use crate::{
    AntigravityProviderConfig, ANTIGRAVITY_AUTH_METHOD, ANTIGRAVITY_CLIENT_NAME,
    ANTIGRAVITY_CLIENT_VERSION,
};
use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig};
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::RuntimeMode;
use alera_provider_protocol::{Provider, ProviderError, ProviderKind};
use async_trait::async_trait;

pub struct AntigravityProvider<T> {
    inner: AcpProvider<T>,
    configured_model: Option<String>,
}

impl<T: JsonTransport> AntigravityProvider<T> {
    pub fn with_transport(
        transport: T,
        config: AntigravityProviderConfig,
    ) -> Result<Self, ProviderError> {
        config.validate()?;
        Ok(Self {
            inner: AcpProvider::with_transport(transport, acp_config(&config)),
            configured_model: config.model,
        })
    }

    pub fn inner(&self) -> &AcpProvider<T> {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut AcpProvider<T> {
        &mut self.inner
    }
}

impl AntigravityProvider<JsonLineProcess> {
    pub async fn spawn(config: AntigravityProviderConfig) -> Result<Self, ProviderError> {
        config.validate()?;
        let process = JsonLineProcess::spawn(process_config(&config)).await?;
        Self::with_transport(process, config)
    }
}

#[async_trait]
impl<T: JsonTransport> Provider for AntigravityProvider<T> {
    fn kind(&self) -> ProviderKind {
        self.inner.kind()
    }

    fn capabilities(&self) -> alera_provider_protocol::ProviderCapabilities {
        self.inner.capabilities()
    }

    /// Before a session exists, the wire support: thinking levels are set
    /// through the session's `thought_level` option at start and before a
    /// turn, so the runtime may pass a level the catalog verified. A live
    /// session reports its own levels.
    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        if self.inner.session().is_some() {
            return self.inner.reasoning_effort_capabilities();
        }
        alera_provider_protocol::ReasoningEffortCapabilities {
            session: true,
            turn: true,
            model_specific: true,
            values: Vec::new(),
            session_wire_field: Some("session/set_config_option {configId,value}".into()),
            turn_wire_field: Some("session/set_config_option before session/prompt".into()),
        }
    }

    fn session(&self) -> Option<&alera_provider_protocol::ProviderSession> {
        self.inner.session()
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.inner.initialize().await
    }

    async fn start_session(
        &mut self,
        mut input: alera_provider_protocol::SessionStartInput,
    ) -> Result<alera_provider_protocol::ProviderSession, ProviderError> {
        if input.model.is_none() {
            input.model = self.configured_model.clone();
        }
        self.inner.start_session(input).await
    }

    async fn send_turn(
        &mut self,
        input: alera_provider_protocol::TurnInput,
    ) -> Result<alera_provider_protocol::TurnStartResult, ProviderError> {
        self.inner.send_turn(input).await
    }

    async fn interrupt(
        &mut self,
        input: alera_provider_protocol::InterruptInput,
    ) -> Result<(), ProviderError> {
        self.inner.interrupt(input).await
    }

    async fn respond(
        &mut self,
        response: alera_provider_protocol::RuntimeResponse,
    ) -> Result<(), ProviderError> {
        self.inner.respond(response).await
    }

    async fn next_event(
        &mut self,
    ) -> Result<Option<alera_provider_protocol::ProviderEvent>, ProviderError> {
        self.inner.next_event().await
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        self.inner.close().await
    }
}

fn acp_config(config: &AntigravityProviderConfig) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("antigravity".into()),
        provider_instance_id: config.instance_id.clone(),
        process: process_config(config),
        client_name: ANTIGRAVITY_CLIENT_NAME.into(),
        client_version: ANTIGRAVITY_CLIENT_VERSION.into(),
        auth_method: Some(if config.auth_method_id.trim().is_empty() {
            ANTIGRAVITY_AUTH_METHOD.to_owned()
        } else {
            config.auth_method_id.clone()
        }),
        authenticate_eagerly: true,
        flavor: AcpFlavor::Antigravity,
        // SessionStartInput owns the per-session policy. Keep the shared
        // runtime default conservative when it receives ApprovalRequired.
        runtime_mode: RuntimeMode::ApprovalRequired,
        request_timeout: config.request_timeout,
        max_queued_events: 1024,
        session_mode: None,
        native_child_sessions: false,
        custom_models: config.custom_models.clone(),
        reports_per_turn_prompt_usage: false,
    }
}

fn process_config(config: &AntigravityProviderConfig) -> ProcessConfig {
    ProcessConfig {
        executable: config.executable.clone(),
        args: config.spawn_args_for_platform(std::env::consts::OS),
        cwd: config.cwd.clone(),
        env: config.effective_env(),
        max_frame_bytes: config.max_frame_bytes,
        shutdown_timeout: config.shutdown_timeout,
    }
}
