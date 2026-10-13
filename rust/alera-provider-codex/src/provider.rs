use crate::config::CodexProviderConfig;
use crate::{events, responses, wire};
use alera_agent_transport::{JsonLineProcess, JsonTransport};
use alera_provider_protocol::{
    ApprovalPolicy, InterruptInput, Provider, ProviderCapabilities, ProviderError, ProviderKind,
    ProviderSession, RuntimeMode, RuntimeResponse, SandboxMode, SessionStartInput, SessionStatus,
    TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};

pub(crate) struct PendingRequest {
    pub rpc_id: alera_provider_protocol::RequestId,
    pub method: String,
}

/// A Codex app-server client using the provider protocol's JSON-lines boundary.
pub struct CodexProvider<T> {
    pub(crate) transport: T,
    pub(crate) config: CodexProviderConfig,
    pub(crate) initialized: bool,
    pub(crate) closed: bool,
    pub(crate) next_request_id: i64,
    pub(crate) pending_thread_id: Option<String>,
    pub(crate) pending_requests: HashMap<alera_provider_protocol::RequestId, PendingRequest>,
    pub(crate) queued_events: VecDeque<alera_provider_protocol::ProviderEvent>,
    pub(crate) session: Option<ProviderSession>,
    pub(crate) runtime_mode: RuntimeMode,
    pub(crate) approval_policy: Option<ApprovalPolicy>,
    pub(crate) sandbox_mode: Option<SandboxMode>,
    pub(crate) terminal_event_pending: bool,
}

impl<T> CodexProvider<T> {
    pub fn new(transport: T, config: CodexProviderConfig) -> Self {
        Self {
            transport,
            config,
            initialized: false,
            closed: false,
            next_request_id: 1,
            pending_thread_id: None,
            pending_requests: HashMap::new(),
            queued_events: VecDeque::new(),
            session: None,
            runtime_mode: RuntimeMode::ApprovalRequired,
            approval_policy: None,
            sandbox_mode: None,
            terminal_event_pending: false,
        }
    }

    pub fn config(&self) -> &CodexProviderConfig {
        &self.config
    }

    pub fn config_mut(&mut self) -> &mut CodexProviderConfig {
        &mut self.config
    }

    pub fn transport(&self) -> &T {
        &self.transport
    }

    pub fn transport_mut(&mut self) -> &mut T {
        &mut self.transport
    }

    pub fn into_transport(self) -> T {
        self.transport
    }

    pub fn is_initialized(&self) -> bool {
        self.initialized
    }

    pub fn queued_event_count(&self) -> usize {
        self.queued_events.len()
    }
}

impl CodexProvider<JsonLineProcess> {
    pub async fn spawn(config: CodexProviderConfig) -> Result<Self, ProviderError> {
        let process = JsonLineProcess::spawn(config.process_config()).await?;
        Ok(Self::new(process, config))
    }
}

#[async_trait]
impl<T: JsonTransport> Provider for CodexProvider<T> {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Codex
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: true,
            streaming: true,
            native_turn_ids: true,
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
        if !self.initialized {
            self.initialize_inner().await?;
        }
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Codex provider supports one session per connection".into(),
            ));
        }
        self.pending_thread_id = Some(input.thread_id.clone());
        if let Err(error) = self.initialize().await {
            self.pending_thread_id = None;
            return Err(error);
        }
        let native_requested = self.next_session_thread(&input);
        let method = if input.resume_thread_id.is_some() {
            "thread/resume"
        } else {
            "thread/start"
        };
        let mut params = self.thread_params(&input);
        if method == "thread/resume" {
            params.insert("threadId".into(), Value::String(native_requested.clone()));
        }
        let response = self.call(method, Value::Object(params)).await;
        self.pending_thread_id = None;
        let response = response?;
        let native_thread_id = Self::decode_thread_id(&response)?;
        let model = input.model.or_else(|| self.config.model.clone());
        let cwd = input.cwd.or_else(|| self.config.cwd.clone());
        let defaults = crate::policy::runtime_defaults(input.runtime_mode);
        self.runtime_mode = input.runtime_mode;
        self.approval_policy = Some(
            input
                .approval_policy
                .or(self.config.approval_policy)
                .unwrap_or(defaults.approval_policy),
        );
        self.sandbox_mode = Some(
            input
                .sandbox_mode
                .or(self.config.sandbox_mode)
                .unwrap_or(defaults.sandbox_mode),
        );
        let session = ProviderSession {
            provider: ProviderKind::Codex,
            provider_instance_id: self.config.instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id,
            status: if self.pending_requests.is_empty() {
                SessionStatus::Ready
            } else {
                SessionStatus::Waiting
            },
            model,
            cwd,
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::InvalidState(
                "turn threadId does not match the active session".into(),
            ));
        }
        if self.terminal_event_pending
            || matches!(
                session.status,
                SessionStatus::Running | SessionStatus::Waiting
            )
            || session.active_turn_id.is_some()
        {
            return Err(ProviderError::InvalidState(
                "cannot start a Codex turn while another turn is active or awaiting an event"
                    .into(),
            ));
        }
        let params = self.turn_params(&input, &session)?;
        let response = self.call("turn/start", Value::Object(params)).await?;
        let native_turn_id = Self::decode_turn_id(&response)?;
        let thread_id = session.thread_id.clone();
        let turn_id = native_turn_id.clone();
        let waiting_for_request = !self.pending_requests.is_empty();
        if let Some(session) = self.session.as_mut() {
            session.status = if waiting_for_request {
                SessionStatus::Waiting
            } else {
                SessionStatus::Running
            };
            session.active_turn_id = Some(native_turn_id.clone());
        }
        Ok(TurnStartResult {
            thread_id,
            turn_id,
            native_turn_id: Some(native_turn_id),
        })
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::InvalidState(
                "interrupt threadId does not match the active session".into(),
            ));
        }
        let turn_id = input.turn_id.or(session.active_turn_id).ok_or_else(|| {
            ProviderError::InvalidState("no active Codex turn to interrupt".into())
        })?;
        self.call(
            "turn/interrupt",
            json!({ "threadId": session.native_thread_id, "turnId": turn_id }),
        )
        .await?;
        Ok(())
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let request_id = response.request_id().clone();
        let (rpc_id, method) = self
            .pending_requests
            .get(&request_id)
            .ok_or_else(|| ProviderError::InvalidState("unknown Codex runtime request id".into()))
            .map(|pending| (pending.rpc_id.clone(), pending.method.clone()))?;
        let method = method.as_str();
        let matches_method = match &response {
            RuntimeResponse::Native { .. } => true,
            RuntimeResponse::Approval { .. } => matches!(
                method,
                "item/commandExecution/requestApproval"
                    | "item/fileChange/requestApproval"
                    | "item/permissions/requestApproval"
                    | "execCommandApproval"
                    | "applyPatchApproval"
            ),
            RuntimeResponse::UserInput { .. } => method == "item/tool/requestUserInput",
            RuntimeResponse::Elicitation { .. } => method == "mcpServer/elicitation/request",
        };
        if !matches_method {
            return Err(ProviderError::Validation(
                "Codex runtime response variant does not match the pending request".into(),
            ));
        }
        let result = match response {
            RuntimeResponse::Approval {
                decision,
                updated_input,
                ..
            } => responses::approval_result(decision, updated_input),
            RuntimeResponse::UserInput { answers, .. } => responses::user_input_result(answers),
            RuntimeResponse::Elicitation {
                action, content, ..
            } => responses::elicitation_result(action, content)?,
            RuntimeResponse::Native { result, .. } => result,
        };
        if method == "mcpServer/elicitation/request" {
            if result.get("action").is_none() {
                return Err(ProviderError::Validation(
                    "MCP elicitation requires an action response".into(),
                ));
            }
            let Some(content) = result.get("content") else {
                return Err(ProviderError::Validation(
                    "MCP elicitation response requires content".into(),
                ));
            };
            if !content.is_null() && !content.is_object() {
                return Err(ProviderError::Validation(
                    "MCP elicitation content must be null or an object".into(),
                ));
            }
        }
        self.transport.send(wire::response(&rpc_id, result)).await?;
        self.pending_requests.remove(&request_id);
        if self.pending_requests.is_empty() {
            if let Some(session) = self.session.as_mut() {
                if session.status == SessionStatus::Waiting {
                    session.status = if session.active_turn_id.is_some() {
                        SessionStatus::Running
                    } else {
                        SessionStatus::Ready
                    };
                }
            }
        }
        Ok(())
    }

    async fn next_event(
        &mut self,
    ) -> Result<Option<alera_provider_protocol::ProviderEvent>, ProviderError> {
        self.ensure_open()?;
        if let Some(event) = self.queued_events.pop_front() {
            self.mark_event_consumed(&event);
            return Ok(Some(event));
        }
        let Some(message) = self.transport.recv().await? else {
            return Ok(None);
        };
        if message.get("id").is_some() && wire::method(&message).is_none() {
            return Err(ProviderError::Protocol(
                "Codex received an unsolicited response".into(),
            ));
        }
        let event = events::map_message(self, message)?;
        self.mark_event_consumed(&event);
        Ok(Some(event))
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        let result = self.transport.close().await;
        self.closed = true;
        self.pending_requests.clear();
        self.queued_events.clear();
        self.terminal_event_pending = false;
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Stopped;
            session.active_turn_id = None;
        }
        result.map_err(ProviderError::from)
    }
}
