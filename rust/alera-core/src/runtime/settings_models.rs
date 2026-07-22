use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeSettings {
    #[serde(default)]
    pub workspace_directory: Option<String>,
    #[serde(default = "default_true")]
    pub confirm_project_removal: bool,
    #[serde(default = "default_true")]
    pub confirm_workspace_removal: bool,
    #[serde(default)]
    pub agent_status_hooks: RuntimeAgentStatusHookSettings,
    #[serde(default)]
    pub agent_quotas: RuntimeAgentQuotaSettings,
}

impl Default for RuntimeSettings {
    fn default() -> Self {
        Self {
            workspace_directory: None,
            confirm_project_removal: true,
            confirm_workspace_removal: true,
            agent_status_hooks: RuntimeAgentStatusHookSettings::default(),
            agent_quotas: RuntimeAgentQuotaSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentQuotaSettings {
    #[serde(default = "default_quota_providers")]
    pub enabled_providers: Vec<String>,
    #[serde(default = "default_true")]
    pub claude_default_enabled: bool,
    #[serde(default)]
    pub claude_profiles: Vec<RuntimeClaudeQuotaProfile>,
    #[serde(default)]
    pub environment: RuntimeAgentQuotaEnvironment,
}

impl Default for RuntimeAgentQuotaSettings {
    fn default() -> Self {
        Self {
            enabled_providers: default_quota_providers(),
            claude_default_enabled: true,
            claude_profiles: Vec::new(),
            environment: RuntimeAgentQuotaEnvironment::default(),
        }
    }
}

impl RuntimeAgentQuotaSettings {
    pub fn normalized(mut self) -> Self {
        const SUPPORTED: [&str; 8] = [
            "claude",
            "codex",
            "kimi",
            "grok",
            "cursor",
            "antigravity",
            "minimax",
            "zai",
        ];
        let mut seen = std::collections::HashSet::new();
        self.enabled_providers.retain(|provider| {
            SUPPORTED.contains(&provider.as_str()) && seen.insert(provider.clone())
        });
        for profile in &mut self.claude_profiles {
            profile.alias = profile.alias.trim().to_string();
            profile.profile = profile.profile.trim().to_string();
        }
        self.claude_profiles
            .retain(|profile| !profile.alias.is_empty() && !profile.profile.is_empty());
        self.environment.normalize();
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeClaudeQuotaProfile {
    pub alias: String,
    pub profile: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentQuotaEnvironment {
    #[serde(default = "default_kimi_api_key")]
    pub kimi_api_key: String,
    #[serde(default = "default_zai_api_key")]
    pub zai_api_key: String,
    #[serde(default = "default_zai_base_url")]
    pub zai_base_url: String,
    #[serde(default = "default_minimax_api_key")]
    pub minimax_api_key: String,
    #[serde(default = "default_minimax_api_host")]
    pub minimax_api_host: String,
}

impl Default for RuntimeAgentQuotaEnvironment {
    fn default() -> Self {
        Self {
            kimi_api_key: default_kimi_api_key(),
            zai_api_key: default_zai_api_key(),
            zai_base_url: default_zai_base_url(),
            minimax_api_key: default_minimax_api_key(),
            minimax_api_host: default_minimax_api_host(),
        }
    }
}

impl RuntimeAgentQuotaEnvironment {
    fn normalize(&mut self) {
        self.kimi_api_key = non_blank_or(&self.kimi_api_key, default_kimi_api_key);
        self.zai_api_key = non_blank_or(&self.zai_api_key, default_zai_api_key);
        self.zai_base_url = non_blank_or(&self.zai_base_url, default_zai_base_url);
        self.minimax_api_key = non_blank_or(&self.minimax_api_key, default_minimax_api_key);
        self.minimax_api_host = non_blank_or(&self.minimax_api_host, default_minimax_api_host);
    }
}

fn default_quota_providers() -> Vec<String> {
    [
        "claude",
        "codex",
        "kimi",
        "grok",
        "cursor",
        "antigravity",
        "minimax",
        "zai",
    ]
    .into_iter()
    .map(str::to_string)
    .collect()
}

fn non_blank_or(value: &str, fallback: fn() -> String) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback()
    } else {
        value.to_string()
    }
}

fn default_kimi_api_key() -> String {
    "KIMI_API_KEY".to_string()
}

fn default_zai_api_key() -> String {
    "ZAI_API_KEY".to_string()
}

fn default_zai_base_url() -> String {
    "ZAI_BASE_URL".to_string()
}

fn default_minimax_api_key() -> String {
    "MINIMAX_API_KEY".to_string()
}

fn default_minimax_api_host() -> String {
    "MINIMAX_API_HOST".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAgentStatusHookSettings {
    #[serde(default)]
    pub codex: bool,
    #[serde(default)]
    pub claude: bool,
    #[serde(default)]
    pub copilot: bool,
    #[serde(default)]
    pub cursor: bool,
    #[serde(default)]
    pub agy: bool,
    #[serde(default)]
    pub opencode: bool,
    #[serde(default)]
    pub pi: bool,
    #[serde(default)]
    pub amp: bool,
    #[serde(default)]
    pub grok: bool,
}

impl RuntimeAgentStatusHookSettings {
    pub fn is_enabled(&self, agent: &str) -> bool {
        match agent {
            "codex" => self.codex,
            "claude" => self.claude,
            "copilot" => self.copilot,
            "cursor" => self.cursor,
            "agy" => self.agy,
            "opencode" => self.opencode,
            "pi" => self.pi,
            "amp" => self.amp,
            "grok" => self.grok,
            _ => false,
        }
    }

    pub fn set_enabled(&mut self, agent: &str, enabled: bool) -> bool {
        let target = match agent {
            "codex" => &mut self.codex,
            "claude" => &mut self.claude,
            "copilot" => &mut self.copilot,
            "cursor" => &mut self.cursor,
            "agy" => &mut self.agy,
            "opencode" => &mut self.opencode,
            "pi" => &mut self.pi,
            "amp" => &mut self.amp,
            "grok" => &mut self.grok,
            _ => return false,
        };
        *target = enabled;
        true
    }

    pub fn enabled_agents(&self) -> Vec<&'static str> {
        const AGENTS: [&str; 9] = [
            "codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp", "grok",
        ];
        AGENTS
            .into_iter()
            .filter(|agent| self.is_enabled(agent))
            .collect()
    }
}

fn default_true() -> bool {
    true
}
