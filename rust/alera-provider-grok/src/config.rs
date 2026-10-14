use alera_provider_protocol::{ProviderError, RuntimeMode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::PathBuf;
use std::time::Duration;

pub const GROK_OAUTH2_REFERRER: &str = "GROK_OAUTH2_REFERRER";
pub const DEFAULT_GROK_OAUTH_REFERRER: &str = "alera";
pub const XAI_API_KEY: &str = "XAI_API_KEY";

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GrokAuthMethod {
    ApiKey,
    #[default]
    CachedToken,
}

#[derive(Debug, Clone)]
pub struct GrokProviderConfig {
    pub executable: PathBuf,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub instance_id: String,
    pub model: Option<String>,
    pub auth_method: GrokAuthMethod,
    pub runtime_mode: RuntimeMode,
    pub request_timeout: Duration,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
}

impl Default for GrokProviderConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("grok"),
            cwd: None,
            env: BTreeMap::new(),
            instance_id: "grok-default".to_owned(),
            model: None,
            auth_method: GrokAuthMethod::default(),
            runtime_mode: RuntimeMode::ApprovalRequired,
            request_timeout: Duration::from_secs(120),
            max_frame_bytes: 1024 * 1024,
            shutdown_timeout: Duration::from_secs(5),
        }
    }
}

impl GrokProviderConfig {
    pub fn validate(&self) -> Result<(), ProviderError> {
        if self.instance_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "instanceId must not be empty".into(),
            ));
        }
        if matches!(self.runtime_mode, RuntimeMode::AutoAcceptEdits) {
            return Err(ProviderError::Unsupported(
                "Grok ACP does not expose an accept-edits runtime mode".into(),
            ));
        }
        Ok(())
    }

    pub fn spawn_args(&self) -> Vec<OsString> {
        grok_spawn_args(self.runtime_mode)
            .into_iter()
            .map(OsString::from)
            .collect()
    }

    pub fn effective_env(&self) -> BTreeMap<OsString, OsString> {
        let mut env = self.env.clone();
        env.entry(OsString::from(GROK_OAUTH2_REFERRER))
            .or_insert_with(|| OsString::from(DEFAULT_GROK_OAUTH_REFERRER));
        env
    }

    pub fn resolved_auth_method(&self) -> GrokAuthMethod {
        if self
            .env
            .get(OsStr::new(XAI_API_KEY))
            .and_then(|value| value.to_str())
            .is_some_and(|value| !value.trim().is_empty())
        {
            GrokAuthMethod::ApiKey
        } else {
            self.auth_method
        }
    }
}

pub fn grok_spawn_args(mode: RuntimeMode) -> Vec<&'static str> {
    match mode {
        RuntimeMode::ApprovalRequired => vec!["--permission-mode", "default", "agent", "stdio"],
        RuntimeMode::Auto => vec!["--permission-mode", "auto", "agent", "stdio"],
        RuntimeMode::FullAccess => vec!["agent", "--always-approve", "stdio"],
        RuntimeMode::AutoAcceptEdits => vec!["--permission-mode", "default", "agent", "stdio"],
    }
}
