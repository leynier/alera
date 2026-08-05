use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
    pub default_agent_profile_id: Option<String>,
    #[serde(default)]
    pub agent_status_hooks: RuntimeAgentStatusHookSettings,
    #[serde(default)]
    pub agent_quotas: RuntimeAgentQuotaSettings,
    #[serde(default)]
    pub mobile_push_notifications: RuntimeMobilePushSettings,
    #[serde(default)]
    pub ai_text_generation: Option<RuntimeAiTextGenerationSettings>,
    #[serde(default)]
    pub text_actions: Option<RuntimeTextActionsSettings>,
    #[serde(default)]
    pub automation: RuntimeAutomationSettings,
}

impl Default for RuntimeSettings {
    fn default() -> Self {
        Self {
            workspace_directory: None,
            confirm_project_removal: true,
            confirm_workspace_removal: true,
            default_agent_profile_id: None,
            agent_status_hooks: RuntimeAgentStatusHookSettings::default(),
            agent_quotas: RuntimeAgentQuotaSettings::default(),
            mobile_push_notifications: RuntimeMobilePushSettings::default(),
            ai_text_generation: None,
            text_actions: None,
            automation: RuntimeAutomationSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAutomationSettings {
    #[serde(default)]
    pub autostart: bool,
    #[serde(default = "default_run_retention_days")]
    pub run_retention_days: i64,
    #[serde(default = "default_audit_retention_days")]
    pub audit_retention_days: i64,
    #[serde(default = "default_trash_retention_days")]
    pub trash_retention_days: i64,
}

impl Default for RuntimeAutomationSettings {
    fn default() -> Self {
        Self {
            autostart: false,
            run_retention_days: default_run_retention_days(),
            audit_retention_days: default_audit_retention_days(),
            trash_retention_days: default_trash_retention_days(),
        }
    }
}

fn default_run_retention_days() -> i64 {
    30
}

fn default_audit_retention_days() -> i64 {
    90
}

fn default_trash_retention_days() -> i64 {
    30
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeMobilePushSettings {
    /// Explicit runtime-level opt-in. Category defaults are inert until this
    /// switch is enabled by the account owner.
    #[serde(default)]
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub attention: bool,
    #[serde(default)]
    pub done: bool,
    #[serde(default)]
    pub terminal_exit: bool,
}

impl Default for RuntimeMobilePushSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            attention: true,
            done: false,
            terminal_exit: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAiTextGenerationSettings {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_ai_text_agent")]
    pub agent: String,
    #[serde(default)]
    pub selected_model_by_agent: HashMap<String, String>,
    #[serde(default)]
    pub selected_thinking_by_model: HashMap<String, String>,
    #[serde(default)]
    pub selected_thinking_by_operation: HashMap<String, HashMap<String, String>>,
    #[serde(default)]
    pub custom_command: String,
    #[serde(default)]
    pub instructions_by_operation: HashMap<String, String>,
    #[serde(default)]
    pub prompt_settings_by_operation: HashMap<String, RuntimeAiTextPromptSettings>,
    #[serde(default = "default_ai_text_timeout")]
    pub timeout_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeAiTextPromptSettings {
    #[serde(default)]
    pub agent: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeTextActionsSettings {
    #[serde(default)]
    pub actions: Vec<RuntimeTextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeTextAction {
    pub id: String,
    pub name: String,
    pub prompt: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub agent_override: Option<String>,
    #[serde(default)]
    pub model_override: Option<String>,
    #[serde(default)]
    pub reasoning_by_model: HashMap<String, String>,
}

impl RuntimeTextActionsSettings {
    pub fn normalized(mut self) -> Self {
        self.actions = self
            .actions
            .into_iter()
            .map(RuntimeTextAction::normalized)
            .collect();
        self
    }
}

impl RuntimeTextAction {
    fn normalized(mut self) -> Self {
        self.id = self.id.trim().to_string();
        self.name = self.name.trim().to_string();
        self.prompt = self.prompt.trim().to_string();
        self.agent_override = self
            .agent_override
            .map(|value| value.trim().to_ascii_lowercase())
            .filter(|value| !value.is_empty());
        self.model_override = self
            .model_override
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
        self.reasoning_by_model = normalized_string_map(self.reasoning_by_model);
        self
    }
}

impl Default for RuntimeAiTextGenerationSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            agent: default_ai_text_agent(),
            selected_model_by_agent: HashMap::new(),
            selected_thinking_by_model: HashMap::new(),
            selected_thinking_by_operation: HashMap::new(),
            custom_command: String::new(),
            instructions_by_operation: HashMap::new(),
            prompt_settings_by_operation: HashMap::new(),
            timeout_seconds: default_ai_text_timeout(),
        }
    }
}

impl RuntimeAiTextGenerationSettings {
    pub fn normalized(mut self) -> Self {
        self.agent = self.agent.trim().to_ascii_lowercase();
        self.custom_command = self.custom_command.trim().to_string();
        self.selected_model_by_agent = normalized_string_map(self.selected_model_by_agent);
        self.selected_thinking_by_model = normalized_string_map(self.selected_thinking_by_model);
        self.selected_thinking_by_operation = self
            .selected_thinking_by_operation
            .into_iter()
            .filter_map(|(operation, values)| {
                let operation = operation.trim().to_string();
                let values = normalized_string_map(values);
                (!operation.is_empty() && !values.is_empty()).then_some((operation, values))
            })
            .collect();
        self.instructions_by_operation = normalized_string_map(self.instructions_by_operation);
        self.prompt_settings_by_operation = self
            .prompt_settings_by_operation
            .into_iter()
            .filter_map(|(operation, settings)| {
                let operation = operation.trim().to_string();
                let agent = settings
                    .agent
                    .map(|value| value.trim().to_ascii_lowercase())
                    .filter(|value| !value.is_empty());
                let model = settings
                    .model
                    .map(|value| value.trim().to_string())
                    .filter(|value| !value.is_empty());
                (!operation.is_empty() && (agent.is_some() || model.is_some()))
                    .then_some((operation, RuntimeAiTextPromptSettings { agent, model }))
            })
            .collect();
        self.timeout_seconds = self.timeout_seconds.clamp(10, 600);
        self
    }
}

fn normalized_string_map(values: HashMap<String, String>) -> HashMap<String, String> {
    values
        .into_iter()
        .filter_map(|(key, value)| {
            let key = key.trim().to_string();
            let value = value.trim().to_string();
            (!key.is_empty() && !value.is_empty()).then_some((key, value))
        })
        .collect()
}

fn default_ai_text_agent() -> String {
    "codex".to_string()
}

fn default_ai_text_timeout() -> u64 {
    120
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
