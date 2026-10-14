use crate::config::CursorProviderConfig;
use crate::mapping::map_run_message;
use crate::mcp::native_mcp_servers;
use crate::stream_state::{is_assistant_delta, item_id, run_id, status_error_message};
use alera_provider_protocol::{
    EventKind, InteractionMode, InterruptInput, Provider, ProviderCapabilities, ProviderError,
    ProviderEvent, ProviderKind, ProviderSession, RuntimeMode, RuntimeResponse, SessionStartInput,
    SessionStatus, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use cursor_agent_sdk::{
    AgentMode, AgentOptions, CursorBridge, CursorClient, CursorRunStream, LocalAgentOptions,
    ModelSelection, SendOptions, UserMessage,
};
use serde_json::Value;
use std::collections::VecDeque;

const MAX_LOCAL_IMAGE_BYTES: usize = 8 * 1024 * 1024;

#[path = "attachments.rs"]
mod attachments;
#[path = "reasoning_effort.rs"]
pub(crate) mod reasoning_effort;
#[path = "recovery.rs"]
mod recovery;
#[path = "session_options.rs"]
mod session_options;

pub struct CursorProvider {
    client: CursorClient,
    config: CursorProviderConfig,
    initialized: bool,
    closed: bool,
    session: Option<ProviderSession>,
    stream: Option<CursorRunStream>,
    native_run_id: Option<String>,
    native_item_id: Option<String>,
    streamed_assistant: bool,
    last_status_error_message: Option<String>,
    next_turn: u64,
    active_turn_id: Option<String>,
    stream_recovery_attempted: bool,
    queued_events: VecDeque<ProviderEvent>,
    mcp_servers: Vec<alera_provider_protocol::McpServerSpec>,
    effort_models: Vec<cursor_agent_sdk::SdkModel>,
    session_effort: Option<String>,
}

impl CursorProvider {
    pub fn connect(config: CursorProviderConfig) -> Result<Self, ProviderError> {
        let client = CursorClient::connect(config.client_config())
            .map_err(|error| ProviderError::Protocol(error.to_string()))?;
        Ok(Self::new(client, config))
    }

    pub fn new(client: CursorClient, config: CursorProviderConfig) -> Self {
        Self {
            client,
            config,
            initialized: false,
            closed: false,
            session: None,
            stream: None,
            native_run_id: None,
            native_item_id: None,
            streamed_assistant: false,
            last_status_error_message: None,
            next_turn: 0,
            active_turn_id: None,
            stream_recovery_attempted: false,
            queued_events: VecDeque::new(),
            mcp_servers: Vec::new(),
            effort_models: Vec::new(),
            session_effort: None,
        }
    }

    pub fn from_bridge(bridge: &CursorBridge, config: CursorProviderConfig) -> Self {
        Self::new(bridge.client().clone(), config)
    }

    pub fn config(&self) -> &CursorProviderConfig {
        &self.config
    }

    pub fn client(&self) -> &CursorClient {
        &self.client
    }

    fn ensure_open(&self) -> Result<(), ProviderError> {
        if self.closed {
            Err(ProviderError::Closed)
        } else {
            Ok(())
        }
    }

    fn active_session(&self) -> Result<ProviderSession, ProviderError> {
        self.session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("Cursor session has not started".into()))
    }

    fn queue_event(&mut self, event: ProviderEvent) -> Result<(), ProviderError> {
        event.validate()?;
        self.queued_events.push_back(event);
        Ok(())
    }
}

#[async_trait]
impl Provider for CursorProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Other("cursor".into())
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            mcp_injection: alera_provider_protocol::McpInjectionCapabilities {
                stdio: true,
                http: true,
            },
            resume: true,
            interrupt: true,
            approvals: false,
            user_input: false,
            mcp_elicitation: false,
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

    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        reasoning_effort::capabilities(self)
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.ensure_open()?;
        if !self.initialized {
            self.client
                .ping()
                .await
                .map_err(|error| ProviderError::Protocol(error.to_string()))?;
            let version = self
                .client
                .get_version()
                .await
                .map_err(|error| ProviderError::Protocol(error.to_string()))?;
            if let Some(protocol) = version
                .get("protocolVersion")
                .or_else(|| version.get("protocol_version"))
                .and_then(Value::as_str)
            {
                if protocol != "sdk.v1" {
                    return Err(ProviderError::Unsupported(format!(
                        "Cursor bridge protocol {protocol} is not sdk.v1"
                    )));
                }
            }
            self.initialized = true;
        }
        Ok(())
    }

    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        if input.options.keys().any(|key| key != "reasoningEffort") {
            return Err(ProviderError::Unsupported(
                "Cursor session options are unsupported".into(),
            ));
        }
        if input.runtime_mode != RuntimeMode::ApprovalRequired {
            return Err(ProviderError::Unsupported(
                "Cursor bridge does not expose runtime approval modes".into(),
            ));
        }
        if input.approval_policy.is_some() {
            return Err(ProviderError::Unsupported(
                "Cursor bridge does not expose approval policies".into(),
            ));
        }
        if input.sandbox_mode.is_some() {
            return Err(ProviderError::Unsupported(
                "Cursor bridge does not expose sandbox policies".into(),
            ));
        }
        self.initialize().await?;
        let effort = alera_provider_protocol::reasoning_effort(&input.options)?.map(str::to_owned);
        if effort.is_some() {
            self.discover_effort_models().await?;
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Cursor provider supports one session per bridge connection".into(),
            ));
        }
        let mcp_servers = input.mcp_servers.clone();
        let (native, response_model) = if let Some(resume_id) = &input.resume_thread_id {
            let response = self
                .client
                .resume_agent(resume_id, self.agent_options(&input)?)
                .await
                .map_err(|error| ProviderError::Protocol(error.to_string()))?;
            (response.agent_id, response.model)
        } else {
            let response = self
                .client
                .create_agent(self.agent_options(&input)?, None)
                .await
                .map_err(|error| ProviderError::Protocol(error.to_string()))?;
            (response.agent_id, response.model)
        };
        self.mcp_servers = mcp_servers;
        self.session_effort = effort;
        let response_model =
            response_model.and_then(|model| (!model.id.is_empty()).then_some(model.id));
        let session = ProviderSession {
            provider: self.kind(),
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id.clone(),
            native_thread_id: native.clone(),
            status: SessionStatus::Ready,
            model: input
                .model
                .or_else(|| self.config.model.clone())
                .or(response_model),
            cwd: input.cwd.or_else(|| self.config.cwd.clone()),
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        let mut started = ProviderEvent::new(
            self.kind(),
            &self.config.provider_instance_id,
            &input.thread_id,
            EventKind::ThreadStarted,
            serde_json::json!({ "providerThreadId": native }),
            None,
        );
        started.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: None,
        });
        self.queue_event(started)?;
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        let session = self.active_session()?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "turn threadId does not match session".into(),
            ));
        }
        if self.stream.is_some() || self.active_turn_id.is_some() {
            return Err(ProviderError::InvalidState(
                "Cursor turn is already running".into(),
            ));
        }
        if input.options.keys().any(|key| key != "reasoningEffort") {
            return Err(ProviderError::Unsupported(
                "Cursor turn options are unsupported".into(),
            ));
        }
        let images = attachments::load_images(&input.attachments).await?;
        let effort = alera_provider_protocol::reasoning_effort(&input.options)?
            .map(str::to_owned)
            .or(self.session_effort.clone());
        if effort.is_some() {
            self.discover_effort_models().await?;
        }
        let model = self.model_selection(
            input.model.or_else(|| session.model.clone()),
            effort.as_deref(),
        )?;
        let options = SendOptions {
            model,
            enable_deltas: Some(true),
            enable_steps: Some(true),
            mode: (input.interaction_mode == InteractionMode::Plan).then_some(AgentMode::Plan),
            mcp_servers: native_mcp_servers(&self.mcp_servers)?,
        };
        let stream = self
            .client
            .send(
                &session.native_thread_id,
                UserMessage {
                    text: input.input,
                    images,
                },
                options,
                None,
            )
            .await
            .map_err(|error| ProviderError::Protocol(error.to_string()))?;
        self.next_turn = self.next_turn.saturating_add(1);
        let turn_id = format!("turn:cursor:{}", self.next_turn);
        self.active_turn_id = Some(turn_id.clone());
        self.native_run_id = None;
        self.native_item_id = None;
        self.streamed_assistant = false;
        self.last_status_error_message = None;
        self.stream_recovery_attempted = false;
        self.stream = Some(stream);
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Running;
            session.active_turn_id = Some(turn_id.clone());
        }
        let mut event = ProviderEvent::new(
            self.kind(),
            &self.config.provider_instance_id,
            &session.thread_id,
            EventKind::TurnStarted,
            serde_json::json!({ "model": session.model }),
            None,
        );
        event.turn_id = Some(turn_id.clone());
        self.queue_event(event)?;
        Ok(TurnStartResult {
            thread_id: session.thread_id,
            turn_id,
            native_turn_id: None,
        })
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.ensure_open()?;
        let session = self.active_session()?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "interrupt threadId does not match session".into(),
            ));
        }
        if let Some(turn_id) = input.turn_id.as_deref() {
            if self.active_turn_id.as_deref() != Some(turn_id) {
                return Err(ProviderError::Validation(
                    "interrupt turnId does not match the active turn".into(),
                ));
            }
        }
        let native = self.native_run_id.clone().ok_or_else(|| {
            ProviderError::InvalidState(
                "Cursor run id is not known until the first stream event".into(),
            )
        })?;
        self.client
            .cancel_and_wait(&native, Some(&session.native_thread_id))
            .await
            .map_err(|error| ProviderError::Protocol(error.to_string()))?;
        Ok(())
    }

    async fn respond(&mut self, _response: RuntimeResponse) -> Result<(), ProviderError> {
        Err(ProviderError::Unsupported(
            "Cursor SDK v1 has no interactive approval or input response in this adapter".into(),
        ))
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        if let Some(event) = self.queued_events.pop_front() {
            return Ok(Some(event));
        }
        self.ensure_open()?;
        let Some(stream) = self.stream.as_mut() else {
            return Ok(None);
        };
        let next = stream.next().await;
        let message = match next {
            Ok(Some(message)) => message,
            Ok(None) => {
                return self
                    .recover_stream_loss("run stream ended before a terminal result".into())
                    .await;
            }
            Err(error) => return self.recover_stream_loss(error.to_string()).await,
        };
        if let Some(run_id) = run_id(&message) {
            self.native_run_id = Some(run_id);
        }
        if let Some(item_id) = item_id(&message) {
            self.native_item_id = Some(item_id);
        }
        if let Some(message) = status_error_message(&message) {
            self.last_status_error_message = Some(message);
        }
        let session = self.active_session()?;
        let mut mapped = map_run_message(
            &message,
            &self.config.provider_instance_id,
            &session.thread_id,
            self.active_turn_id.as_deref(),
            self.native_run_id.as_deref(),
            self.native_item_id.as_deref(),
            self.streamed_assistant,
        )?;
        if message.result.is_some() {
            if let Some(error_message) = self.last_status_error_message.as_deref() {
                for event in &mut mapped {
                    if event.kind == alera_provider_protocol::EventKind::TurnCompleted
                        && event.payload.get("errorMessage").is_none()
                    {
                        event.payload["errorMessage"] = Value::String(error_message.to_owned());
                        event.validate()?;
                    }
                }
            }
        }
        self.streamed_assistant |= mapped.iter().any(is_assistant_delta);
        let terminal = message.result.is_some() || message.done.is_some();
        self.queued_events.extend(mapped);
        if terminal {
            if let Some(stream) = self.stream.as_mut() {
                let _ = stream.close().await;
            }
            self.clear_turn_state();
        }
        Ok(self.queued_events.pop_front())
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        if let Some(stream) = self.stream.as_mut() {
            let _ = stream.close().await;
        }
        if let Some(session) = &self.session {
            let _ = self.client.close_agent(&session.native_thread_id).await;
        }
        let _ = self.client.close().await;
        self.stream = None;
        self.queued_events.clear();
        self.active_turn_id = None;
        self.native_run_id = None;
        self.native_item_id = None;
        self.streamed_assistant = false;
        self.last_status_error_message = None;
        self.stream_recovery_attempted = false;
        self.mcp_servers.clear();
        let session_thread_id = self
            .session
            .as_ref()
            .map(|session| session.thread_id.clone());
        if let Some(session) = self.session.as_mut() {
            session.status = SessionStatus::Stopped;
            session.active_turn_id = None;
        }
        if let Some(thread_id) = session_thread_id {
            let event = ProviderEvent::new(
                self.kind(),
                &self.config.provider_instance_id,
                thread_id,
                EventKind::SessionExited,
                serde_json::json!({
                    "reason": "provider closed",
                    "recoverable": false,
                    "exitKind": "graceful",
                }),
                Some(alera_provider_protocol::RawEvent {
                    source: "cursor.sdk.bridge".into(),
                    method: Some("close".into()),
                    message_type: Some("session".into()),
                    payload: serde_json::json!({ "status": "stopped" }),
                }),
            );
            event.validate()?;
            self.queued_events.push_back(event);
        }
        self.closed = true;
        Ok(())
    }
}
