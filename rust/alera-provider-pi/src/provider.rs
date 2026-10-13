use crate::mcp_extension::McpExtensionLease;
use crate::{
    config::PiProviderConfig,
    events, lifecycle, rpc, runtime,
    runtime::{image_inputs, native_thread_id, state_model, user_input_payload},
};
use alera_agent_transport::{JsonLineProcess, JsonTransport};
use alera_provider_protocol::{
    ApprovalDecision, InteractionMode, InterruptInput, Provider, ProviderCapabilities,
    ProviderError, ProviderEvent, ProviderKind, ProviderSession, RequestId, RuntimeResponse,
    SessionStartInput, SessionStatus, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use serde_json::{json, Map, Value};
use std::collections::{HashMap, VecDeque};

#[derive(Debug, Clone)]
pub(crate) struct PendingCall {
    pub command: String,
}

#[derive(Debug, Clone)]
pub(crate) struct PendingUiRequest {
    pub native_id: RequestId,
    pub method: String,
    pub request: alera_provider_protocol::RuntimeRequest,
    pub expires_at: Option<std::time::Instant>,
}

/// Pi's RPC adapter. The generic transport makes the provider deterministic in
/// tests while the process constructor uses the shared bounded JSONL process.
pub struct PiProvider<T> {
    pub(crate) transport: T,
    pub(crate) config: PiProviderConfig,
    pub(crate) initialized: bool,
    pub(crate) closed: bool,
    pub(crate) next_request_id: i64,
    pub(crate) next_turn_id: u64,
    pub(crate) pending_calls: HashMap<RequestId, PendingCall>,
    pub(crate) pending_order: VecDeque<RequestId>,
    pub(crate) pending_ui: HashMap<RequestId, PendingUiRequest>,
    pub(crate) queued_messages: VecDeque<Value>,
    pub(crate) queued_events: VecDeque<ProviderEvent>,
    pub(crate) session: Option<ProviderSession>,
    pub(crate) native_state: Value,
    pub(crate) interrupt_requested: bool,
    pub(crate) available_models: Vec<Value>,
    pub(crate) settle_message: Option<Value>,
    pub(crate) baseline_model: Option<String>,
    pub(crate) prompt_failure: Option<Value>,
    pub(crate) session_exit_emitted: bool,
    pub(crate) mcp_extension: Option<McpExtensionLease>,
}

impl PiProvider<JsonLineProcess> {
    /// Launches `pi --mode rpc` through the shared windowless process boundary.
    pub async fn spawn(config: PiProviderConfig) -> Result<Self, ProviderError> {
        config
            .validate_launch()
            .map_err(ProviderError::Validation)?;
        let extension = McpExtensionLease::prepare(&config.mcp_servers)?;
        let mut process_config = config.process_config();
        if let Some(extension) = &extension {
            extension.configure(&mut process_config);
        }
        let process = match JsonLineProcess::spawn(process_config).await {
            Ok(process) => process,
            Err(error) => return Err(error.into()),
        };
        let mut provider = Self::new(process, config);
        provider.mcp_extension = extension;
        Ok(provider)
    }
}

#[async_trait]
impl<T: JsonTransport> Provider for PiProvider<T> {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Other("pi".into())
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: alera_provider_protocol::McpInjectionCapabilities {
                stdio: true,
                http: false,
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: false,
            streaming: true,
            native_turn_ids: false,
            multiple_threads: false,
            model_switch: true,
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
        self.ensure_open()?;
        self.config
            .validate_launch()
            .map_err(ProviderError::Validation)?;
        if self.initialized {
            return Ok(());
        }
        let state = self.call("get_state", Value::Object(Map::new())).await?;
        self.native_state = state;
        self.initialized = true;
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Pi provider supports one session per connection".into(),
            ));
        }
        self.validate_policy(&input)?;
        self.validate_mcp_servers(&input)?;
        self.initialize().await?;

        let (lifecycle_command, lifecycle) = if let Some(resume) = &input.resume_thread_id {
            let lifecycle = self
                .call("switch_session", json!({ "sessionPath": resume }))
                .await?;
            ("switch_session", lifecycle)
        } else {
            ("get_state", self.native_state.clone())
        };
        if lifecycle
            .get("cancelled")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            return Err(ProviderError::Protocol(
                "Pi cancelled the requested session change".into(),
            ));
        }
        if input.resume_thread_id.is_some() {
            self.native_state = self.call("get_state", Value::Object(Map::new())).await?;
        } else {
            self.native_state = lifecycle.clone();
        }
        let native_thread_id = native_thread_id(&self.native_state).ok_or_else(|| {
            ProviderError::Protocol("Pi get_state returned no sessionFile or sessionId".into())
        })?;

        self.baseline_model = state_model(&self.native_state);
        let requested_model = input
            .model
            .clone()
            .or_else(|| self.config.model.clone())
            .filter(|model| model != "default");
        let model = if let Some(model) = requested_model {
            self.set_model(&model).await?;
            Some(model)
        } else {
            state_model(&self.native_state)
        };
        let cwd = input.cwd.or_else(|| self.config.cwd.clone());
        let session = ProviderSession {
            provider: self.kind(),
            provider_instance_id: self.config.instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id: native_thread_id.clone(),
            status: SessionStatus::Ready,
            model,
            cwd,
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        self.queue_lifecycle_events(&session, lifecycle_command);
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        if !input.options.is_empty() {
            return Err(ProviderError::Unsupported(
                "Pi turn options are not supported by the RPC adapter".into(),
            ));
        }
        if input.interaction_mode == InteractionMode::Plan {
            return Err(ProviderError::Unsupported(
                "Pi does not expose a structured plan interaction mode".into(),
            ));
        }
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Pi session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "turn threadId does not match the active Pi session".into(),
            ));
        }
        if session.active_turn_id.is_some()
            || matches!(
                session.status,
                SessionStatus::Running | SessionStatus::Waiting
            )
        {
            return Err(ProviderError::InvalidState(
                "cannot start a Pi turn while another turn is active".into(),
            ));
        }
        if let Some(requested_model) = input.model.as_deref() {
            let model = if requested_model == "default" {
                self.baseline_model.as_deref()
            } else {
                Some(requested_model)
            }
            .map(ToOwned::to_owned);
            if let Some(model) = model {
                if session.model.as_deref() != Some(model.as_str()) {
                    self.set_model(&model).await?;
                    if let Some(active) = self.session.as_mut() {
                        active.model = Some(model);
                    }
                }
            }
        }
        let images = image_inputs(&input)?;
        let turn_id = self.next_turn();
        let mut params = Map::new();
        params.insert("message".into(), Value::String(input.input));
        if !images.is_empty() {
            params.insert("images".into(), Value::Array(images));
        }
        self.transport
            .send(rpc::fire_and_forget("prompt", params))
            .await?;
        if let Some(active) = self.session.as_mut() {
            active.status = SessionStatus::Running;
            active.active_turn_id = Some(turn_id.clone());
        }
        self.interrupt_requested = false;
        self.prompt_failure = None;
        Ok(TurnStartResult {
            thread_id: session.thread_id,
            turn_id,
            native_turn_id: None,
        })
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Pi session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "interrupt threadId does not match the active Pi session".into(),
            ));
        }
        let active = session
            .active_turn_id
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("no active Pi turn to interrupt".into()))?;
        if let Some(turn_id) = input.turn_id {
            if turn_id != active {
                return Err(ProviderError::Validation(
                    "interrupt turnId does not match the active Pi turn".into(),
                ));
            }
        }
        self.interrupt_requested = true;
        // Pi's abort response is only an acknowledgement. The running turn
        // remains active until the later `agent_settled` event.
        let _ = self.call("abort", Value::Object(Map::new())).await?;
        Ok(())
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let request_id = response.request_id().clone();
        let pending =
            self.pending_ui.get(&request_id).cloned().ok_or_else(|| {
                ProviderError::InvalidState("unknown Pi runtime request id".into())
            })?;
        let payload = match response {
            RuntimeResponse::Approval {
                decision,
                updated_input,
                ..
            } => {
                if updated_input.is_some() || pending.method != "confirm" {
                    return Err(ProviderError::Validation(
                        "Pi approval response does not match the pending request".into(),
                    ));
                }
                match decision {
                    ApprovalDecision::Accept => json!({ "confirmed": true }),
                    ApprovalDecision::AcceptForSession | ApprovalDecision::AcceptAlways => {
                        return Err(ProviderError::Unsupported(
                            "Pi cannot persist an approval decision for a session or always".into(),
                        ));
                    }
                    ApprovalDecision::Decline => json!({ "confirmed": false }),
                    ApprovalDecision::Cancel => json!({ "cancelled": true }),
                }
            }
            RuntimeResponse::UserInput { answers, .. } => {
                if pending.method == "confirm" {
                    return Err(ProviderError::Validation(
                        "Pi user input response does not match an approval request".into(),
                    ));
                }
                user_input_payload(&answers, &pending.request.questions)?
            }
            RuntimeResponse::Elicitation { .. } | RuntimeResponse::Native { .. } => {
                return Err(ProviderError::Unsupported(
                    "Pi runtime requests accept approval or user-input responses only".into(),
                ))
            }
        };
        if pending
            .expires_at
            .is_some_and(|deadline| deadline <= std::time::Instant::now())
        {
            let resolved = self
                .complete_ui_request(&request_id, json!({ "cancelled": true }))
                .await?;
            self.queued_events.push_back(resolved);
            return Err(ProviderError::InvalidState(
                "Pi runtime request has expired".into(),
            ));
        }
        let resolved = self.complete_ui_request(&request_id, payload).await?;
        self.queued_events.push_back(resolved);
        Ok(())
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.ensure_open()?;
        if self.session.is_none() {
            return Err(ProviderError::InvalidState(
                "start a Pi session before consuming events".into(),
            ));
        }
        if let Some(event) = self.expire_ui_requests().await? {
            event.validate()?;
            return Ok(Some(event));
        }
        if let Some(event) = self.queued_events.pop_front() {
            event.validate()?;
            return Ok(Some(event));
        }
        if let Some(message) = self.prompt_failure.take() {
            let event = lifecycle::prompt_failed(self, message);
            self.mark_terminal(false);
            event.validate()?;
            return Ok(Some(event));
        }
        if let Some(message) = self.settle_message.take() {
            let state = self.call("get_state", Value::Object(Map::new())).await?;
            if runtime::state_is_idle(&state) {
                let event = events::agent_settled(self, message)?;
                self.mark_terminal(false);
                event.validate()?;
                return Ok(Some(event));
            }
            self.settle_message = Some(message);
        }
        loop {
            let message = if let Some(message) = self.queued_messages.pop_front() {
                message
            } else {
                let received = match self.transport.recv().await {
                    Ok(received) => received,
                    Err(error) => {
                        self.pending_calls.clear();
                        self.pending_order.clear();
                        self.pending_ui.clear();
                        return Err(error.into());
                    }
                };
                let Some(message) = received else {
                    self.pending_calls.clear();
                    self.pending_order.clear();
                    self.pending_ui.clear();
                    if let Some(session) = self.session.as_mut() {
                        session.status = SessionStatus::Stopped;
                        session.active_turn_id = None;
                    }
                    if self.session_exit_emitted {
                        return Ok(None);
                    }
                    self.session_exit_emitted = true;
                    let thread_id = self
                        .session
                        .as_ref()
                        .map(|session| session.thread_id.clone())
                        .unwrap_or_else(|| "pi-pending-thread".into());
                    let event = ProviderEvent::new(
                        self.kind(),
                        self.config.instance_id.clone(),
                        thread_id,
                        alera_provider_protocol::EventKind::SessionExited,
                        json!({
                            "reason": "Pi process exited",
                            "recoverable": false,
                            "exitKind": "error"
                        }),
                        Some(alera_provider_protocol::RawEvent {
                            source: "pi.rpc".into(),
                            method: Some("eof".into()),
                            message_type: Some("session_exit".into()),
                            payload: Value::Null,
                        }),
                    );
                    event.validate()?;
                    return Ok(Some(event));
                };
                message
            };
            if rpc::is_response(&message) {
                self.consume_response(&message)?;
                if let Some(failure) = self.prompt_failure.take() {
                    let event = lifecycle::prompt_failed(self, failure);
                    self.mark_terminal(false);
                    event.validate()?;
                    return Ok(Some(event));
                }
                continue;
            }
            if rpc::record_type(&message) == Some("agent_settled") {
                let state = self.call("get_state", Value::Object(Map::new())).await?;
                if !runtime::state_is_idle(&state) {
                    self.settle_message = Some(message);
                    continue;
                }
                let event = events::agent_settled(self, message)?;
                self.mark_terminal(false);
                event.validate()?;
                return Ok(Some(event));
            }
            let event = events::map_message(self, message)?;
            if let Some(event) = event {
                event.validate()?;
                return Ok(Some(event));
            }
        }
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        let result = self.transport.close().await;
        self.closed = true;
        self.pending_calls.clear();
        self.pending_order.clear();
        self.pending_ui.clear();
        self.queued_messages.clear();
        self.queued_events.clear();
        self.settle_message = None;
        self.prompt_failure = None;
        self.session_exit_emitted = true;
        self.mcp_extension.take();
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Stopped;
            session.active_turn_id = None;
        }
        result.map_err(ProviderError::from)
    }
}
