use crate::actor::{self, Command, Inner};
use crate::error::{MuseSdkError, Result};
use crate::session::SessionState;
use crate::types::{
    CommandAck, InitializeResult, ModelInfo, MuseClientOptions, MuseFrame, SessionSummary,
};
use crate::wire;
use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::timeout;

#[derive(Debug, Clone)]
struct CommandMemory {
    signature: String,
    ack: Option<String>,
}

/// A transport-backed client for the public Muse Session Protocol.
pub struct MuseClient {
    inner: Arc<Inner>,
    options: MuseClientOptions,
    initialized: AtomicBool,
    initialize_lock: Mutex<()>,
    initialize_result: Mutex<Option<InitializeResult>>,
    state: Mutex<SessionState>,
    command_memory: Mutex<HashMap<String, CommandMemory>>,
}

impl MuseClient {
    pub async fn connect(options: MuseClientOptions) -> Result<Self> {
        let mut env = options.env.clone();
        if let Some(login_environment) =
            alera_core::login_shell_environment::login_shell_command_environment().await
        {
            for (key, value) in login_environment {
                env.entry(key.into()).or_insert_with(|| value.into());
            }
        }
        let process_config = ProcessConfig {
            executable: options.executable.clone(),
            args: options.args.clone(),
            cwd: options.cwd.clone(),
            env,
            max_frame_bytes: options.max_frame_bytes,
            shutdown_timeout: options.shutdown_timeout,
        };
        let process = JsonLineProcess::spawn(process_config).await?;
        Self::connect_with_boxed_transport(Box::new(process), options).await
    }

    pub async fn connect_with_transport<T: JsonTransport + 'static>(
        transport: T,
        options: MuseClientOptions,
    ) -> Result<Self> {
        Self::connect_with_boxed_transport(Box::new(transport), options).await
    }

    pub fn with_transport<T: JsonTransport + 'static>(
        transport: T,
        options: MuseClientOptions,
    ) -> Result<Self> {
        Self::with_boxed_transport(Box::new(transport), options)
    }

    pub fn with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        options: MuseClientOptions,
    ) -> Result<Self> {
        let (commands, command_rx) = mpsc::channel(64);
        let (frame_tx, frame_rx) = mpsc::channel(128);
        let inner = Arc::new(Inner {
            commands,
            frames: Mutex::new(frame_rx),
            next_request: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            send_timeout: options.request_timeout,
            shutdown_timeout: options.shutdown_timeout,
        });
        let actor_inner = Arc::clone(&inner);
        tokio::spawn(actor::run(actor_inner, transport, command_rx, frame_tx));
        Ok(Self {
            inner,
            options,
            initialized: AtomicBool::new(false),
            initialize_lock: Mutex::new(()),
            initialize_result: Mutex::new(None),
            state: Mutex::new(SessionState::default()),
            command_memory: Mutex::new(HashMap::new()),
        })
    }

    async fn connect_with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        options: MuseClientOptions,
    ) -> Result<Self> {
        let client = Self::with_boxed_transport(transport, options)?;
        client.initialize().await?;
        Ok(client)
    }

    pub async fn initialize(&self) -> Result<InitializeResult> {
        let _guard = self.initialize_lock.lock().await;
        if let Some(result) = self.initialize_result.lock().await.clone() {
            return Ok(result);
        }
        let params = serde_json::json!({
            "clientInfo": self.options.client_info(),
            "capabilities": self.options.capabilities.clone(),
        });
        let raw = self.request("initialize", params).await?;
        let result = InitializeResult::from_value(raw);
        self.notify("initialized", None).await?;
        self.initialized.store(true, Ordering::Release);
        *self.initialize_result.lock().await = Some(result.clone());
        Ok(result)
    }

    pub fn is_initialized(&self) -> bool {
        self.initialized.load(Ordering::Acquire)
    }

    pub fn is_closed(&self) -> bool {
        self.inner.closed.load(Ordering::Acquire)
    }

    /// Return the immutable handshake result, including granted capabilities.
    pub async fn initialize_result(&self) -> Option<InitializeResult> {
        self.initialize_result.lock().await.clone()
    }

    /// Return the server grants from the completed handshake.
    pub async fn granted_capabilities(&self) -> Vec<String> {
        self.initialize_result
            .lock()
            .await
            .as_ref()
            .map(|result| result.granted_capabilities.clone())
            .unwrap_or_default()
    }

    pub async fn next_frame(&self) -> Result<Option<MuseFrame>> {
        let mut frames = self.inner.frames.lock().await;
        let frame = match frames.recv().await {
            None => Ok(None),
            Some(frame) => frame.map(Some),
        }?;
        drop(frames);
        if let Some(frame) = frame.as_ref() {
            if let (Some(method), Some(params)) = (frame.method(), frame.params()) {
                self.state.lock().await.apply(method, params);
            }
        }
        Ok(frame)
    }

    pub async fn session_state(&self) -> SessionState {
        self.state.lock().await.clone()
    }

    pub async fn request(&self, method: &str, params: Value) -> Result<Value> {
        self.require_initialized(method)?;
        let id = Value::from(self.inner.next_request.fetch_add(1, Ordering::Relaxed) + 1);
        let frame = wire::request(id.as_u64().unwrap_or(1), method, params);
        let (response, receiver) = oneshot::channel();
        self.inner
            .commands
            .send(Command::Request {
                id: id.clone(),
                frame,
                response,
            })
            .await
            .map_err(|_| MuseSdkError::Closed)?;
        match timeout(self.options.request_timeout, receiver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(MuseSdkError::Closed),
            Err(_) => {
                let _ = self
                    .inner
                    .commands
                    .send(Command::Cancel(wire::id_key(&id)))
                    .await;
                Err(MuseSdkError::Timeout {
                    operation: method.into(),
                })
            }
        }
    }

    pub async fn notify(&self, method: &str, params: Option<Value>) -> Result<()> {
        self.require_initialized(method)?;
        let (done, receiver) = oneshot::channel();
        self.inner
            .commands
            .send(Command::Notify {
                frame: wire::notification(method, params),
                done,
            })
            .await
            .map_err(|_| MuseSdkError::Closed)?;
        timeout(self.options.request_timeout, receiver)
            .await
            .map_err(|_| MuseSdkError::Timeout {
                operation: method.into(),
            })?
            .map_err(|_| MuseSdkError::Closed)?
    }

    pub async fn respond_server_request(&self, id: Value, result: Value) -> Result<()> {
        let (done, receiver) = oneshot::channel();
        self.inner
            .commands
            .send(Command::Reply {
                frame: wire::response(&id, result),
                done,
            })
            .await
            .map_err(|_| MuseSdkError::Closed)?;
        let result = timeout(self.options.request_timeout, receiver)
            .await
            .map_err(|_| MuseSdkError::Timeout {
                operation: "reply".into(),
            })?
            .map_err(|_| MuseSdkError::Closed)?;
        result
    }

    pub async fn command(
        &self,
        method: &str,
        mut params: Map<String, Value>,
        command_id: Option<String>,
    ) -> Result<CommandAck> {
        let command_id = command_id.unwrap_or_else(|| uuid::Uuid::now_v7().to_string());
        params.insert("commandId".into(), Value::String(command_id.clone()));
        let params_value = Value::Object(params);
        let signature =
            wire::canonical(&serde_json::json!({"method": method, "params": params_value}));
        let mut memory = self.command_memory.lock().await;
        if let Some(previous) = memory.get(&command_id) {
            if previous.signature != signature {
                return Err(MuseSdkError::Protocol(format!(
                    "commandId {command_id} was reused with a different payload"
                )));
            }
            if let Some(ack) = &previous.ack {
                let value: Value = serde_json::from_str(ack)
                    .map_err(|error| MuseSdkError::Protocol(error.to_string()))?;
                return Ok(CommandAck::from_value(value));
            }
        } else {
            memory.insert(
                command_id.clone(),
                CommandMemory {
                    signature,
                    ack: None,
                },
            );
        }
        drop(memory);
        let value = self.request(method, params_value).await?;
        if let Some(echo) = value.get("commandId").and_then(Value::as_str) {
            if echo != command_id {
                return Err(MuseSdkError::Protocol(format!(
                    "{method} did not echo commandId {command_id}"
                )));
            }
        }
        let ack_json = serde_json::to_string(&value)
            .map_err(|error| MuseSdkError::Protocol(error.to_string()))?;
        self.command_memory
            .lock()
            .await
            .entry(command_id)
            .and_modify(|entry| entry.ack = Some(ack_json));
        Ok(CommandAck::from_value(value))
    }

    pub async fn start_session(&self, params: Map<String, Value>) -> Result<SessionSummary> {
        let result = self.command("session/start", params, None).await?;
        let summary = result
            .raw
            .get("session")
            .cloned()
            .and_then(SessionSummary::from_value)
            .ok_or_else(|| MuseSdkError::Protocol("session/start omitted session".into()))?;
        self.state.lock().await.apply_snapshot(&result.raw);
        Ok(summary)
    }

    pub async fn resume_session(&self, params: Map<String, Value>) -> Result<SessionSummary> {
        let result = self.command("session/resume", params, None).await?;
        let summary = result
            .raw
            .get("session")
            .cloned()
            .and_then(SessionSummary::from_value)
            .ok_or_else(|| MuseSdkError::Protocol("session/resume omitted session".into()))?;
        self.state.lock().await.apply_snapshot(&result.raw);
        Ok(summary)
    }

    pub async fn start_turn(
        &self,
        session_id: &str,
        input: Vec<Value>,
        display_text: Option<&str>,
    ) -> Result<CommandAck> {
        let mut params = Map::new();
        params.insert("sessionId".into(), Value::String(session_id.into()));
        params.insert("input".into(), Value::Array(input));
        if let Some(text) = display_text {
            params.insert("displayText".into(), Value::String(text.into()));
        }
        self.command("turn/start", params, None).await
    }

    pub async fn cancel_turn(&self, session_id: &str, turn_id: &str) -> Result<CommandAck> {
        let mut params = Map::new();
        params.insert("sessionId".into(), Value::String(session_id.into()));
        params.insert("turnId".into(), Value::String(turn_id.into()));
        self.command("turn/cancel", params, None).await
    }

    pub async fn interrupt_turn(&self, session_id: &str, turn_id: &str) -> Result<CommandAck> {
        let mut params = Map::new();
        params.insert("sessionId".into(), Value::String(session_id.into()));
        params.insert("turnId".into(), Value::String(turn_id.into()));
        self.command("turn/interrupt", params, None).await
    }

    pub async fn set_model(&self, session_id: &str, model_id: &str) -> Result<CommandAck> {
        let mut model = Map::new();
        model.insert("modelId".into(), Value::String(model_id.into()));
        let mut params = Map::new();
        params.insert("sessionId".into(), Value::String(session_id.into()));
        params.insert("model".into(), Value::Object(model));
        self.command("session/setModel", params, None).await
    }

    pub async fn set_approval_mode(&self, session_id: &str, mode: &str) -> Result<CommandAck> {
        let mut params = Map::new();
        params.insert("sessionId".into(), Value::String(session_id.into()));
        params.insert("mode".into(), Value::String(mode.into()));
        self.command("session/setApprovalMode", params, None).await
    }

    pub async fn model_list(&self, session_id: &str) -> Result<Vec<ModelInfo>> {
        let result = self
            .request("model/list", serde_json::json!({"sessionId": session_id}))
            .await?;
        Ok(result
            .get("models")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|value| serde_json::from_value(value.clone()).ok())
            .collect())
    }

    pub async fn close(&self) -> Result<()> {
        if self.inner.closed.swap(true, Ordering::AcqRel) {
            return Ok(());
        }
        let (done, receiver) = oneshot::channel();
        self.inner
            .commands
            .send(Command::Close(done))
            .await
            .map_err(|_| MuseSdkError::Closed)?;
        timeout(self.options.shutdown_timeout, receiver)
            .await
            .map_err(|_| MuseSdkError::Timeout {
                operation: "close".into(),
            })?
            .map_err(|_| MuseSdkError::Closed)??;
        Ok(())
    }

    fn require_initialized(&self, method: &str) -> Result<()> {
        if self.inner.closed.load(Ordering::Acquire) {
            return Err(MuseSdkError::Closed);
        }
        if !matches!(method, "initialize" | "initialized")
            && !self.initialized.load(Ordering::Acquire)
        {
            return Err(MuseSdkError::InvalidState(
                "initialize must complete before using the MSP session".into(),
            ));
        }
        Ok(())
    }
}

impl Drop for MuseClient {
    fn drop(&mut self) {
        if self.inner.closed.swap(true, Ordering::AcqRel) {
            return;
        }
        let (done, _receiver) = oneshot::channel();
        let _ = self.inner.commands.try_send(Command::Close(done));
    }
}
