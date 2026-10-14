//! Keeps SDK-managed helpers alive for exactly one chat adapter.

use alera_agent_http::{HttpClientConfig, ReqwestTransport};
use alera_provider_protocol::{
    InterruptInput, NativeForkInput, NativeForkResult, NativeHistoryCapabilities,
    NativeRewindFilesInput, NativeRewindFilesResult, NativeRollbackInput, NativeRollbackResult,
    Provider, ProviderCapabilities, ProviderError, ProviderEvent, ProviderKind, ProviderSession,
    ReasoningEffortCapabilities, RuntimeResponse, SessionStartInput, TurnInput, TurnStartResult,
};
use async_trait::async_trait;

use super::super::provider_factory::BoxedProvider;

pub(super) struct OwnedProvider {
    provider: BoxedProvider,
    child: OwnedChild,
}

enum OwnedChild {
    Cursor(Box<cursor_agent_sdk::CursorBridge>),
    OpenCode(opencode_agent_sdk::OpenCodeServer),
}

impl OwnedProvider {
    pub(super) async fn cursor(
        config: alera_provider_cursor::CursorProviderConfig,
        bridge_config: cursor_agent_sdk::CursorBridgeConfig,
    ) -> Result<Self, ProviderError> {
        let bridge = cursor_agent_sdk::CursorBridge::spawn(bridge_config)
            .await
            .map_err(sdk_error)?;
        let provider = alera_provider_cursor::CursorProvider::from_bridge(&bridge, config);
        Ok(Self {
            provider: Box::new(provider),
            child: OwnedChild::Cursor(Box::new(bridge)),
        })
    }

    pub(super) async fn opencode(
        mut config: alera_provider_opencode::OpenCodeProviderConfig,
    ) -> Result<Self, ProviderError> {
        let mut server_config = config.local_server_config();
        // Each chat owns a server; port zero avoids collisions between chats.
        server_config.port = 0;
        let mut server = opencode_agent_sdk::OpenCodeServer::spawn(server_config)
            .await
            .map_err(sdk_error)?;
        config.server_password = server.password().map(str::to_owned);
        let transport = match ReqwestTransport::new(HttpClientConfig {
            base_url: server.url().to_owned(),
            request_timeout: config.request_timeout,
            ..Default::default()
        }) {
            Ok(transport) => transport,
            Err(error) => {
                let _ = server.close().await;
                return Err(sdk_error(error));
            }
        };
        let provider = local_opencode_provider(transport, config, server.url());
        Ok(Self {
            provider: Box::new(provider),
            child: OwnedChild::OpenCode(server),
        })
    }
}

pub(super) fn local_opencode_provider(
    transport: ReqwestTransport,
    mut config: alera_provider_opencode::OpenCodeProviderConfig,
    url: &str,
) -> alera_provider_opencode::OpenCodeProvider<ReqwestTransport> {
    // The client needs the ephemeral URL, but the adapter's config must keep
    // local ownership so its per-chat MCP isolation remains enabled.
    config.server_url = Some(url.to_owned());
    let mut provider = alera_provider_opencode::OpenCodeProvider::new(transport, config);
    provider.config_mut().server_url = None;
    provider
}

fn sdk_error(error: impl std::fmt::Display) -> ProviderError {
    ProviderError::Protocol(error.to_string())
}

#[async_trait]
impl Provider for OwnedProvider {
    fn kind(&self) -> ProviderKind {
        self.provider.kind()
    }
    fn capabilities(&self) -> ProviderCapabilities {
        self.provider.capabilities()
    }
    fn session(&self) -> Option<&ProviderSession> {
        self.provider.session()
    }
    fn reasoning_effort_capabilities(&self) -> ReasoningEffortCapabilities {
        self.provider.reasoning_effort_capabilities()
    }
    fn native_history_capabilities(&self) -> NativeHistoryCapabilities {
        self.provider.native_history_capabilities()
    }
    async fn initialize(&mut self) -> Result<(), ProviderError> {
        self.provider.initialize().await
    }
    async fn start_session(
        &mut self,
        input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        self.provider.start_session(input).await
    }
    async fn send_turn(&mut self, input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        self.provider.send_turn(input).await
    }
    async fn steer_turn(
        &mut self,
        input: TurnInput,
        expected_turn_id: &str,
    ) -> Result<(), ProviderError> {
        self.provider.steer_turn(input, expected_turn_id).await
    }
    async fn fork_session(
        &mut self,
        input: NativeForkInput,
    ) -> Result<NativeForkResult, ProviderError> {
        self.provider.fork_session(input).await
    }
    async fn rollback_session(
        &mut self,
        input: NativeRollbackInput,
    ) -> Result<NativeRollbackResult, ProviderError> {
        self.provider.rollback_session(input).await
    }
    async fn rewind_files(
        &mut self,
        input: NativeRewindFilesInput,
    ) -> Result<NativeRewindFilesResult, ProviderError> {
        self.provider.rewind_files(input).await
    }
    async fn interrupt(&mut self, input: InterruptInput) -> Result<(), ProviderError> {
        self.provider.interrupt(input).await
    }
    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.provider.respond(response).await
    }
    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.provider.next_event().await
    }
    async fn close(&mut self) -> Result<(), ProviderError> {
        let provider = self.provider.close().await;
        let child = match &mut self.child {
            OwnedChild::Cursor(child) => child.close().await.map_err(sdk_error),
            OwnedChild::OpenCode(child) => child.close().await.map_err(sdk_error),
        };
        provider.and(child)
    }
}
