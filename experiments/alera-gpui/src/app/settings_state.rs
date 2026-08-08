use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;

const DEFAULT_QUOTA_PROVIDERS: [&str; 8] = [
    "claude",
    "codex",
    "kimi",
    "grok",
    "cursor",
    "antigravity",
    "minimax",
    "zai",
];

const DEFAULT_AGENT_HOOKS: [&str; 9] = [
    "codex", "claude", "copilot", "cursor", "agy", "opencode", "pi", "amp", "grok",
];

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct ClaudeQuotaProfile {
    pub alias: String,
    pub profile: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct AiTextPromptSettings {
    pub agent: Option<String>,
    pub model: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct AiTextDiscoveredThinkingLevel {
    pub id: String,
    pub label: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct AiTextDiscoveredModel {
    pub id: String,
    pub label: String,
    pub thinking_levels: Vec<AiTextDiscoveredThinkingLevel>,
    pub default_thinking_level: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct CliRegistrationStatus {
    pub state: String,
    pub ready: bool,
    pub path_configured: bool,
    pub command_path: Option<String>,
    pub detail: String,
}

impl CliRegistrationStatus {
    pub(super) fn label(&self) -> &'static str {
        match self.state.as_str() {
            "installed" if self.ready => "Registered",
            "installed" if !self.path_configured => "Registered, Add To PATH",
            "installed" => "Registered",
            "notInstalled" => "Not Registered",
            "stale" => "Registration Needs Update",
            "conflict" => "Registration Conflict",
            "unsupported" => "Registration Unsupported",
            _ => "Registration Status Unknown",
        }
    }

    pub(super) fn blocks_install(&self) -> bool {
        matches!(self.state.as_str(), "conflict" | "unsupported")
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct SettingsState {
    pub settings_schema_version: u32,
    pub workspace_directory: String,
    pub confirm_project_removal: bool,
    pub confirm_workspace_removal: bool,
    pub keep_runtime_open_on_quit: bool,
    pub host_empty_shutdown_delay_seconds: i64,
    pub host_detached_shutdown_delay_seconds: i64,
    pub diagnostics_log_level: String,
    pub crash_reporting_enabled: bool,

    pub agent_status_hooks: BTreeMap<String, bool>,
    pub agent_status_notifications_enabled: bool,
    pub agent_status_finished_notifications_enabled: bool,
    pub keep_computer_awake_while_agents_work: bool,

    pub quota_enabled_providers: Vec<String>,
    pub quota_unpinned_keys: BTreeSet<String>,
    pub claude_default_enabled: bool,
    pub claude_profiles: Vec<ClaudeQuotaProfile>,
    pub selected_claude_profile: String,
    pub quota_environment: BTreeMap<String, String>,

    pub ai_text_enabled: bool,
    pub ai_text_agent: String,
    pub ai_text_selected_model_by_agent: BTreeMap<String, String>,
    pub ai_text_selected_thinking_by_model: BTreeMap<String, String>,
    pub ai_text_discovered_models_by_agent: BTreeMap<String, Vec<AiTextDiscoveredModel>>,
    pub ai_text_discovered_default_model_by_agent: BTreeMap<String, String>,
    pub ai_text_custom_command: String,
    pub ai_text_instructions_by_operation: BTreeMap<String, String>,
    pub ai_text_prompt_settings_by_operation: BTreeMap<String, AiTextPromptSettings>,
    pub ai_text_timeout_seconds: i64,

    pub editor_theme: String,
    pub editor_tab_size: i64,

    pub terminal_font_family: String,
    pub terminal_font_size: f64,
    pub terminal_font_weight: i64,
    pub terminal_line_height: f64,
    pub terminal_padding_x: f64,
    pub terminal_padding_y: f64,
    pub terminal_cursor_shape: String,
    pub terminal_cursor_blink: bool,
    pub terminal_cursor_opacity: f64,
    pub terminal_theme_name: String,
    pub terminal_background_opacity: f64,
    pub terminal_word_separators: Option<String>,
    pub terminal_color_overrides: BTreeMap<String, String>,
    pub terminal_scrollback_lines: i64,
    pub terminal_tui_scroll_sensitivity: i64,
    pub terminal_clipboard_on_select: bool,
    pub terminal_allow_osc52_clipboard: bool,
    pub terminal_host_scrollback_bytes: i64,
    pub terminal_buffer_budget_megabytes: i64,
    pub terminal_login_shell: bool,

    pub keyboard_terminal_policy: String,
    pub keyboard_overrides: BTreeMap<String, Vec<String>>,

    #[serde(skip)]
    pub loading: bool,
    #[serde(skip)]
    pub error: Option<String>,
    #[serde(skip)]
    pub toast: Option<String>,
    #[serde(skip)]
    pub generation: u64,
    #[serde(skip)]
    pub runtime_log_directory: Option<String>,
    #[serde(skip)]
    pub runtime_host_version: Option<String>,
    #[serde(skip)]
    pub runtime_host_commit: Option<String>,
    #[serde(skip)]
    pub runtime_protocol_version: Option<i64>,
    #[serde(skip)]
    pub runtime_capabilities: Vec<String>,
    #[serde(skip)]
    pub cli_registration_status: Option<CliRegistrationStatus>,
}

impl Default for SettingsState {
    fn default() -> Self {
        Self {
            settings_schema_version: 1,
            workspace_directory: "~/.alera/workspaces".to_string(),
            confirm_project_removal: true,
            confirm_workspace_removal: true,
            keep_runtime_open_on_quit: false,
            host_empty_shutdown_delay_seconds: 30,
            host_detached_shutdown_delay_seconds: 3600,
            diagnostics_log_level: "Info".to_string(),
            crash_reporting_enabled: false,
            agent_status_hooks: DEFAULT_AGENT_HOOKS
                .into_iter()
                .map(|agent| (agent.to_string(), false))
                .collect(),
            agent_status_notifications_enabled: false,
            agent_status_finished_notifications_enabled: false,
            keep_computer_awake_while_agents_work: false,
            quota_enabled_providers: DEFAULT_QUOTA_PROVIDERS
                .into_iter()
                .map(str::to_string)
                .collect(),
            quota_unpinned_keys: BTreeSet::new(),
            claude_default_enabled: true,
            claude_profiles: Vec::new(),
            selected_claude_profile: "default".to_string(),
            quota_environment: [
                ("kimiApiKey", "KIMI_API_KEY"),
                ("zaiApiKey", "ZAI_API_KEY"),
                ("zaiBaseUrl", "ZAI_BASE_URL"),
                ("minimaxApiKey", "MINIMAX_API_KEY"),
                ("minimaxApiHost", "MINIMAX_API_HOST"),
            ]
            .into_iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect(),
            ai_text_enabled: true,
            ai_text_agent: "codex".to_string(),
            ai_text_selected_model_by_agent: BTreeMap::new(),
            ai_text_selected_thinking_by_model: BTreeMap::new(),
            ai_text_discovered_models_by_agent: BTreeMap::new(),
            ai_text_discovered_default_model_by_agent: BTreeMap::new(),
            ai_text_custom_command: String::new(),
            ai_text_instructions_by_operation: BTreeMap::new(),
            ai_text_prompt_settings_by_operation: BTreeMap::new(),
            ai_text_timeout_seconds: 120,
            editor_theme: "Alera".to_string(),
            editor_tab_size: 4,
            terminal_font_family: "JetBrains Mono".to_string(),
            terminal_font_size: 13.0,
            terminal_font_weight: 400,
            terminal_line_height: 1.3,
            terminal_padding_x: 12.0,
            terminal_padding_y: 12.0,
            terminal_cursor_shape: "block".to_string(),
            terminal_cursor_blink: false,
            terminal_cursor_opacity: 1.0,
            terminal_theme_name: "Alera Dark".to_string(),
            terminal_background_opacity: 1.0,
            terminal_word_separators: None,
            terminal_color_overrides: BTreeMap::new(),
            terminal_scrollback_lines: 10_000,
            terminal_tui_scroll_sensitivity: 1,
            terminal_clipboard_on_select: false,
            terminal_allow_osc52_clipboard: false,
            terminal_host_scrollback_bytes: 10_000_000,
            terminal_buffer_budget_megabytes: 256,
            terminal_login_shell: cfg!(target_os = "macos"),
            keyboard_terminal_policy: "appFirst".to_string(),
            keyboard_overrides: BTreeMap::new(),
            loading: false,
            error: None,
            toast: None,
            generation: 0,
            runtime_log_directory: None,
            runtime_host_version: None,
            runtime_host_commit: None,
            runtime_protocol_version: None,
            runtime_capabilities: Vec::new(),
            cli_registration_status: None,
        }
    }
}

impl SettingsState {
    pub fn apply_runtime_settings(&mut self, value: &Value) {
        if let Some(directory) = value.get("workspaceDirectory") {
            self.workspace_directory = directory
                .as_str()
                .filter(|directory| !directory.trim().is_empty())
                .unwrap_or("~/.alera/workspaces")
                .to_string();
        }
        if let Some(enabled) = value.get("confirmProjectRemoval").and_then(Value::as_bool) {
            self.confirm_project_removal = enabled;
        }
        if let Some(enabled) = value
            .get("confirmWorkspaceRemoval")
            .and_then(Value::as_bool)
        {
            self.confirm_workspace_removal = enabled;
        }
        if let Some(hooks) = value.get("agentStatusHooks").and_then(Value::as_object) {
            for (agent, enabled) in hooks {
                if let Some(enabled) = enabled.as_bool() {
                    self.agent_status_hooks.insert(agent.clone(), enabled);
                }
            }
        }
        if let Some(quotas) = value.get("agentQuotas").and_then(Value::as_object) {
            self.apply_runtime_quotas(quotas);
        }
        if let Some(ai_text) = value.get("aiTextGeneration").and_then(Value::as_object) {
            self.apply_runtime_ai_text(ai_text);
        }
    }

    pub fn apply_host_status(&mut self, value: &Value) {
        self.runtime_log_directory = value
            .get("logDirectory")
            .and_then(Value::as_str)
            .filter(|path| !path.trim().is_empty())
            .map(str::to_owned);
        self.runtime_host_version = value
            .get("runtimeHostVersion")
            .and_then(Value::as_str)
            .map(str::to_owned);
        self.runtime_host_commit = value
            .get("runtimeHostCommit")
            .and_then(Value::as_str)
            .map(str::to_owned);
        self.runtime_protocol_version = value.get("protocolVersion").and_then(Value::as_i64);
        self.runtime_capabilities = value
            .get("runtimeCapabilities")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect();
        if let Some(enabled) = value
            .get("diagnostics")
            .and_then(|diagnostics| diagnostics.get("crashReportingEnabled"))
            .and_then(Value::as_bool)
        {
            self.crash_reporting_enabled = enabled;
        }
    }

    pub fn runtime_quota_payload(&self) -> Value {
        serde_json::json!({
            "enabledProviders": self.quota_enabled_providers,
            "claudeDefaultEnabled": self.claude_default_enabled,
            "claudeProfiles": self.claude_profiles,
            "selectedClaudeProfile": self.selected_claude_profile,
            "environment": self.quota_environment,
            "unpinnedQuotaKeys": self.quota_unpinned_keys,
        })
    }

    pub fn runtime_ai_text_payload(&self) -> Value {
        serde_json::json!({
            "enabled": self.ai_text_enabled,
            "agent": self.ai_text_agent,
            "selectedModelByAgent": self.ai_text_selected_model_by_agent,
            "selectedThinkingByModel": self.ai_text_selected_thinking_by_model,
            "discoveredModelsByAgent": self.ai_text_discovered_models_by_agent,
            "discoveredDefaultModelByAgent": self.ai_text_discovered_default_model_by_agent,
            "customCommand": self.ai_text_custom_command,
            "instructionsByOperation": self.ai_text_instructions_by_operation,
            "promptSettingsByOperation": self.ai_text_prompt_settings_by_operation,
            "timeoutSeconds": self.ai_text_timeout_seconds,
        })
    }

    fn apply_runtime_quotas(&mut self, quotas: &serde_json::Map<String, Value>) {
        if let Some(providers) = quotas.get("enabledProviders").and_then(Value::as_array) {
            self.quota_enabled_providers = providers
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect();
        }
        if let Some(enabled) = quotas.get("claudeDefaultEnabled").and_then(Value::as_bool) {
            self.claude_default_enabled = enabled;
        }
        if let Some(profiles) = quotas.get("claudeProfiles").and_then(Value::as_array) {
            self.claude_profiles = profiles
                .iter()
                .filter_map(|profile| serde_json::from_value(profile.clone()).ok())
                .collect();
        }
        if let Some(profile) = quotas.get("selectedClaudeProfile").and_then(Value::as_str) {
            self.selected_claude_profile = profile.to_string();
        }
        if let Some(environment) = quotas.get("environment").and_then(Value::as_object) {
            for (key, value) in environment {
                if let Some(value) = value.as_str() {
                    self.quota_environment
                        .insert(key.clone(), value.to_string());
                }
            }
        }
        if let Some(keys) = quotas.get("unpinnedQuotaKeys").and_then(Value::as_array) {
            self.quota_unpinned_keys = keys
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect();
        }
    }

    fn apply_runtime_ai_text(&mut self, ai_text: &serde_json::Map<String, Value>) {
        if let Some(enabled) = ai_text.get("enabled").and_then(Value::as_bool) {
            self.ai_text_enabled = enabled;
        }
        if let Some(agent) = ai_text.get("agent").and_then(Value::as_str) {
            self.ai_text_agent = agent.to_string();
        }
        if let Some(command) = ai_text.get("customCommand").and_then(Value::as_str) {
            self.ai_text_custom_command = command.to_string();
        }
        if let Some(timeout) = ai_text.get("timeoutSeconds").and_then(Value::as_i64) {
            self.ai_text_timeout_seconds = timeout;
        }
        apply_string_map(
            ai_text.get("selectedModelByAgent"),
            &mut self.ai_text_selected_model_by_agent,
        );
        apply_string_map(
            ai_text.get("selectedThinkingByModel"),
            &mut self.ai_text_selected_thinking_by_model,
        );
        apply_string_map(
            ai_text.get("discoveredDefaultModelByAgent"),
            &mut self.ai_text_discovered_default_model_by_agent,
        );
        if let Some(models) = ai_text
            .get("discoveredModelsByAgent")
            .and_then(Value::as_object)
        {
            self.ai_text_discovered_models_by_agent = models
                .iter()
                .filter_map(|(agent, value)| {
                    serde_json::from_value(value.clone())
                        .ok()
                        .map(|models| (agent.clone(), models))
                })
                .collect();
        }
        apply_string_map(
            ai_text.get("instructionsByOperation"),
            &mut self.ai_text_instructions_by_operation,
        );
        if let Some(settings) = ai_text
            .get("promptSettingsByOperation")
            .and_then(Value::as_object)
        {
            self.ai_text_prompt_settings_by_operation = settings
                .iter()
                .filter_map(|(operation, value)| {
                    serde_json::from_value(value.clone())
                        .ok()
                        .map(|settings| (operation.clone(), settings))
                })
                .collect();
        }
    }
}

fn apply_string_map(value: Option<&Value>, target: &mut BTreeMap<String, String>) {
    let Some(values) = value.and_then(Value::as_object) else {
        return;
    };
    *target = values
        .iter()
        .filter_map(|(key, value)| value.as_str().map(|value| (key.clone(), value.to_string())))
        .collect();
}

#[cfg(test)]
mod tests {
    use super::SettingsState;
    use serde_json::json;

    #[test]
    fn runtime_settings_merge_shared_surfaces_without_resetting_local_settings() {
        let mut state = SettingsState {
            editor_theme: "Dracula".to_string(),
            terminal_font_size: 17.0,
            ..SettingsState::default()
        };

        state.apply_runtime_settings(&json!({
            "workspaceDirectory": "/tmp/workspaces",
            "agentStatusHooks": {"codex": true},
            "agentQuotas": {
                "enabledProviders": ["codex", "kimi"],
                "environment": {"kimiApiKey": "KIMI_TOKEN"}
            },
            "aiTextGeneration": {
                "enabled": false,
                "agent": "opencode",
                "timeoutSeconds": 180
            }
        }));

        assert_eq!(state.workspace_directory, "/tmp/workspaces");
        assert_eq!(state.agent_status_hooks.get("codex"), Some(&true));
        assert_eq!(state.quota_enabled_providers, ["codex", "kimi"]);
        assert_eq!(state.ai_text_agent, "opencode");
        assert!(!state.ai_text_enabled);
        assert_eq!(state.editor_theme, "Dracula");
        assert_eq!(state.terminal_font_size, 17.0);
    }

    #[test]
    fn runtime_settings_load_discovered_ai_models_with_thinking_metadata() {
        let mut state = SettingsState::default();

        state.apply_runtime_settings(&json!({
            "aiTextGeneration": {
                "agent": "codex",
                "selectedModelByAgent": {
                    "codex": "gpt-5.3-codex-spark"
                },
                "selectedThinkingByModel": {
                    "gpt-5.3-codex-spark": "high"
                },
                "discoveredDefaultModelByAgent": {
                    "codex": "gpt-5.3-codex-spark"
                },
                "discoveredModelsByAgent": {
                    "codex": [{
                        "id": "gpt-5.3-codex-spark",
                        "label": "GPT-5.3 Codex Spark",
                        "thinkingLevels": [
                            {"id": "medium", "label": "Medium"},
                            {"id": "high", "label": "High"}
                        ],
                        "defaultThinkingLevel": "medium"
                    }]
                }
            }
        }));

        let discovered = &state.ai_text_discovered_models_by_agent["codex"][0];
        assert_eq!(discovered.id, "gpt-5.3-codex-spark");
        assert_eq!(discovered.label, "GPT-5.3 Codex Spark");
        assert_eq!(discovered.thinking_levels.len(), 2);
        assert_eq!(discovered.thinking_levels[1].id, "high");
        assert_eq!(discovered.default_thinking_level.as_deref(), Some("medium"));
        assert_eq!(
            state
                .ai_text_discovered_default_model_by_agent
                .get("codex")
                .map(String::as_str),
            Some("gpt-5.3-codex-spark")
        );
    }
}
