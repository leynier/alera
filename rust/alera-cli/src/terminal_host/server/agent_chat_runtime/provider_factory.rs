//! Builds connected provider adapters. Production spawns each provider through
//! its crate's own `spawn`/`connect`; tests inject scripted providers.

use std::collections::BTreeMap;
use std::path::PathBuf;

use alera_provider_protocol::{McpServerSpec, Provider, ProviderError, RuntimeMode};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Launch overrides for one provider instance, read from
/// `agent-chat-providers.json`. Environment values reach the process only.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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
