use alera_provider_protocol::{ProviderError, RuntimeMode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AcpRegistrySource {
    #[default]
    Registry,
    Local,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AcpDistribution {
    #[default]
    Auto,
    Binary,
    Npx,
    Uvx,
}

/// Native exceptions documented by the registry adapter. Standard ACP
/// messages remain available for every flavor; this metadata lets a caller
/// select a provider-specific extension when one exists.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum AcpRegistryAgentFlavor {
    #[default]
    Generic,
    Devin,
    Copilot,
    MistralVibe,
}

impl AcpRegistryAgentFlavor {
    pub fn for_recipe(
        source: AcpRegistrySource,
        agent_id: &str,
        executable: Option<&Path>,
    ) -> Self {
        let normalized = agent_id.trim().to_ascii_lowercase();
        if normalized == "devin" {
            return Self::Devin;
        }
        if normalized == "mistral-vibe" {
            return Self::MistralVibe;
        }
        if normalized == "github-copilot-cli"
            || (source == AcpRegistrySource::Local
                && executable
                    .and_then(|path| path.file_name())
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| {
                        name.eq_ignore_ascii_case("copilot")
                            || name.eq_ignore_ascii_case("copilot.exe")
                            || name.eq_ignore_ascii_case("copilot.cmd")
                    }))
        {
            return Self::Copilot;
        }
        Self::Generic
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AcpRegistryRecipe {
    pub agent_id: String,
    pub executable: PathBuf,
    #[serde(default)]
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    #[serde(default)]
    pub env: BTreeMap<OsString, OsString>,
    pub auth_method_id: Option<String>,
}

impl AcpRegistryRecipe {
    pub fn validate(&self) -> Result<(), ProviderError> {
        if self.agent_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "agentId must not be empty".into(),
            ));
        }
        if self.executable.as_os_str().is_empty() {
            return Err(ProviderError::Validation(
                "executable must not be empty".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct AcpRegistryProviderConfig {
    pub source: AcpRegistrySource,
    pub agent_id: String,
    pub executable: Option<PathBuf>,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub auth_method_id: Option<String>,
    pub distribution: AcpDistribution,
    pub custom_models: Vec<String>,
    pub model: Option<String>,
    pub instance_id: String,
    pub runtime_mode: RuntimeMode,
    pub request_timeout: Duration,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
}

impl Default for AcpRegistryProviderConfig {
    fn default() -> Self {
        Self {
            source: AcpRegistrySource::Registry,
            agent_id: String::new(),
            executable: None,
            args: Vec::new(),
            cwd: None,
            env: BTreeMap::new(),
            auth_method_id: None,
            distribution: AcpDistribution::Auto,
            custom_models: Vec::new(),
            model: None,
            instance_id: "acp-registry-default".to_owned(),
            runtime_mode: RuntimeMode::ApprovalRequired,
            request_timeout: Duration::from_secs(120),
            max_frame_bytes: 1024 * 1024,
            shutdown_timeout: Duration::from_secs(5),
        }
    }
}

impl AcpRegistryProviderConfig {
    pub fn validate(&self) -> Result<(), ProviderError> {
        if self.instance_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "instanceId must not be empty".into(),
            ));
        }
        if self.agent_id.trim().is_empty() {
            return Err(ProviderError::Validation(
                "ACP registry source requires agentId".into(),
            ));
        }
        if self.source == AcpRegistrySource::Local && self.executable.is_none() {
            return Err(ProviderError::Validation(
                "local source requires executable".into(),
            ));
        }
        Ok(())
    }

    pub fn recipe(&self) -> Option<AcpRegistryRecipe> {
        self.executable.clone().map(|executable| AcpRegistryRecipe {
            agent_id: self.agent_id.clone(),
            executable,
            args: self.args.clone(),
            cwd: self.cwd.clone(),
            env: self.env.clone(),
            auth_method_id: self.auth_method_id.clone(),
        })
    }

    pub fn agent_flavor(&self) -> AcpRegistryAgentFlavor {
        AcpRegistryAgentFlavor::for_recipe(self.source, &self.agent_id, self.executable.as_deref())
    }

    pub fn from_recipe(recipe: AcpRegistryRecipe) -> Result<Self, ProviderError> {
        recipe.validate()?;
        Ok(Self {
            source: AcpRegistrySource::Registry,
            agent_id: recipe.agent_id,
            executable: Some(recipe.executable),
            args: recipe.args,
            cwd: recipe.cwd,
            env: recipe.env,
            auth_method_id: recipe.auth_method_id,
            ..Self::default()
        })
    }
}
