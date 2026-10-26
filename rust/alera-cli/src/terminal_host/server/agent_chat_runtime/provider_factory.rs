//! Builds connected provider adapters. Production spawns each provider through
//! its crate's own `spawn`/`connect`; tests inject scripted providers.

use std::collections::BTreeMap;
use std::path::PathBuf;

use alera_provider_protocol::{McpServerSpec, Provider, ProviderError, ProviderSkill, RuntimeMode};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Launch overrides for one provider instance, read from
/// `agent-chat-providers.json`. Environment values reach the process only.
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProviderInstanceConfig {
    pub provider_instance_id: String,
    pub provider: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub executable: Option<PathBuf>,
    #[serde(default)]
    pub args: Option<Vec<String>>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub models: Vec<String>,
    #[serde(default)]
    pub default_model: Option<String>,
    /// Provider-specific settings, validated by the production launch builder:
    /// ACP authentication, OpenCode generation, or Cursor bridge endpoints.
    #[serde(default)]
    pub options: serde_json::Map<String, Value>,
    #[serde(default = "enabled_default")]
    pub enabled: bool,
    #[serde(skip)]
    pub secret_refs: BTreeMap<String, String>,
    #[serde(skip)]
    pub credential_scope: Option<(PathBuf, String)>,
}

fn enabled_default() -> bool {
    true
}

impl Default for ProviderInstanceConfig {
    fn default() -> Self {
        Self {
            provider_instance_id: String::new(),
            provider: String::new(),
            label: None,
            executable: None,
            args: None,
            env: BTreeMap::new(),
            models: Vec::new(),
            default_model: None,
            options: Default::default(),
            enabled: true,
            secret_refs: BTreeMap::new(),
            credential_scope: None,
        }
    }
}

impl std::fmt::Debug for ProviderInstanceConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProviderInstanceConfig")
            .field("provider_instance_id", &self.provider_instance_id)
            .field("provider", &self.provider)
            .field("enabled", &self.enabled)
            .field("environment_count", &self.env.len())
            .field("option_count", &self.options.len())
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Debug)]
pub(crate) struct ProviderStatus {
    pub available: bool,
    pub setup_required: bool,
    pub installed: Option<bool>,
    pub version: Option<String>,
    pub auth_status: String,
    pub unavailable_reason: Option<String>,
    pub setup: Value,
}

#[derive(Debug, Clone)]
pub(crate) struct ProviderLaunch {
    pub chat_id: String,
    /// The chat's provider generation; per-generation credentials key on it.
    pub generation: i64,
    pub provider: String,
    pub provider_instance_id: String,
    pub cwd: Option<PathBuf>,
    pub model: Option<String>,
    pub runtime_mode: RuntimeMode,
    pub instance: Option<ProviderInstanceConfig>,
    /// Filled by launch hooks: MCP servers to attach to this chat's session.
    /// Startup fails when the provider cannot carry one of them.
    pub mcp_servers: Vec<McpServerSpec>,
    /// Filled by launch hooks: extra process environment for this chat.
    pub env: BTreeMap<String, String>,
}

/// Runs before every provider spawn so other host modules can attach
/// per-chat configuration without the chat runtime knowing about them.
#[async_trait]
pub(crate) trait ProviderLaunchHook: Send + Sync + 'static {
    async fn prepare(&self, launch: &mut ProviderLaunch) -> Result<(), String>;

    /// Revokes per-generation sidecars when their provider session stops.
    /// Hooks that do not mint credentials can keep the default no-op.
    async fn revoke(&self, _chat_id: &str, _generation: i64, _reason: &str) -> Result<(), String> {
        Ok(())
    }
}

pub(crate) type BoxedProvider = Box<dyn Provider>;

#[async_trait]
pub(crate) trait ProviderFactory: Send + Sync + 'static {
    /// Spawns and connects the provider process. It is not initialized and
    /// has no session yet; the session actor does both.
    async fn spawn(&self, launch: &ProviderLaunch) -> Result<BoxedProvider, ProviderError>;

    /// Cheap availability check for the catalog: `Err` carries the reason.
    async fn availability(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> Result<(), String>;

    async fn status(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
    ) -> ProviderStatus {
        let availability = self.availability(provider, instance).await;
        ProviderStatus {
            available: availability.is_ok(),
            setup_required: false,
            installed: None,
            version: None,
            auth_status: "unknown".into(),
            unavailable_reason: availability.err(),
            setup: Value::Null,
        }
    }

    /// The skills an agent offers before it has a session, for the composer's
    /// `$` menu. `None` means the provider only reports them from a live
    /// session (ACP agents, Pi), or offers none.
    async fn discover_skills(
        &self,
        _provider: &str,
        _instance: Option<&ProviderInstanceConfig>,
        _cwd: Option<PathBuf>,
        _refresh: bool,
    ) -> Option<Result<Vec<ProviderSkill>, String>> {
        None
    }

    async fn discover_model_metadata(
        &self,
        provider: &str,
        instance: Option<&ProviderInstanceConfig>,
        cwd: Option<PathBuf>,
    ) -> Option<Result<Vec<Value>, String>> {
        self.discover_models(provider, instance, cwd)
            .await
            .map(|result| {
                result.map(|models| {
                    models
                        .into_iter()
                        .map(|id| serde_json::json!({"id":id,"label":id}))
                        .collect()
                })
            })
    }

    async fn validate_reasoning_effort(
        &self,
        _provider: &str,
        _instance: Option<&ProviderInstanceConfig>,
        _cwd: Option<PathBuf>,
        _model: Option<&str>,
        _effort: &str,
    ) -> Result<(), String> {
        Err("This agent does not support reasoning effort.".into())
    }

    /// Cached proof from a bounded authenticated discovery request, when supported.
    async fn cached_verified_auth_status(
        &self,
        _provider: &str,
        _instance: Option<&ProviderInstanceConfig>,
    ) -> Option<(String, String)> {
        None
    }

    /// Models the provider reports without running inference, when it has a
    /// cheap discovery path. `None` means no discovery exists.
    async fn discover_models(
        &self,
        _provider: &str,
        _instance: Option<&ProviderInstanceConfig>,
        _cwd: Option<PathBuf>,
    ) -> Option<Result<Vec<String>, String>> {
        None
    }
}
