use crate::control::{
    build_initialize_request, control_subtype, next_request_id, wrap_control_request,
};
use crate::error::{ClaudeSdkError, Result};
use crate::message::{Message, UserPrompt};
use crate::process::spawn_cli;
use crate::types::{
    ClaudeAgentOptions, HookCallback, McpCallback, McpCallbackWithContext, PermissionCallback,
};
use alera_agent_transport::JsonTransport;
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::runtime::Handle;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{timeout_at, Duration, Instant};
#[path = "client_controls.rs"]
mod client_controls;
#[path = "client_stream.rs"]
mod client_stream;
type PendingSender = oneshot::Sender<Result<Value>>;

enum TransportCommand {
    Send(Value, oneshot::Sender<Result<()>>),
    Close(oneshot::Sender<Result<()>>),
}

struct ClientInner {
    transport: Mutex<Option<Box<dyn JsonTransport>>>,
    transport_commands: mpsc::Sender<TransportCommand>,
    transport_receiver: Mutex<Option<mpsc::Receiver<TransportCommand>>>,
    pending: Mutex<HashMap<String, PendingSender>>,
    inflight_callbacks: Mutex<HashMap<String, JoinHandle<()>>>,
    hook_callbacks: Mutex<HashMap<String, HookCallback>>,
    permission_callback: Option<PermissionCallback>,
    mcp_callback: Option<McpCallback>,
    mcp_callback_with_context: Option<McpCallbackWithContext>,
    message_tx: Mutex<Option<mpsc::Sender<Result<Message>>>>,
    transport_timeout: Duration,
    reader: Mutex<Option<JoinHandle<()>>>,
    next_request: AtomicU64,
    next_callback: AtomicU64,
    closed: AtomicBool,
    initialized: AtomicBool,
    initialize_lock: Mutex<()>,
    message_overflowed: AtomicBool,
    server_info: std::sync::Mutex<Option<Value>>,
}

pub struct ClaudeClient {
    inner: Arc<ClientInner>,
    options: ClaudeAgentOptions,
    message_rx: Mutex<mpsc::Receiver<Result<Message>>>,
}

impl ClaudeClient {
    pub async fn connect(options: ClaudeAgentOptions) -> Result<Self> {
        options.validate()?;
        let transport = spawn_cli(&options).await?;
        Self::connect_with_boxed_transport(transport, options).await
    }

    pub async fn connect_with_transport<T>(
        transport: T,
        options: ClaudeAgentOptions,
    ) -> Result<Self>
    where
        T: JsonTransport + 'static,
    {
        Self::connect_with_boxed_transport(Box::new(transport), options).await
    }

    pub fn with_transport<T>(transport: T, options: ClaudeAgentOptions) -> Result<Self>
    where
        T: JsonTransport + 'static,
    {
        options.validate()?;
        Ok(Self::new_inner(Box::new(transport), options))
    }

    async fn connect_with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        options: ClaudeAgentOptions,
    ) -> Result<Self> {
        let client = Self::with_boxed_transport(transport, options)?;
        client.start_reader().await;
        if let Err(error) = client.initialize().await {
            let _ = client.close().await;
            return Err(error);
        }
        Ok(client)
    }

    fn with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        options: ClaudeAgentOptions,
    ) -> Result<Self> {
        options.validate()?;
        Ok(Self::new_inner(transport, options))
    }

    fn new_inner(transport: Box<dyn JsonTransport>, options: ClaudeAgentOptions) -> Self {
        let (message_tx, message_rx) = mpsc::channel(128);
        let (transport_commands, transport_receiver) = mpsc::channel(64);
        let inner = Arc::new(ClientInner {
            transport: Mutex::new(Some(transport)),
            transport_commands,
            transport_receiver: Mutex::new(Some(transport_receiver)),
            pending: Mutex::new(HashMap::new()),
            inflight_callbacks: Mutex::new(HashMap::new()),
            hook_callbacks: Mutex::new(HashMap::new()),
            permission_callback: options.permission_callback.clone(),
            mcp_callback: options.mcp_callback.clone(),
            mcp_callback_with_context: options.mcp_callback_with_context.clone(),
            message_tx: Mutex::new(Some(message_tx)),
            transport_timeout: options.initialize_timeout,
            reader: Mutex::new(None),
            next_request: AtomicU64::new(0),
            next_callback: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            initialized: AtomicBool::new(false),
            initialize_lock: Mutex::new(()),
            message_overflowed: AtomicBool::new(false),
            server_info: std::sync::Mutex::new(None),
        });
        Self {
            inner,
            options,
            message_rx: Mutex::new(message_rx),
        }
    }

    pub async fn start_reader(&self) {
        let mut reader = self.inner.reader.lock().await;
        if reader.is_none() {
            let inner = Arc::clone(&self.inner);
            let transport = self.inner.transport.lock().await.take();
            let commands = self.inner.transport_receiver.lock().await.take();
            if let (Some(transport), Some(commands)) = (transport, commands) {
                let shutdown_timeout = self.options.shutdown_timeout;
                let transport_timeout = self.options.initialize_timeout;
                *reader = Some(tokio::spawn(async move {
                    client_stream::transport_loop(
                        inner,
                        transport,
                        commands,
                        shutdown_timeout,
                        transport_timeout,
                    )
                    .await
                }));
            }
        }
    }

    pub async fn initialize(&self) -> Result<Value> {
        let _initialize_guard = self.inner.initialize_lock.lock().await;
        if self.inner.initialized.load(Ordering::Acquire) {
            return Ok(Value::Object(Map::new()));
        }
        self.start_reader().await;
        let mut hooks = Map::new();
        for (event, matchers) in &self.options.hooks {
            let mut wire_matchers = Vec::new();
            for matcher in matchers {
                let mut callback_ids = Vec::new();
                for callback in &matcher.hooks {
                    let id = format!(
                        "hook_{}",
                        self.inner.next_callback.fetch_add(1, Ordering::Relaxed)
                    );
                    self.inner
                        .hook_callbacks
                        .lock()
                        .await
                        .insert(id.clone(), callback.clone());
                    callback_ids.push(Value::String(id));
                }
                let mut wire = Map::new();
                wire.insert(
                    "matcher".into(),
                    matcher
                        .matcher
                        .clone()
                        .map(Value::String)
                        .unwrap_or(Value::Null),
                );
                wire.insert("hookCallbackIds".into(), Value::Array(callback_ids));
                if let Some(timeout) = matcher.timeout {
                    wire.insert("timeout".into(), Value::from(timeout.as_secs_f64()));
                }
                wire_matchers.push(Value::Object(wire));
            }
            hooks.insert(event.clone(), Value::Array(wire_matchers));
        }
        let agents = self
            .options
            .agents
            .iter()
            .filter_map(|(name, agent)| {
                serde_json::to_value(agent)
                    .ok()
                    .map(|value| (name.clone(), value))
            })
            .collect::<Map<_, _>>();
        let (exclude_dynamic_sections, system_prompt_snapshot) = match &self.options.system_prompt {
            Some(crate::types::SystemPrompt::Preset {
                exclude_dynamic_sections,
                snapshot,
                ..
            }) => (*exclude_dynamic_sections, *snapshot),
            Some(crate::types::SystemPrompt::Custom { snapshot, .. }) => (None, *snapshot),
            _ => (None, None),
        };
        let request = build_initialize_request(
            &mut hooks,
            &agents,
            exclude_dynamic_sections,
            system_prompt_snapshot,
            self.options.skills.as_ref(),
            self.options.forward_subagent_text,
        );
        let response = self
            .send_control_request(request, self.options.initialize_timeout)
            .await?;
        *self
            .inner
            .server_info
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(response.clone());
        self.inner.initialized.store(true, Ordering::Release);
        Ok(response)
    }

    pub async fn send_prompt(&self, prompt: impl Into<String>) -> Result<()> {
        self.send_user_message(UserPrompt::text(prompt)).await
    }

    pub async fn send_user_message(&self, prompt: UserPrompt) -> Result<()> {
        if !self.inner.initialized.load(Ordering::Acquire) {
            return Err(ClaudeSdkError::InvalidState(
                "initialize must complete before sending a prompt".into(),
            ));
        }
        self.send_frame(prompt.to_wire(self.options.verbatim_prompts))
            .await
    }

    pub async fn next_message(&self) -> Result<Option<Message>> {
        let mut receiver = self.message_rx.lock().await;
        match receiver.recv().await {
            None if self.inner.message_overflowed.load(Ordering::Acquire) => {
                Err(ClaudeSdkError::Transport(
                    "message queue overflowed; consume messages while the session is running"
                        .into(),
                ))
            }
            None => Ok(None),
            Some(Ok(message)) => Ok(Some(message)),
            Some(Err(error)) => Err(error),
        }
    }

    pub async fn recv(&self) -> Result<Option<Message>> {
        self.next_message().await
    }

    /// What the CLI answered to `initialize` (its commands, output styles,
    /// models and account), like the Python SDK's `get_server_info`. `None`
    /// before initialization.
    pub fn server_info(&self) -> Option<Value> {
        self.inner
            .server_info
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    pub fn is_initialized(&self) -> bool {
        self.inner.initialized.load(Ordering::Acquire)
    }

    pub fn is_closed(&self) -> bool {
        self.inner.closed.load(Ordering::Acquire)
    }

    pub(crate) fn run_end_timeout(&self) -> Duration {
        self.options.run_end_timeout
    }

    pub(crate) fn options_initialize_timeout(&self) -> Duration {
        self.options.initialize_timeout
    }

    pub async fn control_command(
        &self,
        request: Value,
        timeout_duration: Duration,
    ) -> Result<Value> {
        self.send_control_request(request, timeout_duration).await
    }

    async fn send_control_request(
        &self,
        request: Value,
        timeout_duration: Duration,
    ) -> Result<Value> {
        if self.inner.closed.load(Ordering::Acquire) {
            return Err(ClaudeSdkError::Closed);
        }
        let request_id = next_request_id(&self.inner.next_request);
        let (sender, receiver) = oneshot::channel();
        self.inner
            .pending
            .lock()
            .await
            .insert(request_id.clone(), sender);
        let subtype = control_subtype(&request).to_owned();
        let deadline = Instant::now() + timeout_duration;
        match timeout_at(
            deadline,
            self.send_frame(wrap_control_request(&request_id, request)),
        )
        .await
        {
            Err(_) => {
                self.inner.pending.lock().await.remove(&request_id);
                Err(ClaudeSdkError::Timeout {
                    operation: format!("sending control request {subtype}"),
                    timeout_ms: timeout_duration.as_millis() as u64,
                })
            }
            Ok(Err(error)) => {
                self.inner.pending.lock().await.remove(&request_id);
                Err(error)
            }
            Ok(Ok(())) => match timeout_at(deadline, receiver).await {
                Err(_) => {
                    self.inner.pending.lock().await.remove(&request_id);
                    Err(ClaudeSdkError::Timeout {
                        operation: format!("control request {subtype}"),
                        timeout_ms: timeout_duration.as_millis() as u64,
                    })
                }
                Ok(Err(_)) => Err(ClaudeSdkError::Closed),
                Ok(Ok(result)) => result,
            },
        }
    }

    async fn send_frame(&self, frame: Value) -> Result<()> {
        if self.inner.closed.load(Ordering::Acquire) {
            return Err(ClaudeSdkError::Closed);
        }
        let (sender, receiver) = oneshot::channel();
        self.inner
            .transport_commands
            .send(TransportCommand::Send(frame, sender))
            .await
            .map_err(|_| ClaudeSdkError::Closed)?;
        receiver.await.map_err(|_| ClaudeSdkError::Closed)?
    }

    pub async fn close(&self) -> Result<()> {
        self.start_reader().await;
        if self.inner.closed.swap(true, Ordering::AcqRel) {
            if let Some(reader) = self.inner.reader.lock().await.take() {
                let _ = reader.await;
            }
            return Ok(());
        }
        let error = ClaudeSdkError::Closed;
        for (_, sender) in self.inner.pending.lock().await.drain() {
            let _ = sender.send(Err(error.clone()));
        }
        let (sender, receiver) = oneshot::channel();
        let command = TransportCommand::Close(sender);
        let deadline = Instant::now() + self.options.shutdown_timeout;
        let sent = timeout_at(deadline, self.inner.transport_commands.send(command)).await;
        if sent.is_err() {
            if let Some(reader) = self.inner.reader.lock().await.take() {
                reader.abort();
                let _ = reader.await;
            }
            return Err(ClaudeSdkError::Timeout {
                operation: "queueing transport close".into(),
                timeout_ms: self.options.shutdown_timeout.as_millis() as u64,
            });
        }
        if sent.unwrap().is_ok() {
            let close_result = timeout_at(deadline, receiver).await;
            if close_result.is_err() {
                if let Some(reader) = self.inner.reader.lock().await.take() {
                    reader.abort();
                    let _ = reader.await;
                }
                return Err(ClaudeSdkError::Timeout {
                    operation: "transport close".into(),
                    timeout_ms: self.options.shutdown_timeout.as_millis() as u64,
                });
            }
            close_result
                .unwrap()
                .map_err(|_| ClaudeSdkError::Closed)??;
        }
        if let Some(reader) = self.inner.reader.lock().await.take() {
            let _ = reader.await;
        }
        Ok(())
    }
}

impl Drop for ClaudeClient {
    fn drop(&mut self) {
        self.inner.closed.store(true, Ordering::Release);
        if let Ok(mut reader) = self.inner.reader.try_lock() {
            if let Some(task) = reader.take() {
                task.abort();
            }
        }
        abort_callbacks_on_drop(&self.inner);
        if let Ok(mut hooks) = self.inner.hook_callbacks.try_lock() {
            hooks.clear();
        }
        if let Ok(mut message_tx) = self.inner.message_tx.try_lock() {
            message_tx.take();
        }
    }
}

fn abort_callbacks_on_drop(inner: &Arc<ClientInner>) {
    if let Ok(mut callbacks) = inner.inflight_callbacks.try_lock() {
        for (_, task) in callbacks.drain() {
            task.abort();
        }
        return;
    }
    let Ok(runtime) = Handle::try_current() else {
        return;
    };
    let inner = Arc::clone(inner);
    runtime.spawn(async move {
        let mut callbacks = inner.inflight_callbacks.lock().await;
        for (_, task) in callbacks.drain() {
            task.abort();
        }
    });
}
