use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;

fn default_true() -> bool {
    true
}

const DEFAULT_QUOTA_PROVIDERS: [&str; 9] = [
    "claude",
    "codex",
    "kimi",
    "grok",
    "cursor",
    "antigravity",
    "minimax",
    "zai",
    "opencode",
];

const DEFAULT_AGENT_HOOKS: [&str; 11] = [
    "codex", "claude", "copilot", "cursor", "agy", "opencode", "opencode2", "pi", "amp", "grok", "fx",
];

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct ClaudeQuotaProfile {
    pub alias: String,
    pub profile: String,
    #[serde(default = "default_true")]
    pub show_in_usage: bool,
    #[serde(default)]
    pub usage_display_name: Option<String>,
}

impl ClaudeQuotaProfile {
    pub(super) fn usage_label(&self) -> String {
        self.usage_display_name
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or(&self.alias)
            .to_owned()
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct AiTextPromptSettings {
    pub agent: Option<String>,
    pub model: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub(super) struct TextActionSetting {
    pub id: String,
    pub name: String,
    pub prompt: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    pub agent_override: Option<String>,
    pub model_override: Option<String>,
    pub reasoning_by_model: BTreeMap<String, String>,
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum GitHubStarState {
    Loading,
    NotStarred,
    Starring,
    Starred,
    Error,
    Hidden,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct SettingsState {
    pub settings_schema_version: u32,
    pub workspace_directory: String,
    pub star_clicked: bool,
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
    pub default_agent_profile_id: Option<String>,

    pub quota_enabled_providers: Vec<String>,
    pub quota_unpinned_keys: BTreeSet<String>,
    pub claude_default_enabled: bool,
    pub claude_default_show_in_usage: bool,
    pub claude_profiles: Vec<ClaudeQuotaProfile>,
    pub selected_claude_profile: String,
    pub quota_environment: BTreeMap<String, String>,

    pub ai_text_enabled: bool,
    pub ai_text_agent: String,
    pub ai_text_selected_model_by_agent: BTreeMap<String, String>,
    pub ai_text_selected_thinking_by_model: BTreeMap<String, String>,
    pub ai_text_selected_thinking_by_operation: BTreeMap<String, BTreeMap<String, String>>,
    pub ai_text_discovered_models_by_agent: BTreeMap<String, Vec<AiTextDiscoveredModel>>,
    pub ai_text_discovered_default_model_by_agent: BTreeMap<String, String>,
    pub ai_text_custom_command: String,
    pub ai_text_instructions_by_operation: BTreeMap<String, String>,
    pub ai_text_prompt_settings_by_operation: BTreeMap<String, AiTextPromptSettings>,
    pub ai_text_timeout_seconds: i64,
    pub text_actions: Vec<TextActionSetting>,
    pub codex_chat_selected_model: Option<String>,
    pub codex_chat_reasoning_effort: String,
    pub codex_chat_speed_mode: String,
    pub codex_chat_permission_mode: String,
    pub codex_chat_plan_mode: bool,
    pub automation_autostart: bool,
    pub automation_run_retention_days: i64,
    pub automation_audit_retention_days: i64,
    pub automation_trash_retention_days: i64,

    pub editor_theme: String,
    pub editor_tab_size: i64,
    pub editor_autosave_enabled: bool,
    pub editor_autosave_delay_seconds: i64,

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
    pub terminal_show_composer_by_default: bool,
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
    #[serde(skip)]
    pub update_status: String,
    #[serde(skip)]
    pub update_message: Option<String>,
    #[serde(skip)]
    pub update_current_version: Option<String>,
    #[serde(skip)]
    pub update_current_build_number: Option<String>,
    #[serde(skip)]
    pub update_latest_version: Option<String>,
    #[serde(skip)]
    pub update_latest_build_number: Option<String>,
    #[serde(skip)]
    pub update_upgrade_command: Option<String>,
    #[serde(skip)]
    pub update_upgrade_manager: Option<String>,
    #[serde(skip)]
    pub update_restart_required: bool,
    #[serde(skip)]
    pub update_busy: bool,
    #[serde(skip)]
    pub github_star_state: GitHubStarState,
}

impl Default for SettingsState {
    fn default() -> Self {
        Self {
            settings_schema_version: 1,
            workspace_directory: "~/.alera/workspaces".to_string(),
            star_clicked: false,
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
            default_agent_profile_id: None,
            quota_enabled_providers: DEFAULT_QUOTA_PROVIDERS
                .into_iter()
                .map(str::to_string)
                .collect(),
            quota_unpinned_keys: BTreeSet::new(),
            claude_default_enabled: true,
            claude_default_show_in_usage: true,
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
            ai_text_selected_thinking_by_operation: BTreeMap::new(),
            ai_text_discovered_models_by_agent: BTreeMap::new(),
            ai_text_discovered_default_model_by_agent: BTreeMap::new(),
            ai_text_custom_command: String::new(),
            ai_text_instructions_by_operation: BTreeMap::new(),
            ai_text_prompt_settings_by_operation: BTreeMap::new(),
            ai_text_timeout_seconds: 120,
            text_actions: Vec::new(),
            codex_chat_selected_model: None,
            codex_chat_reasoning_effort: "medium".to_owned(),
            codex_chat_speed_mode: "normal".to_owned(),
            codex_chat_permission_mode: "on-request".to_owned(),
            codex_chat_plan_mode: false,
            automation_autostart: false,
            automation_run_retention_days: 30,
            automation_audit_retention_days: 90,
            automation_trash_retention_days: 30,
            editor_theme: "Alera".to_string(),
            editor_tab_size: 4,
            editor_autosave_enabled: false,
            editor_autosave_delay_seconds: 1,
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
            terminal_show_composer_by_default: false,
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
            update_status: "Update Status".to_string(),
            update_message: None,
            update_current_version: Some(env!("CARGO_PKG_VERSION").to_string()),
            update_current_build_number: None,
            update_latest_version: None,
            update_latest_build_number: None,
            update_upgrade_command: None,
            update_upgrade_manager: None,
            update_restart_required: false,
            update_busy: false,
            github_star_state: GitHubStarState::Loading,
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
        if let Some(profile_id) = value.get("defaultAgentProfileId") {
            self.default_agent_profile_id = profile_id
                .as_str()
                .map(str::trim)
                .filter(|profile_id| !profile_id.is_empty())
                .map(str::to_owned);
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
        if let Some(text_actions) = value.get("textActions").and_then(Value::as_object) {
            self.text_actions = text_actions
                .get("actions")
                .and_then(Value::as_array)
                .map(|actions| {
                    actions
                        .iter()
                        .filter_map(|action| serde_json::from_value(action.clone()).ok())
                        .collect()
                })
                .unwrap_or_default();
        }
        if let Some(codex) = value.get("codexChat").and_then(Value::as_object) {
            self.codex_chat_selected_model = codex
                .get("selectedModel")
                .and_then(Value::as_str)
                .map(str::to_owned);
            if let Some(value) = codex.get("reasoningEffort").and_then(Value::as_str) {
                self.codex_chat_reasoning_effort = value.to_owned();
            }
            if let Some(value) = codex.get("speedMode").and_then(Value::as_str) {
                self.codex_chat_speed_mode = value.to_owned();
            }
            if let Some(value) = codex.get("permissionMode").and_then(Value::as_str) {
                self.codex_chat_permission_mode = value.to_owned();
            }
            if let Some(value) = codex.get("planMode").and_then(Value::as_bool) {
                self.codex_chat_plan_mode = value;
            }
        }
        if let Some(automation) = value.get("automation").and_then(Value::as_object) {
            if let Some(value) = automation.get("autostart").and_then(Value::as_bool) {
                self.automation_autostart = value;
            }
            if let Some(value) = automation.get("runRetentionDays").and_then(Value::as_i64) {
                self.automation_run_retention_days = value.clamp(1, 3650);
            }
            if let Some(value) = automation.get("auditRetentionDays").and_then(Value::as_i64) {
                self.automation_audit_retention_days = value.clamp(1, 3650);
            }
            if let Some(value) = automation.get("trashRetentionDays").and_then(Value::as_i64) {
                self.automation_trash_retention_days = value.clamp(1, 3650);
            }
        }
    }

    /// Merge the UI-only settings stored by Flutter's local repository.
    ///
    /// The runtime deliberately stores only the quota fields needed by the
    /// host. Flutter therefore loads this record first and overlays the local
    /// values after `runtimeSettings.get`; GPUI must do the same or provider
    /// pinning and profile selection drift between the two clients.
    pub fn apply_local_flutter_settings(&mut self, value: &Value) {
        if let Some(general) = value.get("general").and_then(Value::as_object) {
            if let Some(directory) = general.get("workspaceDirectory") {
                self.workspace_directory = directory
                    .as_str()
                    .filter(|directory| !directory.trim().is_empty())
                    .unwrap_or("~/.alera/workspaces")
                    .to_string();
            }
            if let Some(clicked) = general.get("starClicked").and_then(Value::as_bool) {
                self.star_clicked = clicked;
            }
            if let Some(enabled) = general
                .get("confirmProjectRemoval")
                .and_then(Value::as_bool)
            {
                self.confirm_project_removal = enabled;
            }
            if let Some(enabled) = general
                .get("confirmWorkspaceRemoval")
                .and_then(Value::as_bool)
            {
                self.confirm_workspace_removal = enabled;
            }
        }

        if let Some(editor) = value.get("editor").and_then(Value::as_object) {
            if let Some(theme) = editor.get("themeName").and_then(Value::as_str) {
                self.editor_theme = theme.to_string();
            }
            if let Some(tab_size) = editor.get("tabSize").and_then(Value::as_i64) {
                self.editor_tab_size = tab_size;
            }
            if let Some(enabled) = editor.get("autosaveEnabled").and_then(Value::as_bool) {
                self.editor_autosave_enabled = enabled;
            }
            if let Some(delay) = editor.get("autosaveDelaySeconds").and_then(Value::as_i64) {
                self.editor_autosave_delay_seconds = delay.clamp(1, 60);
            }
        }

        if let Some(diagnostics) = value.get("diagnostics").and_then(Value::as_object) {
            if let Some(level) = diagnostics.get("logLevel").and_then(Value::as_str) {
                self.diagnostics_log_level = match level {
                    "error" | "Error" => "Error",
                    "warning" | "Warning" => "Warning",
                    "info" | "Info" => "Info",
                    "debug" | "Debug" => "Debug",
                    _ => self.diagnostics_log_level.as_str(),
                }
                .to_string();
            }
            if let Some(enabled) = diagnostics
                .get("crashReportingEnabled")
                .and_then(Value::as_bool)
            {
                self.crash_reporting_enabled = enabled;
            }
        }

        if let Some(keyboard) = value.get("keyboard").and_then(Value::as_object) {
            if let Some(policy) = keyboard.get("terminalPolicy").and_then(Value::as_str) {
                if matches!(policy, "appFirst" | "terminalFirst") {
                    self.keyboard_terminal_policy = policy.to_string();
                }
            }
            if let Some(overrides) = keyboard.get("overrides").and_then(Value::as_object) {
                self.keyboard_overrides = overrides
                    .iter()
                    .filter_map(|(id, chords)| {
                        let chords = chords
                            .as_array()?
                            .iter()
                            .map(Value::as_str)
                            .collect::<Option<Vec<_>>>()?;
                        Some((id.clone(), chords.into_iter().map(str::to_owned).collect()))
                    })
                    .collect();
            }
        }

        if let Some(terminal) = value.get("terminal").and_then(Value::as_object) {
            if let Some(font_family) = terminal.get("fontFamily").and_then(Value::as_str) {
                self.terminal_font_family = font_family.to_string();
            }
            apply_f64(terminal.get("fontSize"), &mut self.terminal_font_size);
            apply_i64(terminal.get("fontWeight"), &mut self.terminal_font_weight);
            apply_f64(terminal.get("lineHeight"), &mut self.terminal_line_height);
            apply_f64(terminal.get("paddingX"), &mut self.terminal_padding_x);
            apply_f64(terminal.get("paddingY"), &mut self.terminal_padding_y);
            if let Some(shape) = terminal.get("cursorShape").and_then(Value::as_str) {
                if matches!(shape, "block" | "bar" | "underline") {
                    self.terminal_cursor_shape = shape.to_string();
                }
            }
            if let Some(blink) = terminal.get("cursorBlink").and_then(Value::as_bool) {
                self.terminal_cursor_blink = blink;
            }
            apply_f64(
                terminal.get("cursorOpacity"),
                &mut self.terminal_cursor_opacity,
            );
            if let Some(theme) = terminal.get("themeName").and_then(Value::as_str) {
                self.terminal_theme_name = theme.to_string();
            }
            apply_f64(
                terminal.get("backgroundOpacity"),
                &mut self.terminal_background_opacity,
            );
            if let Some(word_separators) = terminal.get("wordSeparators") {
                self.terminal_word_separators = word_separators
                    .as_str()
                    .filter(|value| !value.is_empty())
                    .map(str::to_owned);
            }
            if let Some(overrides) = terminal.get("colorOverrides").and_then(Value::as_object) {
                for key in ["foreground", "background", "cursor", "selection"] {
                    match overrides.get(key).and_then(Value::as_str) {
                        Some(value) if is_terminal_color(value) => {
                            self.terminal_color_overrides
                                .insert(key.to_string(), normalize_terminal_color(value));
                        }
                        _ if overrides.contains_key(key) => {
                            self.terminal_color_overrides.remove(key);
                        }
                        _ => {}
                    }
                }
            }
            apply_i64(
                terminal.get("scrollbackLines"),
                &mut self.terminal_scrollback_lines,
            );
            apply_i64(
                terminal.get("tuiScrollSensitivity"),
                &mut self.terminal_tui_scroll_sensitivity,
            );
            if let Some(enabled) = terminal.get("clipboardOnSelect").and_then(Value::as_bool) {
                self.terminal_clipboard_on_select = enabled;
            }
            if let Some(enabled) = terminal.get("allowOsc52Clipboard").and_then(Value::as_bool) {
                self.terminal_allow_osc52_clipboard = enabled;
            }
            if let Some(enabled) = terminal
                .get("showComposerByDefault")
                .and_then(Value::as_bool)
            {
                self.terminal_show_composer_by_default = enabled;
            }
            apply_i64(
                terminal.get("hostEmptyShutdownDelaySeconds"),
                &mut self.host_empty_shutdown_delay_seconds,
            );
            apply_i64(
                terminal.get("hostDetachedSessionShutdownDelaySeconds"),
                &mut self.host_detached_shutdown_delay_seconds,
            );
            apply_i64(
                terminal.get("hostScrollbackBytes"),
                &mut self.terminal_host_scrollback_bytes,
            );
            apply_i64(
                terminal.get("bufferBudgetMegabytes"),
                &mut self.terminal_buffer_budget_megabytes,
            );
            if let Some(enabled) = terminal
                .get("keepRuntimeOpenOnAppQuit")
                .and_then(Value::as_bool)
            {
                self.keep_runtime_open_on_quit = enabled;
            }
            if let Some(login_shell) = terminal.get("loginShell") {
                self.terminal_login_shell =
                    login_shell.as_bool().unwrap_or(cfg!(target_os = "macos"));
            }
        }

        if let Some(agents) = value.get("agents").and_then(Value::as_object) {
            if let Some(profile_id) = agents.get("defaultAgentProfileId") {
                self.default_agent_profile_id = profile_id
                    .as_str()
                    .map(str::trim)
                    .filter(|profile_id| !profile_id.is_empty())
                    .map(str::to_owned);
            }
            if let Some(hooks) = agents.get("agentStatusHooks").and_then(Value::as_object) {
                for (agent, enabled) in hooks {
                    if let Some(enabled) = enabled.as_bool() {
                        self.agent_status_hooks.insert(agent.clone(), enabled);
                    }
                }
            }
            if let Some(enabled) = agents
                .get("agentStatusNotificationsEnabled")
                .and_then(Value::as_bool)
            {
                self.agent_status_notifications_enabled = enabled;
            }
            if let Some(enabled) = agents
                .get("agentStatusFinishedNotificationsEnabled")
                .and_then(Value::as_bool)
            {
                self.agent_status_finished_notifications_enabled = enabled;
            }
            if let Some(enabled) = agents
                .get("keepComputerAwakeWhileAgentsWork")
                .and_then(Value::as_bool)
            {
                self.keep_computer_awake_while_agents_work = enabled;
            }
            if let Some(quotas) = agents
                .get("quotas")
                .and_then(Value::as_object)
                .and_then(|quotas| quotas.get("hosts"))
                .and_then(Value::as_object)
                .and_then(|hosts| hosts.get("local"))
                .and_then(Value::as_object)
            {
                self.apply_runtime_quotas(quotas);
            }
        }
    }

    /// Build the local sections shared with Flutter's settings repository.
    /// Each section is complete so a GPUI edit can be merged without losing
    /// values that are not represented by the runtime settings API.
    pub fn shared_flutter_local_payload(&self) -> Value {
        let color_overrides = serde_json::json!({
            "foreground": self.terminal_color_overrides.get("foreground"),
            "background": self.terminal_color_overrides.get("background"),
            "cursor": self.terminal_color_overrides.get("cursor"),
            "selection": self.terminal_color_overrides.get("selection"),
        });
        serde_json::json!({
            "general": {
                "workspaceDirectory": if self.workspace_directory == "~/.alera/workspaces" {
                    Value::Null
                } else {
                    Value::String(self.workspace_directory.clone())
                },
                "starClicked": self.star_clicked,
                "confirmProjectRemoval": self.confirm_project_removal,
                "confirmWorkspaceRemoval": self.confirm_workspace_removal,
            },
            "editor": {
                "tabSize": self.editor_tab_size,
                "themeName": self.editor_theme,
                "autosaveEnabled": self.editor_autosave_enabled,
                "autosaveDelaySeconds": self.editor_autosave_delay_seconds.clamp(1, 60),
            },
            "terminal": {
                "fontFamily": self.terminal_font_family,
                "fontSize": self.terminal_font_size,
                "fontWeight": self.terminal_font_weight,
                "lineHeight": self.terminal_line_height,
                "paddingX": self.terminal_padding_x,
                "paddingY": self.terminal_padding_y,
                "cursorShape": self.terminal_cursor_shape,
                "cursorBlink": self.terminal_cursor_blink,
                "cursorOpacity": self.terminal_cursor_opacity,
                "themeName": self.terminal_theme_name,
                "backgroundOpacity": self.terminal_background_opacity,
                "wordSeparators": self.terminal_word_separators,
                "colorOverrides": color_overrides,
                "scrollbackLines": self.terminal_scrollback_lines,
                "tuiScrollSensitivity": self.terminal_tui_scroll_sensitivity,
                "clipboardOnSelect": self.terminal_clipboard_on_select,
                "allowOsc52Clipboard": self.terminal_allow_osc52_clipboard,
                "showComposerByDefault": self.terminal_show_composer_by_default,
                "hostEmptyShutdownDelaySeconds": self.host_empty_shutdown_delay_seconds,
                "hostDetachedSessionShutdownDelaySeconds":
                    self.host_detached_shutdown_delay_seconds,
                "hostScrollbackBytes": self.terminal_host_scrollback_bytes,
                "bufferBudgetMegabytes": self.terminal_buffer_budget_megabytes,
                "keepRuntimeOpenOnAppQuit": self.keep_runtime_open_on_quit,
                "loginShell": self.terminal_login_shell,
            },
            "diagnostics": {
                "logLevel": match self.diagnostics_log_level.as_str() {
                    "Error" => "error",
                    "Warning" => "warning",
                    "Debug" => "debug",
                    _ => "info",
                },
                "crashReportingEnabled": self.crash_reporting_enabled,
            },
            "keyboard": {
                "overrides": self.keyboard_overrides,
                "terminalPolicy": self.keyboard_terminal_policy,
            },
            "codexChat": {
                "selectedModel": self.codex_chat_selected_model,
                "reasoningEffort": self.codex_chat_reasoning_effort,
                "speedMode": self.codex_chat_speed_mode,
                "permissionMode": self.codex_chat_permission_mode,
                "planMode": self.codex_chat_plan_mode,
            },
        })
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
            "claudeDefaultShowInUsage": self.claude_default_show_in_usage,
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
            "selectedThinkingByOperation": self.ai_text_selected_thinking_by_operation,
            "discoveredModelsByAgent": self.ai_text_discovered_models_by_agent,
            "discoveredDefaultModelByAgent": self.ai_text_discovered_default_model_by_agent,
            "customCommand": self.ai_text_custom_command,
            "instructionsByOperation": self.ai_text_instructions_by_operation,
            "promptSettingsByOperation": self.ai_text_prompt_settings_by_operation,
            "timeoutSeconds": self.ai_text_timeout_seconds,
        })
    }

    pub fn runtime_text_actions_payload(&self) -> Value {
        serde_json::json!({"actions": self.text_actions})
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
        if let Some(show_in_usage) = quotas
            .get("claudeDefaultShowInUsage")
            .and_then(Value::as_bool)
        {
            self.claude_default_show_in_usage = show_in_usage;
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
        if let Some(by_operation) = ai_text
            .get("selectedThinkingByOperation")
            .and_then(Value::as_object)
        {
            self.ai_text_selected_thinking_by_operation = by_operation
                .iter()
                .filter_map(|(operation, values)| {
                    let values = values
                        .as_object()?
                        .iter()
                        .filter_map(|(model, value)| {
                            value.as_str().map(|value| (model.clone(), value.to_owned()))
                        })
                        .collect::<BTreeMap<_, _>>();
                    (!values.is_empty()).then_some((operation.clone(), values))
                })
                .collect();
        }
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

fn apply_f64(value: Option<&Value>, target: &mut f64) {
    if let Some(value) = value
        .and_then(Value::as_f64)
        .filter(|value| value.is_finite())
    {
        *target = value;
    }
}

fn apply_i64(value: Option<&Value>, target: &mut i64) {
    if let Some(value) = value.and_then(Value::as_i64) {
        *target = value;
    }
}

fn is_terminal_color(value: &str) -> bool {
    let value = value.trim().strip_prefix('#').unwrap_or(value.trim());
    value.len() == 6 && value.chars().all(|character| character.is_ascii_hexdigit())
}

fn normalize_terminal_color(value: &str) -> String {
    format!(
        "#{}",
        value.trim().trim_start_matches('#').to_ascii_lowercase()
    )
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

    #[test]
    fn local_flutter_settings_restore_quota_pins_and_profiles() {
        let mut state = SettingsState {
            quota_unpinned_keys: ["kimi".to_string()].into_iter().collect(),
            selected_claude_profile: "default".to_string(),
            ..SettingsState::default()
        };

        state.apply_local_flutter_settings(&json!({
            "agents": {
                "agentStatusNotificationsEnabled": true,
                "quotas": {
                    "hosts": {
                        "local": {
                            "enabledProviders": ["claude", "codex", "kimi"],
                            "claudeProfiles": [{"alias": "dev", "profile": "leynierdev"}],
                            "selectedClaudeProfile": "leynierdev",
                            "unpinnedQuotaKeys": []
                        }
                    }
                }
            }
        }));

        assert!(state.agent_status_notifications_enabled);
        assert_eq!(state.quota_enabled_providers, ["claude", "codex", "kimi"]);
        assert!(state.quota_unpinned_keys.is_empty());
        assert_eq!(state.selected_claude_profile, "leynierdev");
        assert_eq!(state.claude_profiles[0].profile, "leynierdev");
    }

    #[test]
    fn local_flutter_settings_restore_all_client_sections() {
        let mut state = SettingsState::default();
        state.apply_local_flutter_settings(&json!({
            "general": {
                "workspaceDirectory": "/tmp/alera-workspaces",
                "starClicked": true,
                "confirmProjectRemoval": false,
                "confirmWorkspaceRemoval": false
            },
            "editor": {"themeName": "GitHub Dark", "tabSize": 2},
            "terminal": {
                "fontFamily": "Iosevka",
                "fontSize": 15.0,
                "fontWeight": 500,
                "lineHeight": 1.4,
                "paddingX": 8.0,
                "paddingY": 10.0,
                "cursorShape": "bar",
                "cursorBlink": true,
                "cursorOpacity": 0.8,
                "themeName": "Alera Dark",
                "backgroundOpacity": 0.9,
                "wordSeparators": " /",
                "colorOverrides": {"cursor": "ABCDEF", "foreground": null},
                "scrollbackLines": 2000,
                "tuiScrollSensitivity": 2,
                "clipboardOnSelect": true,
                "allowOsc52Clipboard": true,
                "hostEmptyShutdownDelaySeconds": 45,
                "hostDetachedSessionShutdownDelaySeconds": 7200,
                "hostScrollbackBytes": 2000000,
                "bufferBudgetMegabytes": 128,
                "keepRuntimeOpenOnAppQuit": true,
                "loginShell": false
            },
            "diagnostics": {"logLevel": "debug", "crashReportingEnabled": true},
            "keyboard": {
                "terminalPolicy": "terminalFirst",
                "overrides": {"openSettings": ["Mod+Shift+P"], "newTab": []}
            }
        }));

        assert_eq!(state.workspace_directory, "/tmp/alera-workspaces");
        assert!(state.star_clicked);
        assert!(!state.confirm_project_removal);
        assert_eq!(state.editor_theme, "GitHub Dark");
        assert_eq!(state.editor_tab_size, 2);
        assert_eq!(state.terminal_font_family, "Iosevka");
        assert_eq!(state.terminal_font_size, 15.0);
        assert_eq!(state.terminal_cursor_shape, "bar");
        assert!(state.terminal_cursor_blink);
        assert_eq!(state.terminal_word_separators.as_deref(), Some(" /"));
        assert_eq!(
            state.terminal_color_overrides.get("cursor"),
            Some(&"#abcdef".to_string())
        );
        assert!(!state.terminal_color_overrides.contains_key("foreground"));
        assert_eq!(state.diagnostics_log_level, "Debug");
        assert!(state.crash_reporting_enabled);
        assert_eq!(state.keyboard_terminal_policy, "terminalFirst");
        assert_eq!(
            state.keyboard_overrides.get("openSettings"),
            Some(&vec!["Mod+Shift+P".to_string()])
        );
        assert_eq!(state.keyboard_overrides.get("newTab"), Some(&Vec::new()));
    }

    #[test]
    fn shared_flutter_payload_uses_flutter_field_names() {
        let state = SettingsState {
            editor_theme: "GitHub Dark".to_string(),
            terminal_cursor_shape: "bar".to_string(),
            terminal_cursor_blink: true,
            diagnostics_log_level: "Warning".to_string(),
            keyboard_terminal_policy: "terminalFirst".to_string(),
            ..SettingsState::default()
        };
        let payload = state.shared_flutter_local_payload();
        assert_eq!(
            payload.pointer("/editor/themeName"),
            Some(&json!("GitHub Dark"))
        );
        assert_eq!(payload.pointer("/general/starClicked"), Some(&json!(false)));
        assert_eq!(
            payload.pointer("/terminal/cursorShape"),
            Some(&json!("bar"))
        );
        assert_eq!(payload.pointer("/terminal/cursorBlink"), Some(&json!(true)));
        assert_eq!(
            payload.pointer("/diagnostics/logLevel"),
            Some(&json!("warning"))
        );
        assert_eq!(
            payload.pointer("/keyboard/terminalPolicy"),
            Some(&json!("terminalFirst"))
        );
    }
}
