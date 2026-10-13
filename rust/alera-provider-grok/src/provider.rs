use crate::GrokProviderConfig;
use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig};
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::RuntimeMode;
use alera_provider_protocol::{Provider, ProviderError, ProviderKind};
use async_trait::async_trait;

pub struct GrokProvider<T> {
    inner: AcpProvider<T>,
    configured_model: Option<String>,
    launch_runtime_mode: RuntimeMode,
}

impl<T: JsonTransport> GrokProvider<T> {
    pub fn with_transport(transport: T, config: GrokProviderConfig) -> Result<Self, ProviderError> {
        config.validate()?;
        Ok(Self {
            inner: AcpProvider::with_transport(transport, acp_config(&config)),
            configured_model: config.model,
            launch_runtime_mode: config.runtime_mode,
        })
    }

    pub fn inner(&self) -> &AcpProvider<T> {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut AcpProvider<T> {
        &mut self.inner
    }
}

impl GrokProvider<JsonLineProcess> {
    pub async fn spawn(config: GrokProviderConfig) -> Result<Self, ProviderError> {
        config.validate()?;
        let process = JsonLineProcess::spawn(process_config(&config)).await?;
        Self::with_transport(process, config)
    }
}

#[async_trait]
impl<T: JsonTransport> Provider for GrokProvider<T> {
    fn kind(&self) -> ProviderKind {
        self.inner.kind()
    }

    fn capabilities(&self) -> alera_provider_protocol::ProviderCapabilities {
        self.inner.capabilities()
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
        if input.runtime_mode != self.launch_runtime_mode {
            return Err(ProviderError::Unsupported(format!(
                "Grok launch mode {:?} cannot serve session mode {:?}; spawn a provider with the requested mode",
                self.launch_runtime_mode,
                input.runtime_mode
            )));
        }
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

fn acp_config(config: &GrokProviderConfig) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("grok".into()),
        provider_instance_id: config.instance_id.clone(),
        process: process_config(config),
        client_name: "alera".into(),
        client_version: env!("CARGO_PKG_VERSION").into(),
        auth_method: Some(match config.resolved_auth_method() {
            crate::GrokAuthMethod::ApiKey => "xai.api_key".into(),
            crate::GrokAuthMethod::CachedToken => "cached_token".into(),
        }),
        authenticate_eagerly: false,
        flavor: AcpFlavor::Grok,
        // SessionStartInput owns the per-session policy. Keep the shared
        // runtime default conservative when it receives ApprovalRequired.
        runtime_mode: RuntimeMode::ApprovalRequired,
        request_timeout: config.request_timeout,
        max_queued_events: 1024,
        session_mode: None,
    }
}

fn process_config(config: &GrokProviderConfig) -> ProcessConfig {
    ProcessConfig {
        executable: config.executable.clone(),
        args: config.spawn_args(),
        cwd: config.cwd.clone(),
        env: config.effective_env(),
        max_frame_bytes: config.max_frame_bytes,
        shutdown_timeout: config.shutdown_timeout,
    }
}
