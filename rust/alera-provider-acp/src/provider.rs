use crate::config::{AcpFlavor, AcpProviderConfig};
use crate::mapping::{map_incoming, MappingContext};
use crate::mcp::{map_servers, negotiated_capabilities};
use crate::policy::is_auth_required;
use crate::runtime_response::{acp_error, cancelled_response};
use crate::transport::{raw, PendingRequest};
use agent_client_protocol::{AcpClient, AcpRequestId, RpcError};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, InteractionMode, InterruptInput, Provider, ProviderCapabilities, ProviderError,
    ProviderEvent, ProviderKind, ProviderRefs, ProviderSession, RequestKind, RuntimeResponse,
    SessionStartInput, SessionStatus, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use serde_json::json;
use std::collections::{HashMap, VecDeque};
use uuid::Uuid;
pub struct AcpProvider<T> {
    pub(crate) client: AcpClient<T>,
    pub(crate) config: AcpProviderConfig,
    pub(crate) session: Option<ProviderSession>,
    pub(crate) queued_events: VecDeque<ProviderEvent>,
    pub(crate) pending_requests: HashMap<String, PendingRequest>,
    pub(crate) prompt_id: Option<AcpRequestId>,
    pub(crate) prompt_meta_id: Option<String>,
    pub(crate) session_config_options: Vec<serde_json::Value>,
    pub(crate) initialized: bool,
    pub(crate) closed: bool,
}
#[async_trait]
impl<T: JsonTransport> Provider for AcpProvider<T> {
    fn kind(&self) -> ProviderKind {
        self.config.provider.clone()
    }
    fn capabilities(&self) -> ProviderCapabilities {
        let initialized = self.client.initialized();
        ProviderCapabilities {
            mcp_injection: negotiated_capabilities(initialized),
            resume: initialized.is_some_and(|value| {
                if value.generation == agent_client_protocol::AcpProtocolGeneration::V1 {
                    value.capabilities.supports(&["loadSession"])
                        || value
                            .capabilities
                            .supports(&["sessionCapabilities", "resume"])
                } else if let Some(session) = value.capabilities.raw.get("session") {
                    session.is_object() // Resume is part of the V2 session baseline.
                } else {
                    value
                        .capabilities
                        .supports(&["sessionCapabilities", "resume"])
                }
            }),
            interrupt: true,
            approvals: true,
            user_input: true,
            mcp_elicitation: true,
            streaming: true,
            native_turn_ids: false,
            multiple_threads: false,
            model_switch: self.supports_config_option("model"),
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
        crate::reasoning_effort::capabilities(&self.session_config_options)
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.ensure_open()?;
        if self.initialized {
            return Ok(());
        }
        self.client
            .initialize_with_meta(
                &self.config.client_name,
                &self.config.client_version,
                (self.config.flavor == AcpFlavor::Grok).then(|| json!({"clientType":"extension"})),
            )
            .await
            .map_err(acp_error)?;
        self.initialized = true;
        if self.config.authenticate_eagerly {
            self.authenticate_after_required().await?;
        }
        Ok(())
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        input.validate()?;
        if input.options.keys().any(|key| key != "reasoningEffort") {
            return Err(ProviderError::Unsupported(
                "ACP session options require a provider flavor mapping".into(),
            ));
        }
        if input.approval_policy.is_some() || input.sandbox_mode.is_some() {
            return Err(ProviderError::Unsupported(
                "ACP approval and sandbox policies require provider-specific mapping".into(),
            ));
        }
        self.ensure_open()?;
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "ACP provider supports one active session per connection".into(),
            ));
        }
        self.initialize().await?;
        let runtime_mode = input.runtime_mode;
        self.validate_runtime_policy(runtime_mode)?;
        let generation = self.protocol_generation();
        let mcp_servers = map_servers(
            &input.mcp_servers,
            self.capabilities().mcp_injection,
            generation,
        )?;
        let cwd = input.cwd.as_deref().and_then(|path| path.to_str());
        let (session_method, response) = if let Some(native_id) = input.resume_thread_id.as_deref()
        {
            if !self.capabilities().resume {
                return Err(ProviderError::Unsupported(
                    "ACP agent did not advertise session resume".into(),
                ));
            }
            let use_load = self.client.initialized().is_some_and(|initialized| {
                initialized.generation == agent_client_protocol::AcpProtocolGeneration::V1
                    && initialized.capabilities.supports(&["loadSession"])
            });
            let response = if use_load {
                match self
                    .client
                    .load_session_with_mcp(native_id, cwd, &mcp_servers)
                    .await
                {
                    Ok(response) => response,
                    Err(error) if is_auth_required(&error) => {
                        self.authenticate_after_required().await?;
                        self.client
                            .load_session_with_mcp(native_id, cwd, &mcp_servers)
                            .await
                            .map_err(acp_error)?
                    }
                    Err(error) => return Err(acp_error(error)),
                }
            } else {
                match self
                    .client
                    .resume_session_with_mcp(native_id, cwd, &mcp_servers)
                    .await
                {
                    Ok(response) => response,
                    Err(error) if is_auth_required(&error) => {
                        self.authenticate_after_required().await?;
                        self.client
                            .resume_session_with_mcp(native_id, cwd, &mcp_servers)
                            .await
                            .map_err(acp_error)?
                    }
                    Err(error) => return Err(acp_error(error)),
                }
            };
            let method = if use_load {
                "session/load"
            } else {
                "session/resume"
            };
            (method, response)
        } else {
            let response = match self.client.new_session(cwd, &mcp_servers).await {
                Ok(response) => response,
                Err(error) if is_auth_required(&error) => {
                    self.authenticate_after_required().await?;
                    self.client
                        .new_session(cwd, &mcp_servers)
                        .await
                        .map_err(acp_error)?
                }
                Err(error) => return Err(acp_error(error)),
            };
            ("session/new", response)
        };
        let native_thread_id = response
            .session_id
            .clone()
            .or(input.resume_thread_id.clone())
            .ok_or_else(|| {
                ProviderError::Protocol("ACP session response lacks sessionId".into())
            })?;
        self.session_config_options = response.config_options.clone();
        if let Some(model) = input.model.as_deref() {
            if !self.supports_config_option("model") {
                return Err(ProviderError::Unsupported(
                    "ACP agent did not advertise a model configuration option".into(),
                ));
            }
            let configured = self
                .client
                .set_model(&native_thread_id, model)
                .await
                .map_err(acp_error)?;
            if let Some(options) = configured
                .get("configOptions")
                .and_then(serde_json::Value::as_array)
            {
                self.session_config_options = options.clone();
            }
        }
        self.apply_runtime_policy(&native_thread_id, runtime_mode)
            .await?;
        if let Some(effort) = alera_provider_protocol::reasoning_effort(&input.options)? {
            self.apply_reasoning_effort(&native_thread_id, effort)
                .await?;
        }
        let session = ProviderSession {
            provider: self.kind(),
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id.clone(),
            native_thread_id: native_thread_id.clone(),
            status: SessionStatus::Ready,
            model: input.model.clone(),
            cwd: input.cwd.clone(),
            active_turn_id: None,
        };
        self.session = Some(session.clone());
        let event = ProviderEvent::new(
            self.kind(),
            self.config.provider_instance_id.clone(),
            input.thread_id,
            EventKind::ThreadStarted,
            json!({"providerThreadId":native_thread_id}),
            Some(raw(session_method, response.raw)),
        );
        self.queue_event(event)?;
        Ok(session)
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        self.ensure_open()?;
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start an ACP session first".into()))?;
        if session.thread_id != input.thread_id {
            return Err(ProviderError::InvalidState(
                "turn threadId does not match active ACP session".into(),
            ));
        }
        if session.active_turn_id.is_some() {
            return Err(ProviderError::InvalidState(
                "cannot start an ACP turn while another turn is active".into(),
            ));
        }
        if !input.attachments.is_empty() {
            return Err(ProviderError::Unsupported(
                "ACP attachment forwarding is not negotiated by this adapter".into(),
            ));
        }
        if input.options.keys().any(|key| key != "reasoningEffort") {
            return Err(ProviderError::Unsupported(
                "ACP turn options require a provider flavor mapping".into(),
            ));
        }
        if input.model.is_some() {
            return Err(ProviderError::Unsupported(
                "ACP per-turn model selection is not negotiated by this adapter".into(),
            ));
        }
        if input.interaction_mode != InteractionMode::Default {
            return Err(ProviderError::Unsupported(
                "ACP per-turn interaction mode is not negotiated by this adapter".into(),
            ));
        }
        if let Some(effort) = alera_provider_protocol::reasoning_effort(&input.options)? {
            self.apply_reasoning_effort(&session.native_thread_id, effort)
                .await?;
        }
        let turn_id = format!("turn:{}", Uuid::new_v4());
        let prompt_text = input.input.clone();
        let prompt_meta = (self.config.flavor == AcpFlavor::Grok)
            .then(|| json!({"promptId": turn_id, "requestId": turn_id}));
        let prompt_id = self
            .client
            .begin_prompt_with_meta(
                &session.native_thread_id,
                vec![json!({"type":"text","text":prompt_text.clone()})],
                prompt_meta.clone(),
            )
            .await
            .map_err(acp_error)?;
        let mut prompt_params = json!({
            "sessionId": session.native_thread_id,
            "prompt": [{"type":"text","text":prompt_text}]
        });
        if let Some(meta) = prompt_meta {
            prompt_params["_meta"] = meta;
        }
        let mut started = ProviderEvent::new(
            self.kind(),
            self.config.provider_instance_id.clone(),
            input.thread_id.clone(),
            EventKind::TurnStarted,
            json!({"model":session.model}),
            Some(raw(
                "session/prompt",
                json!({
                    "jsonrpc":"2.0",
                    "id":prompt_id.as_value(),
                    "method":"session/prompt",
                    "params":prompt_params
                }),
            )),
        );
        started.turn_id = Some(turn_id.clone());
        started.provider_refs = Some(ProviderRefs {
            provider_turn_id: None,
            provider_item_id: None,
            provider_request_id: Some(prompt_id.to_string()),
        });
        self.queue_event(started)?;
        self.prompt_id = Some(prompt_id);
        self.prompt_meta_id = (self.config.flavor == AcpFlavor::Grok).then(|| turn_id.clone());
        if let Some(active) = self.session.as_mut() {
            active.status = SessionStatus::Running;
            active.active_turn_id = Some(turn_id.clone());
        }
        Ok(TurnStartResult {
            thread_id: input.thread_id,
            turn_id,
            native_turn_id: None,
        })
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("start an ACP session first".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::InvalidState(
                "interrupt threadId does not match active ACP session".into(),
            ));
        }
        let cancel_meta =
            (self.config.flavor == AcpFlavor::Grok).then(|| json!({"cancelTrigger":"ctrl_c"}));
        let pending = self.pending_requests.values().cloned().collect::<Vec<_>>();
        for request in pending {
            let wire = cancelled_response(&request);
            self.client
                .respond(&request.rpc_id, Ok(wire))
                .await
                .map_err(acp_error)?;
            self.pending_requests.remove(&request.logical_id);
            self.queue_request_resolved(&request)?;
        }
        self.client
            .cancel_with_meta(&session.native_thread_id, cancel_meta)
            .await
            .map_err(acp_error)
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.respond_native(response).await
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.ensure_open()?;
        if let Some(event) = self.queued_events.pop_front() {
            event.validate()?;
            return Ok(Some(event));
        }
        let incoming = self.client.next_incoming().await.map_err(acp_error)?;
        let Some(incoming) = incoming else {
            self.closed = true;
            self.prompt_id = None;
            if let Some(session) = self.session.as_mut() {
                session.active_turn_id = None;
                session.status = SessionStatus::Error;
            }
            return Ok(None);
        };
        let session = self.session.clone().ok_or_else(|| {
            ProviderError::InvalidState("ACP event arrived before session/new".into())
        })?;
        let provider_kind = self.kind();
        if let agent_client_protocol::AcpIncoming::Notification { params, .. } = &incoming {
            if params.get("sessionId").and_then(serde_json::Value::as_str)
                == Some(session.native_thread_id.as_str())
            {
                if let Some(options) = params
                    .pointer("/update/configOptions")
                    .and_then(serde_json::Value::as_array)
                {
                    self.session_config_options = options.clone();
                }
            }
        }
        let context = MappingContext {
            provider: &provider_kind,
            instance_id: &self.config.provider_instance_id,
            thread_id: &session.thread_id,
            native_thread_id: &session.native_thread_id,
            turn_id: session.active_turn_id.as_deref(),
            prompt_id: self.prompt_id.as_ref(),
            prompt_meta_id: self.prompt_meta_id.as_deref(),
        };
        let mapped = map_incoming(incoming, &context)?;
        mapped.event.validate()?;
        self.apply_mapped_state(&mapped);
        if let Some(pending) = mapped.pending {
            if pending.kind == RequestKind::Unknown {
                self.client
                    .respond(
                        &pending.rpc_id,
                        Err(RpcError {
                            code: -32601,
                            message: "Method not found".into(),
                            data: None,
                        }),
                    )
                    .await
                    .map_err(acp_error)?;
            } else {
                self.pending_requests
                    .insert(pending.logical_id.clone(), pending);
            }
        }
        Ok(Some(mapped.event))
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        self.pending_requests.clear();
        self.queued_events.clear();
        self.prompt_id = None;
        self.prompt_meta_id = None;
        if let Some(session) = self.session.as_mut() {
            session.active_turn_id = None;
            session.status = SessionStatus::Stopped;
        }
        self.client.close().await.map_err(acp_error)
    }
}
