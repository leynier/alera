#[path = "background_wait.rs"]
mod background_wait;
#[path = "callbacks.rs"]
mod callbacks;
#[path = "canonical_payload.rs"]
mod canonical_payload;
#[path = "failure.rs"]
mod failure;
#[path = "history.rs"]
mod history;
#[path = "lifecycle.rs"]
mod lifecycle;
#[path = "lineage.rs"]
mod lineage;
#[path = "mapping.rs"]
mod mapping;
#[path = "mapping_stream.rs"]
mod mapping_stream;
#[path = "mcp.rs"]
mod mcp;
#[path = "reasoning_effort.rs"]
mod reasoning_effort;
#[path = "runtime_response.rs"]
mod runtime_response;
#[path = "slash_commands.rs"]
mod slash_commands;
#[path = "turns.rs"]
mod turns;
#[path = "user_messages.rs"]
mod user_messages;

use alera_agent_transport::{JsonTransport, TransportError};
use alera_provider_protocol::{
    ApprovalPolicy, EventKind, InteractionMode, InterruptInput, Provider, ProviderCapabilities,
    ProviderError, ProviderEvent, ProviderKind, ProviderRefs, ProviderSession, RawEvent,
    RequestKind, RuntimeMode, RuntimeRequest, RuntimeResponse, SandboxMode, SessionStartInput,
    SessionStatus, StreamKind, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use callbacks::{install_callbacks, PendingResponse, RequestNotice};
use claude_agent_sdk::{ClaudeAgentOptions, ClaudeClient, ClaudeSdkError};
use runtime_response::{resolved_payload, response_matches_request};
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};

const MESSAGE_SOURCE: &str = "claude.sdk.message";
const PERMISSION_SOURCE: &str = "claude.sdk.permission";
// SDK MCP control frames share the SDK message source.
const MCP_SOURCE: &str = MESSAGE_SOURCE;

struct BoxedTransport(Box<dyn JsonTransport>);

#[async_trait]
impl JsonTransport for BoxedTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        self.0.send(message).await
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        self.0.recv().await
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.0.close().await
    }
}

/// Configuration shared by process-backed and injected-transport providers.
#[derive(Clone)]
pub struct ClaudeProviderConfig {
    pub provider_instance_id: String,
    pub options: ClaudeAgentOptions,
}

impl Default for ClaudeProviderConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: "claude".into(),
            options: ClaudeAgentOptions::default(),
        }
    }
}

/// A provider adapter backed by Claude Code's stream-json SDK.
pub struct ClaudeProvider {
    config: ClaudeProviderConfig,
    transport: Option<Box<dyn JsonTransport>>,
    client: Option<ClaudeClient>,
    initialized: bool,
    closed: bool,
    session: Option<ProviderSession>,
    active_turn_id: Arc<Mutex<Option<String>>>,
    thread_id: Arc<Mutex<Option<String>>>,
    request_tx: mpsc::Sender<RequestNotice>,
    request_rx: mpsc::Receiver<RequestNotice>,
    pending: Arc<Mutex<HashMap<String, PendingResponse>>>,
    next_request: Arc<AtomicU64>,
    next_turn: u64,
    queued_events: VecDeque<ProviderEvent>,
    streamed_text_message_ids: std::collections::HashSet<String>,
    streamed_thinking_message_ids: std::collections::HashSet<String>,
    streamed_text_unscoped: bool,
    streamed_thinking_unscoped: bool,
    stream_message_id: Option<String>,
    open_items: HashMap<String, String>,
    stream_items: HashMap<String, String>,
    session_effort: Option<String>,
    // The permission mode a non-plan turn returns to after Alera's plan mode.
    base_permission_mode: Option<String>,
    plan_interaction: Arc<AtomicBool>,
    file_checkpointing: bool,
    fork_source_native_thread_id: Option<String>,
    pending_user_prompt: Option<user_messages::UserPromptCorrelation>,
    turn_failure: failure::TurnFailureEvidence,
    // `initialize` described the commands, so `system/init` names are ignored.
    described_commands: bool,
    background_tasks: background_wait::BackgroundTasks,
}

fn sdk_error(error: ClaudeSdkError) -> ProviderError {
    match error {
        ClaudeSdkError::Transport(message) => ProviderError::Protocol(message),
        ClaudeSdkError::Closed => ProviderError::Closed,
        ClaudeSdkError::Timeout { operation, .. } => ProviderError::Timeout { operation },
        other => ProviderError::Protocol(other.to_string()),
    }
}

#[async_trait]
impl Provider for ClaudeProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Claude
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: alera_provider_protocol::McpInjectionCapabilities {
                stdio: true,
                http: true,
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: false,
            streaming: true,
            native_turn_ids: false,
            multiple_threads: false,
            model_switch: false,
            steer: false,
            snapshot: false,
            rollback: false,
            fork: true,
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }

    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        reasoning_effort::capabilities()
    }

    fn native_history_capabilities(&self) -> alera_provider_protocol::NativeHistoryCapabilities {
        alera_provider_protocol::NativeHistoryCapabilities {
            file_checkpointing: true,
            fork_at_message: true,
            rewind_files: self.file_checkpointing && self.session.is_some() && !self.closed,
            ..Default::default()
        }
    }

    async fn fork_session(
        &mut self,
        input: alera_provider_protocol::NativeForkInput,
    ) -> Result<alera_provider_protocol::NativeForkResult, ProviderError> {
        self.fork_native(input).await
    }

    async fn rewind_files(
        &mut self,
        input: alera_provider_protocol::NativeRewindFilesInput,
    ) -> Result<alera_provider_protocol::NativeRewindFilesResult, ProviderError> {
        self.rewind_native_files(input).await
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Err(ProviderError::Closed);
        }
        self.initialized = true;
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        if !self.initialized {
            return Err(ProviderError::InvalidState(
                "initialize must be called before start_session".into(),
            ));
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Claude provider supports one session at a time".into(),
            ));
        }
        let options = self.build_options(&input)?;
        self.session_effort = options.effort.clone();
        let plan_at_start = options.permission_mode.as_deref() == Some("plan")
            && input.options.get("interactionMode").and_then(Value::as_str) == Some("plan");
        self.plan_interaction.store(plan_at_start, Ordering::SeqCst);
        self.base_permission_mode = if plan_at_start {
            Some("default".into())
        } else {
            options.permission_mode.clone()
        };
        self.file_checkpointing = options.enable_file_checkpointing;
        *self.thread_id.lock().await = Some(input.thread_id.clone());
        let client = if let Some(transport) = self.transport.take() {
            let client = ClaudeClient::with_transport(BoxedTransport(transport), options)
                .map_err(sdk_error)?;
            client.initialize().await.map_err(sdk_error)?;
            client
        } else {
            ClaudeClient::connect(options).await.map_err(sdk_error)?
        };
        self.client = Some(client);
        let native_thread_id = if self.fork_source_native_thread_id.is_some() {
            format!("pending:{}", input.thread_id)
        } else {
            input
                .resume_thread_id
                .clone()
                .unwrap_or_else(|| format!("pending:{}", input.thread_id))
        };
        let session = ProviderSession {
            provider: ProviderKind::Claude,
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id,
            status: SessionStatus::Ready,
            model: input.model.or_else(|| self.config.options.model.clone()),
            cwd: input.cwd.or_else(|| self.config.options.cwd.clone()),
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        self.queue_session_events();
        self.queue_initialize_commands();
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.send_native_turn(input).await
    }

    async fn await_background_tasks(
        &mut self,
        task_ids: &[String],
        _awaited: bool,
    ) -> Result<Vec<String>, ProviderError> {
        if self.session.is_none() || self.closed {
            return Err(ProviderError::InvalidState(
                "session has not started".into(),
            ));
        }
        // The runtime holds the marks; Claude itself never needs them.
        Ok(self.background_tasks.matching(task_ids))
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let session = self
            .session
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "interrupt threadId does not match session".into(),
            ));
        }
        let active = self.active_turn_id.lock().await.clone();
        if let Some(turn_id) = &input.turn_id {
            if active.as_deref() != Some(turn_id.as_str()) {
                return Err(ProviderError::Validation(
                    "interrupt turnId does not match active turn".into(),
                ));
            }
        }
        if active.is_none() {
            return Err(ProviderError::InvalidState(
                "no active turn to interrupt".into(),
            ));
        }
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("session client is unavailable".into()))?
            .interrupt()
            .await
            .map_err(sdk_error)
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        let request_id = response.request_id().to_string();
        let (pending, request) = {
            let mut pending_map = self.pending.lock().await;
            let pending = pending_map.get(&request_id).ok_or_else(|| {
                ProviderError::Validation(format!("unknown runtime request {request_id}"))
            })?;
            let request = match pending {
                PendingResponse::Permission { request, .. }
                | PendingResponse::Mcp { request, .. } => request.clone(),
            };
            if !response_matches_request(&request, &response) {
                return Err(ProviderError::Validation(format!(
                    "runtime response does not match request type {:?}",
                    request.kind
                )));
            }
            let pending = pending_map.remove(&request_id).ok_or_else(|| {
                ProviderError::Validation(format!("unknown runtime request {request_id}"))
            })?;
            (pending, request)
        };
        let response_for_event = response.clone();
        let native_request_id = match &pending {
            PendingResponse::Permission {
                native_request_id, ..
            }
            | PendingResponse::Mcp {
                native_request_id, ..
            } => native_request_id.clone(),
        };
        match pending {
            PendingResponse::Permission { sender, .. } | PendingResponse::Mcp { sender, .. } => {
                sender.send(response).map_err(|_| {
                    ProviderError::InvalidState(
                        "runtime request callback is no longer waiting".into(),
                    )
                })?;
            }
        }
        let (kind, payload) = resolved_payload(&request, &response_for_event);
        let source = if request.kind == RequestKind::DynamicToolCall {
            MCP_SOURCE
        } else {
            PERMISSION_SOURCE
        };
        let mut event = self.event(
            kind,
            payload.clone(),
            self.raw_from(source, "control_response", payload),
        );
        event.request_id = Some(request.request_id.to_string());
        event.turn_id = request.turn_id.clone();
        event.item_id = request.item_id.clone();
        event.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: native_request_id,
        });
        event.validate()?;
        self.queue(event);
        Ok(())
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.pending
            .lock()
            .await
            .retain(|_, response| !response.is_closed());
        loop {
            if let Some(event) = self.pop_validated()? {
                return Ok(Some(event));
            }
            if self.closed {
                return Ok(None);
            }
            let message = {
                let client = self
                    .client
                    .as_ref()
                    .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
                let message_future = client.next_message();
                tokio::select! {
                    notice = self.request_rx.recv() => {
                        if let Some(notice) = notice {
                            let request_id = notice.request.request_id.to_string();
                            let pending = self.pending.lock().await;
                            let live = pending
                                .get(&request_id)
                                .is_some_and(|response| !response.is_closed());
                            drop(pending);
                            if !live {
                                continue;
                            }
                            let request = notice.request;
                            let (kind, payload) = if request.kind
                                == alera_provider_protocol::RequestKind::ToolUserInput
                            {
                                (
                                    EventKind::UserInputRequested,
                                    json!({
                                        "questions": request.questions,
                                        "responseMode": "message",
                                    }),
                                )
                            } else {
                                (EventKind::RequestOpened, request.payload.clone())
                            };
                            let mut event = self
                                .event(
                                    kind,
                                    payload.clone(),
                                    self.raw_from(notice.source, "control_request", notice.raw),
                                )
                                .with_request(request);
                            event.provider_refs = Some(ProviderRefs {
                                provider_turn_id: None,
                                provider_item_id: event.item_id.clone(),
                                provider_request_id: notice.native_request_id,
                            });
                            event.validate()?;
                            return Ok(Some(event));
                        }
                        return Ok(None);
                    }
                    result = message_future => result.map_err(sdk_error)?,
                }
            };
            if let Some(message) = message {
                let events = self.map_message(message);
                self.queued_events.extend(events);
            } else {
                return Ok(None);
            }
        }
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        self.pending.lock().await.clear();
        self.pending_user_prompt = None;
        self.background_tasks.clear();
        if let Some(client) = &self.client {
            client.close().await.map_err(sdk_error)?;
        } else if let Some(mut transport) = self.transport.take() {
            transport.close().await.map_err(ProviderError::Transport)?;
        }
        if self.session.is_some() {
            self.queue(self.event(
                EventKind::SessionExited,
                json!({
                    "reason": "provider closed",
                    "recoverable": false,
                    "exitKind": "graceful"
                }),
                self.raw("session", json!({ "status": "stopped" })),
            ));
            if let Some(session) = &mut self.session {
                session.status = SessionStatus::Stopped;
                session.active_turn_id = None;
            }
        }
        self.closed = true;
        Ok(())
    }
}
