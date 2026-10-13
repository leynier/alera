use crate::{config::PiProviderConfig, provider::PiProvider};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::ProviderError;
use serde_json::{Map, Value};

impl<T> PiProvider<T> {
    pub fn new(transport: T, config: PiProviderConfig) -> Self {
        Self {
            transport,
            config,
            initialized: false,
            closed: false,
            next_request_id: 1,
            next_turn_id: 0,
            pending_calls: std::collections::HashMap::new(),
            pending_order: std::collections::VecDeque::new(),
            pending_ui: std::collections::HashMap::new(),
            queued_messages: std::collections::VecDeque::new(),
            queued_events: std::collections::VecDeque::new(),
            session: None,
            native_state: Value::Null,
            interrupt_requested: false,
            available_models: Vec::new(),
            settle_message: None,
            baseline_model: None,
            prompt_failure: None,
            assistant_failure: None,
            session_exit_emitted: false,
            mcp_extension: None,
        }
    }

    pub fn with_transport(transport: T, config: PiProviderConfig) -> Self {
        Self::new(transport, config)
    }

    pub fn config(&self) -> &PiProviderConfig {
        &self.config
    }

    pub fn config_mut(&mut self) -> &mut PiProviderConfig {
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

    pub fn available_models(&self) -> &[Value] {
        &self.available_models
    }

    pub async fn refresh_models(&mut self) -> Result<(), ProviderError>
    where
        T: JsonTransport,
    {
        let data = self
            .call("get_available_models", Value::Object(Map::new()))
            .await?;
        self.available_models = data
            .get("models")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        Ok(())
    }
}
