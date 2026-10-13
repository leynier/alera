use crate::config::AcpProviderConfig;
use crate::provider::AcpProvider;
use crate::transport::BoxedTransport;
use agent_client_protocol::AcpClientRequestHandler;
use alera_agent_transport::{JsonLineProcess, JsonTransport};
use alera_provider_protocol::ProviderError;
use std::sync::Arc;

impl<T: JsonTransport> AcpProvider<T> {
    pub fn with_transport(transport: T, config: AcpProviderConfig) -> Self {
        let mut client = agent_client_protocol::AcpClient::with_options(
            transport,
            config.request_timeout,
            config.max_queued_events.max(32),
        );
        client.set_max_response_frame_bytes(config.process.max_frame_bytes);
        Self {
            client,
            config,
            session: None,
            queued_events: std::collections::VecDeque::new(),
            pending_requests: std::collections::HashMap::new(),
            prompt_id: None,
            prompt_meta_id: None,
            session_config_options: Vec::new(),
            initialized: false,
            closed: false,
        }
    }

    pub fn config(&self) -> &AcpProviderConfig {
        &self.config
    }

    pub fn config_mut(&mut self) -> &mut AcpProviderConfig {
        &mut self.config
    }

    pub fn client(&self) -> &agent_client_protocol::AcpClient<T> {
        &self.client
    }

    pub fn client_mut(&mut self) -> &mut agent_client_protocol::AcpClient<T> {
        &mut self.client
    }

    pub fn set_request_handler(&mut self, handler: Option<Arc<dyn AcpClientRequestHandler>>) {
        self.client.set_request_handler(handler);
    }

    pub fn queued_event_count(&self) -> usize {
        self.queued_events.len()
    }

    pub fn pending_request_count(&self) -> usize {
        self.pending_requests.len()
    }
}

impl AcpProvider<BoxedTransport> {
    pub fn with_boxed_transport(
        transport: Box<dyn JsonTransport>,
        config: AcpProviderConfig,
    ) -> Self {
        Self::from_boxed_transport(transport, config)
    }

    pub fn from_boxed_transport(
        transport: Box<dyn JsonTransport>,
        config: AcpProviderConfig,
    ) -> Self {
        Self::with_transport(BoxedTransport::new(transport), config)
    }
}

impl AcpProvider<JsonLineProcess> {
    pub async fn spawn(config: AcpProviderConfig) -> Result<Self, ProviderError> {
        config.validate().map_err(ProviderError::Validation)?;
        let transport = JsonLineProcess::spawn(config.process.clone()).await?;
        Ok(Self::with_transport(transport, config))
    }
}
