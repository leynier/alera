use cursor_agent_sdk::CursorClientConfig;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct CursorProviderConfig {
    pub provider_instance_id: String,
    pub bridge_url: String,
    pub bridge_bearer_token: String,
    pub allow_remote_bridge: bool,
    pub api_key: Option<String>,
    pub cwd: Option<PathBuf>,
    pub model: Option<String>,
    pub request_timeout: Duration,
}

impl Default for CursorProviderConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: "cursor".into(),
            bridge_url: "http://127.0.0.1:0".into(),
            bridge_bearer_token: String::new(),
            allow_remote_bridge: false,
            api_key: None,
            cwd: None,
            model: None,
            request_timeout: Duration::from_secs(30),
        }
    }
}

impl CursorProviderConfig {
    pub fn client_config(&self) -> CursorClientConfig {
        CursorClientConfig {
            base_url: self.bridge_url.clone(),
            bearer_token: self.bridge_bearer_token.clone(),
            timeout: self.request_timeout,
            allow_remote_endpoint: self.allow_remote_bridge,
        }
    }
}
