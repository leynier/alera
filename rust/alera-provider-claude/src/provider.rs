#[path = "callbacks.rs"]
mod callbacks;
#[path = "canonical_payload.rs"]
mod canonical_payload;
#[path = "lifecycle.rs"]
mod lifecycle;
#[path = "mapping.rs"]
mod mapping;
#[path = "mapping_stream.rs"]
mod mapping_stream;
#[path = "mcp.rs"]
mod mcp;
#[path = "runtime_response.rs"]
mod runtime_response;

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
use std::sync::atomic::{AtomicU64, Ordering};
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
            fork: false,
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
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
        let native_thread_id = input
            .resume_thread_id
            .clone()
            .unwrap_or_else(|| format!("pending:{}", input.thread_id));
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
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        if !input.attachments.is_empty() {
            return Err(ProviderError::Unsupported(
                "Claude Code turns do not support provider attachments".into(),
            ));
        }
        if !input.options.is_empty() {
            return Err(ProviderError::Unsupported(
                "Claude Code turn options are not supported by this adapter".into(),
            ));
        }
        if input.interaction_mode != InteractionMode::Default {
            return Err(ProviderError::Unsupported(
                "Claude Code per-turn interaction mode is not supported by this adapter".into(),
            ));
        }
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "turn threadId does not match session".into(),
            ));
        }
        if session.active_turn_id.is_some()
            || matches!(
                session.status,
                SessionStatus::Running | SessionStatus::Waiting
            )
        {
            return Err(ProviderError::InvalidState(
                "cannot start a Claude turn while another turn is active or awaiting an event"
                    .into(),
            ));
        }
        if self.closed {
            return Err(ProviderError::Closed);
        }
        if let Some(model) = &input.model {
            if session.model.as_deref() != Some(model.as_str()) {
                return Err(ProviderError::Unsupported(
                    "Claude model switching is not enabled by this adapter".into(),
                ));
            }
        }
        if self.client.is_none() {
            return Err(ProviderError::InvalidState(
                "session client is unavailable".into(),
            ));
        }
        let next_turn = self.next_turn + 1;
        let turn_id = format!("turn:claude:{next_turn}");
        let previous_streamed_text_message_ids = self.streamed_text_message_ids.clone();
        let previous_streamed_thinking_message_ids = self.streamed_thinking_message_ids.clone();
        let previous_streamed_text_unscoped = self.streamed_text_unscoped;
        let previous_streamed_thinking_unscoped = self.streamed_thinking_unscoped;
        let previous_stream_message_id = self.stream_message_id.clone();
        let previous_open_items = std::mem::take(&mut self.open_items);
        let previous_stream_items = std::mem::take(&mut self.stream_items);
        let previous_status = session.status;
        let previous_active_turn_id = session.active_turn_id.clone();
        self.streamed_text_message_ids.clear();
        self.streamed_thinking_message_ids.clear();
        self.streamed_text_unscoped = false;
        self.streamed_thinking_unscoped = false;
        self.stream_message_id = None;
        self.open_items = HashMap::new();
        self.stream_items = HashMap::new();
        *self.active_turn_id.lock().await = Some(turn_id.clone());
        if let Some(session) = &mut self.session {
            session.status = SessionStatus::Running;
            session.active_turn_id = Some(turn_id.clone());
        }
        let send_result = self
            .client
            .as_ref()
            .expect("client checked before turn state setup")
            .send_prompt(input.input)
            .await;
        if let Err(error) = send_result {
            *self.active_turn_id.lock().await = previous_active_turn_id.clone();
            self.streamed_text_message_ids = previous_streamed_text_message_ids;
            self.streamed_thinking_message_ids = previous_streamed_thinking_message_ids;
            self.streamed_text_unscoped = previous_streamed_text_unscoped;
            self.streamed_thinking_unscoped = previous_streamed_thinking_unscoped;
            self.stream_message_id = previous_stream_message_id;
            self.open_items = previous_open_items;
            self.stream_items = previous_stream_items;
            if let Some(session) = &mut self.session {
                session.status = previous_status;
                session.active_turn_id = previous_active_turn_id;
            }
            self.pending.lock().await.clear();
            return Err(sdk_error(error));
        }
        self.next_turn = next_turn;
        let mut payload = json!({});
        if let Some(model) = session.model {
            payload["model"] = Value::String(model);
        }
        self.queue(self.event(
            EventKind::TurnStarted,
            payload.clone(),
            self.raw("turn", payload),
        ));
        Ok(TurnStartResult {
            thread_id: input.thread_id,
            turn_id,
            native_turn_id: None,
        })
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
