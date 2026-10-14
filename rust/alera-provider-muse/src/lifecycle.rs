use crate::provider::MuseProvider;
use crate::session_mcp;
use alera_provider_protocol::*;
use async_trait::async_trait;
use serde_json::{Map, Value};

#[async_trait]
impl Provider for MuseProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Other("muse".into())
    }

    fn capabilities(&self) -> ProviderCapabilities {
        let session_mcp = self.initialized
            && !self.closed
            && self.has_granted_capability(muse_agent_sdk::SESSION_MCP_CAPABILITY);
        ProviderCapabilities {
            mcp_injection: McpInjectionCapabilities {
                stdio: session_mcp,
                http: session_mcp,
            },
            resume: true,
            interrupt: true,
            approvals: true,
            user_input: true,
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

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Err(ProviderError::Closed);
        }
        if self.initialized {
            return Ok(());
        }
        let mut options = self.options();
        options.request_capability(muse_agent_sdk::SESSION_MCP_CAPABILITY);
        let client = if let Some(transport) = self.transport.take() {
            muse_agent_sdk::MuseClient::with_boxed_transport(transport, options)
                .map_err(Self::sdk_error)?
        } else {
            muse_agent_sdk::MuseClient::connect(options)
                .await
                .map_err(Self::sdk_error)?
        };
        let initialize = client.initialize().await.map_err(Self::sdk_error)?;
        self.granted_capabilities = initialize.granted_capabilities;
        self.client = Some(client);
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
                "initialize must precede start_session".into(),
            ));
        }
        if self.session.is_some() {
            return Err(ProviderError::InvalidState(
                "Muse adapter supports one session".into(),
            ));
        }
        if !input.options.is_empty() {
            return Err(ProviderError::Unsupported(
                "Muse session options are not supported by the MSP adapter".into(),
            ));
        }
        if !input.mcp_servers.is_empty()
            && !self.has_granted_capability(muse_agent_sdk::SESSION_MCP_CAPABILITY)
        {
            return Err(ProviderError::Unsupported(
                "Muse host did not grant sessionMcp".into(),
            ));
        }
        let mode = Self::approval_mode(&input)?;
        let mut params = Map::new();
        if let Some(cwd) = &input.cwd {
            params.insert(
                "workspaceRoot".into(),
                Value::String(cwd.to_string_lossy().into()),
            );
        }
        if let Some(model) = &input.model {
            params.insert("modelId".into(), Value::String(model.clone()));
        }
        if let Some(thread) = &input.resume_thread_id {
            params.insert("sessionId".into(), Value::String(thread.clone()));
        }
        if let Some(mode) = mode {
            params.insert("approvalMode".into(), Value::String(mode.into()));
        }
        if let Some(config) = session_mcp::config(&input.mcp_servers)? {
            params.insert("config".into(), Value::Object(config));
        }
        let summary = if input.resume_thread_id.is_some() {
            self.client
                .as_ref()
                .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
                .resume_session(params)
                .await
                .map_err(Self::sdk_error)?
        } else {
            self.client
                .as_ref()
                .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
                .start_session(params)
                .await
                .map_err(Self::sdk_error)?
        };
        let session = ProviderSession {
            provider: self.kind(),
            provider_instance_id: self.config.provider_instance_id.clone(),
            thread_id: input.thread_id,
            native_thread_id: summary.session_id.clone(),
            status: SessionStatus::Ready,
            model: input.model.or(summary.model_id),
            cwd: input.cwd,
            active_turn_id: summary.active_turn_id,
        };
        self.queue_event(self.event_session_started(&session))?;
        self.queue_event(self.event_thread_started(&session))?;
        self.session = Some(session.clone());
        Ok(session)
    }

    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        let session = self.session_ref()?.clone();
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
                "Muse turn is already active".into(),
            ));
        }
        if input.interaction_mode == InteractionMode::Plan {
            return Err(ProviderError::Unsupported(
                "Muse MSP has no per-turn plan mode".into(),
            ));
        }
        if !input.options.is_empty() {
            return Err(ProviderError::Unsupported(
                "Muse turn options are not supported by the MSP adapter".into(),
            ));
        }
        if let Some(model) = &input.model {
            if session.model.as_deref() != Some(model.as_str()) {
                self.client
                    .as_ref()
                    .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
                    .set_model(&session.native_thread_id, model)
                    .await
                    .map_err(Self::sdk_error)?;
                if let Some(current) = &mut self.session {
                    current.model = Some(model.clone());
                }
            }
        }
        let mut parts = Vec::new();
        if !input.input.trim().is_empty() {
            parts.push(serde_json::json!({"type":"text","text":input.input}));
        }
        if !input.attachments.is_empty() {
            return Err(ProviderError::Unsupported(
                "Muse MSP image and file attachments require a native upload receipt".into(),
            ));
        }
        let ack = self
            .client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
            .start_turn(&session.native_thread_id, parts, None)
            .await
            .map_err(Self::sdk_error)?;
        let native_turn_id = ack
            .turn_id
            .clone()
            .ok_or_else(|| ProviderError::Protocol("turn/start omitted turnId".into()))?;
        if let Some(current) = &mut self.session {
            current.status = SessionStatus::Running;
            current.active_turn_id = Some(native_turn_id.clone());
        }
        Ok(TurnStartResult {
            thread_id: input.thread_id,
            turn_id: native_turn_id.clone(),
            native_turn_id: Some(native_turn_id),
        })
    }

    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        let session = self.session_ref()?.clone();
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "interrupt threadId does not match session".into(),
            ));
        }
        let turn_id = input
            .turn_id
            .or(session.active_turn_id)
            .ok_or_else(|| ProviderError::InvalidState("no active Muse turn".into()))?;
        self.client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
            .interrupt_turn(&session.native_thread_id, &turn_id)
            .await
            .map_err(Self::sdk_error)?;
        Ok(())
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        let request_id = response.request_id().clone();
        let pending =
            self.pending.get(&request_id).cloned().ok_or_else(|| {
                ProviderError::InvalidState("unknown Muse runtime request".into())
            })?;
        match response {
            RuntimeResponse::Approval { decision, .. } => {
                self.respond_approval(pending, decision).await?
            }
            RuntimeResponse::UserInput { answers, .. } => {
                self.respond_user_input(pending, answers).await?
            }
            RuntimeResponse::Native { result, .. } => {
                if !matches!(
                    pending.kind,
                    RequestKind::DynamicToolCall | RequestKind::Unknown
                ) {
                    return Err(ProviderError::Validation(
                        "native response is incompatible with this Muse request".into(),
                    ));
                }
                let id = pending.wire_id.ok_or_else(|| {
                    ProviderError::Unsupported(
                        "native Muse response needs a server request id".into(),
                    )
                })?;
                self.client
                    .as_ref()
                    .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
                    .respond_server_request(id, result)
                    .await
                    .map_err(Self::sdk_error)?;
                self.pending.remove(&request_id);
            }
            RuntimeResponse::Elicitation { .. } => {
                return Err(ProviderError::Unsupported(
                    "Muse does not expose MCP elicitation through this adapter".into(),
                ))
            }
        }
        Ok(())
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        if let Some(event) = self.queued_events.pop_front() {
            return Ok(Some(event));
        }
        let frame = self
            .client
            .as_ref()
            .ok_or_else(|| ProviderError::InvalidState("Muse client unavailable".into()))?
            .next_frame()
            .await
            .map_err(Self::sdk_error)?;
        let Some(frame) = frame else {
            return Ok(None);
        };
        self.handle_frame(frame).await
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        if let Some(client) = &self.client {
            client.close().await.map_err(Self::sdk_error)?;
        }
        let provider = self.kind();
        let provider_instance_id = self.config.provider_instance_id.clone();
        if let Some(session) = &mut self.session {
            session.status = SessionStatus::Stopped;
            session.active_turn_id = None;
            let event = ProviderEvent::new(
                provider,
                provider_instance_id,
                session.thread_id.clone(),
                EventKind::SessionExited,
                serde_json::json!({"reason":"clientClosed","recoverable":true,"exitKind":"orderly"}),
                Some(RawEvent {
                    source: "muse.msp".into(),
                    method: Some("close".into()),
                    message_type: Some("session".into()),
                    payload: Value::Null,
                }),
            );
            event.validate()?;
            self.queued_events.push_back(event);
        }
        Ok(())
    }
}
