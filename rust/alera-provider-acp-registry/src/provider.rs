use crate::client_terminals::ClientTerminals;
use crate::registry_flavor::{normalize_event, RegistryFlavorState};
use crate::{AcpRegistryAgentFlavor, AcpRegistryProviderConfig};
use crate::{ClientTerminalSpawner, NativeClientTerminalSpawner};
use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig};
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::RuntimeMode;
use alera_provider_protocol::{Provider, ProviderError, ProviderKind};
use async_trait::async_trait;
use std::sync::Arc;

#[cfg(test)]
#[path = "client_terminals_response_tests.rs"]
mod response_tests;

pub struct AcpRegistryProvider<T> {
    inner: AcpProvider<T>,
    configured_model: Option<String>,
    launch_runtime_mode: alera_provider_protocol::RuntimeMode,
    agent_flavor: AcpRegistryAgentFlavor,
    flavor_state: RegistryFlavorState,
    client_terminals: Option<Arc<ClientTerminals>>,
}

impl<T: JsonTransport> AcpRegistryProvider<T> {
    pub fn with_transport(
        transport: T,
        config: AcpRegistryProviderConfig,
    ) -> Result<Self, ProviderError> {
        Self::with_transport_and_terminal_spawner(
            transport,
            config,
            Arc::new(NativeClientTerminalSpawner),
        )
    }

    pub fn with_transport_and_terminal_spawner(
        transport: T,
        config: AcpRegistryProviderConfig,
        terminal_spawner: Arc<dyn ClientTerminalSpawner>,
    ) -> Result<Self, ProviderError> {
        config.validate()?;
        let agent_flavor = config.agent_flavor();
        let client_terminals = if agent_flavor == AcpRegistryAgentFlavor::Devin {
            Some(Arc::new(ClientTerminals::new(
                terminal_spawner,
                config.cwd.clone(),
                config.env.clone(),
                config.max_frame_bytes,
            )?))
        } else {
            None
        };
        let mut inner = AcpProvider::with_transport(transport, acp_config(&config));
        if let Some(terminals) = &client_terminals {
            inner.set_request_handler(Some(terminals.clone()));
        }
        Ok(Self {
            inner,
            configured_model: config.model,
            launch_runtime_mode: config.runtime_mode,
            agent_flavor,
            flavor_state: RegistryFlavorState::default(),
            client_terminals,
        })
    }

    pub fn inner(&self) -> &AcpProvider<T> {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut AcpProvider<T> {
        &mut self.inner
    }

    pub fn agent_flavor(&self) -> AcpRegistryAgentFlavor {
        self.agent_flavor
    }
}

impl<T> Drop for AcpRegistryProvider<T> {
    fn drop(&mut self) {
        if let Some(terminals) = &self.client_terminals {
            terminals.shutdown_now();
        }
    }
}

impl AcpRegistryProvider<JsonLineProcess> {
    pub async fn spawn(config: AcpRegistryProviderConfig) -> Result<Self, ProviderError> {
        config.validate()?;
        let process = JsonLineProcess::spawn(resolved_process_config(&config)?).await?;
        Self::with_transport(process, config)
    }
}

#[async_trait]
impl<T: JsonTransport> Provider for AcpRegistryProvider<T> {
    fn kind(&self) -> ProviderKind {
        self.inner.kind()
    }

    fn capabilities(&self) -> alera_provider_protocol::ProviderCapabilities {
        self.inner.capabilities()
    }

    fn reasoning_effort_capabilities(
        &self,
    ) -> alera_provider_protocol::ReasoningEffortCapabilities {
        self.inner.reasoning_effort_capabilities()
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
                "ACP registry launch mode {:?} cannot serve session mode {:?} without an agent-specific mapping",
                self.launch_runtime_mode,
                input.runtime_mode
            )));
        }
        if input.runtime_mode != alera_provider_protocol::RuntimeMode::ApprovalRequired {
            return Err(ProviderError::Unsupported(
                "ACP registry has no generic runtime-mode mapping".into(),
            ));
        }
        if input.model.is_none() {
            input.model = self.configured_model.clone();
        }
        let session = self.inner.start_session(input).await?;
        if let Some(terminals) = &self.client_terminals {
            terminals.sync_session(&session);
        }
        Ok(session)
    }

    async fn send_turn(
        &mut self,
        input: alera_provider_protocol::TurnInput,
    ) -> Result<alera_provider_protocol::TurnStartResult, ProviderError> {
        let turn = self.inner.send_turn(input).await?;
        if let (Some(terminals), Some(session)) = (&self.client_terminals, self.inner.session()) {
            terminals.sync_session(session);
        }
        Ok(turn)
    }

    async fn interrupt(
        &mut self,
        input: alera_provider_protocol::InterruptInput,
    ) -> Result<(), ProviderError> {
        if self
            .inner
            .session()
            .is_some_and(|session| session.thread_id == input.thread_id)
        {
            if let Some(terminals) = &self.client_terminals {
                terminals.interrupt();
            }
        }
        self.inner.interrupt(input).await
    }

    async fn respond(
        &mut self,
        response: alera_provider_protocol::RuntimeResponse,
    ) -> Result<(), ProviderError> {
        if let Some(terminals) = &self.client_terminals {
            terminals.validate_response(&response)?;
        }
        self.inner.respond(response.clone()).await?;
        if let Some(terminals) = &self.client_terminals {
            terminals.record_response(&response);
        }
        Ok(())
    }

    async fn next_event(
        &mut self,
    ) -> Result<Option<alera_provider_protocol::ProviderEvent>, ProviderError> {
        let Some(mut event) = self.inner.next_event().await? else {
            if let Some(terminals) = &self.client_terminals {
                terminals.close().await?;
            }
            return Ok(None);
        };
        if let Some(terminals) = &self.client_terminals {
            terminals.observe(&mut event);
        }
        let event = normalize_event(event, self.agent_flavor, &mut self.flavor_state);
        event.validate()?;
        Ok(Some(event))
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        let terminal_result = match &self.client_terminals {
            Some(terminals) => terminals.close().await,
            None => Ok(()),
        };
        let provider_result = self.inner.close().await;
        terminal_result.and(provider_result)
    }
}

fn acp_config(config: &AcpRegistryProviderConfig) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("acpRegistry".into()),
        provider_instance_id: config.instance_id.clone(),
        process: process_config(config),
        client_name: "alera".into(),
        client_version: env!("CARGO_PKG_VERSION").into(),
        auth_method: config.auth_method_id.clone(),
        authenticate_eagerly: false,
        flavor: AcpFlavor::Registry,
        // SessionStartInput owns the per-session policy. Keep the shared
        // runtime default conservative when it receives ApprovalRequired.
        runtime_mode: RuntimeMode::ApprovalRequired,
        request_timeout: config.request_timeout,
        max_queued_events: 1024,
        session_mode: None,
    }
}

fn process_config(config: &AcpRegistryProviderConfig) -> ProcessConfig {
    ProcessConfig {
        executable: config.executable.clone().unwrap_or_default(),
        args: config.args.clone(),
        cwd: config.cwd.clone(),
        env: config.env.clone(),
        max_frame_bytes: config.max_frame_bytes,
        shutdown_timeout: config.shutdown_timeout,
    }
}

fn resolved_process_config(
    config: &AcpRegistryProviderConfig,
) -> Result<ProcessConfig, ProviderError> {
    let Some(executable) = config.executable.clone() else {
        return Err(ProviderError::Unsupported(
            "ACP registry launch recipe has not been resolved".into(),
        ));
    };
    Ok(ProcessConfig {
        executable,
        args: config.args.clone(),
        cwd: config.cwd.clone(),
        env: config.env.clone(),
        max_frame_bytes: config.max_frame_bytes,
        shutdown_timeout: config.shutdown_timeout,
    })
}
