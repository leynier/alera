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
use std::collections::{HashMap, HashSet, VecDeque};

pub(crate) struct PendingRequest {
    pub rpc_id: alera_provider_protocol::RequestId,
    pub method: String,
    pub allowance: Option<crate::session_approvals::AllowanceGrant>,
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
    pub(crate) history_mode: Option<String>,
    pub(crate) session_effort: Option<String>,
    /// Every descendant thread of the session's thread, with its parent.
    pub(crate) native_child_parents: HashMap<String, String>,
    /// What each child's spawn called it, for its task description.
    pub(crate) child_labels: HashMap<String, String>,
    /// Each child's latest final answer in its running turn.
    pub(crate) child_results: HashMap<String, String>,
    /// Native child threads with a running turn. A root turn that fails
    /// while any runs leaves them working; they report their own ends.
    pub(crate) active_child_turns: HashSet<String>,
    /// The class of the root turn's last final `error` notification, for a
    /// failed `turn/completed` that does not repeat its `codexErrorInfo`.
    pub(crate) turn_failure_class: Option<alera_provider_protocol::FailureClass>,
    pub(crate) session_approvals: crate::session_approvals::SessionApprovals,
    /// Set by `skills/changed`; the next `next_event` lists the skills again.
    pub(crate) skills_stale: bool,
    /// Requests given up on after a timeout whose answers may still arrive.
    pub(crate) abandoned_responses: HashSet<i64>,
    /// The native turn the last `/compact` runs in, which cannot be steered.
    pub(crate) compaction_turn_id: Option<String>,
}

impl<T: JsonTransport> CodexProvider<T> {
    /// Answers an approval the session allowance already covers, without
    /// surfacing it. Returns whether the message was consumed.
    async fn answer_allowed_request(&mut self, message: &Value) -> Result<bool, ProviderError> {
        let (Some(id), Some(method)) = (message.get("id"), wire::method(message)) else {
            return Ok(false);
        };
        let params = wire::params(message);
        let Some(grant) = self.allowance_grant(method, &params) else {
            return Ok(false);
        };
        if !self
            .session_approvals
            .allows(&grant.native_thread_id, grant.kind)
        {
            return Ok(false);
        }
        let rpc_id = wire::request_id(id)?;
        let result = crate::session_approvals::allowed_result(method);
        self.transport.send(wire::response(&rpc_id, result)).await?;
        Ok(true)
    }
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
            history_mode: None,
            session_effort: None,
            native_child_parents: HashMap::new(),
            child_labels: HashMap::new(),
            child_results: HashMap::new(),
            active_child_turns: HashSet::new(),
            turn_failure_class: None,
            session_approvals: Default::default(),
            skills_stale: false,
            abandoned_responses: HashSet::new(),
            compaction_turn_id: None,
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
            mcp_injection: alera_provider_protocol::McpInjectionCapabilities {
                stdio: true,
                http: true,
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: true,
            streaming: true,
            native_turn_ids: true,
            multiple_threads: false,
            model_switch: true,
            steer: true,
            snapshot: false,
            rollback: true,
            fork: true,
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }

    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        crate::reasoning_effort::capabilities()
    }

    fn native_history_capabilities(&self) -> alera_provider_protocol::NativeHistoryCapabilities {
        alera_provider_protocol::NativeHistoryCapabilities {
            fork_at_turn: true,
            rollback_remove_turns: self.history_mode.as_deref() != Some("paginated"),
            rollback_before_turn: self.history_mode.as_deref() == Some("paginated"),
            ..Default::default()
        }
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
        let method = if input.resume_thread_id.is_some() {
            "thread/resume"
        } else {
            "thread/start"
        };
        let native = input.resume_thread_id.clone();
        self.start_native_session(input, method, native.as_deref(), None)
            .await
    }

    async fn fork_session(
        &mut self,
        input: alera_provider_protocol::NativeForkInput,
    ) -> Result<alera_provider_protocol::NativeForkResult, ProviderError> {
        self.fork_native(input).await
    }

    async fn rollback_session(
        &mut self,
        input: alera_provider_protocol::NativeRollbackInput,
    ) -> Result<alera_provider_protocol::NativeRollbackResult, ProviderError> {
        self.rollback_native(input).await
    }

    async fn steer_turn(
        &mut self,
        input: TurnInput,
        expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        self.steer_native(input, expected_turn_id).await
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
            return Err(ProviderError::Rejected {
                class: alera_provider_protocol::FailureClass::PreviousTurnActive,
                detail:
                    "cannot start a Codex turn while another turn is active or awaiting an event"
                        .into(),
            });
        }
        crate::feedback::refuse_feedback_turn(&input)?;
        if crate::compact::is_compact_turn(&input) {
            return self.start_compaction(&session).await;
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

    async fn upload_feedback(
        &mut self,
        input: alera_provider_protocol::FeedbackUploadInput,
    ) -> Result<alera_provider_protocol::FeedbackUploadResult, ProviderError> {
        self.upload_feedback_native(input).await
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
        let (rpc_id, method, allowance) = self
            .pending_requests
            .get(&request_id)
            .ok_or_else(|| ProviderError::InvalidState("unknown Codex runtime request id".into()))
            .map(|pending| {
                (
                    pending.rpc_id.clone(),
                    pending.method.clone(),
                    pending.allowance.clone(),
                )
            })?;
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
            } => {
                if let Some(grant) = &allowance {
                    self.session_approvals.record(grant, decision);
                }
                responses::approval_result(method, decision, updated_input)
            }
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
        let message = loop {
            if let Some(event) = self.queued_events.pop_front() {
                self.mark_event_consumed(&event);
                return Ok(Some(event));
            }
            if self.skills_stale {
                self.queue_session_skills().await;
                continue;
            }
            let Some(message) = self.transport.recv().await? else {
                return Ok(None);
            };
            if self.absorb_skills_message(&message) {
                continue;
            }
            if message.get("id").is_some() && wire::method(&message).is_none() {
                return Err(ProviderError::Protocol(
                    "Codex received an unsolicited response".into(),
                ));
            }
            if !self.answer_allowed_request(&message).await? {
                break message;
            }
        };
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
        self.session_approvals.clear();
        self.skills_stale = false;
        self.abandoned_responses.clear();
        self.compaction_turn_id = None;
        self.terminal_event_pending = false;
        self.clear_children();
        self.turn_failure_class = None;
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Stopped;
            session.active_turn_id = None;
        }
        result.map_err(ProviderError::from)
    }
}
