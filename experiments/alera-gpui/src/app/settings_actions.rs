#![allow(clippy::items_after_test_module)]

use gpui::{Context, SharedString, Window};
use gpui_component::select::SearchableVec;
use serde_json::{json, Value};

use super::command_terminal::CommandTerminalRequest;
use super::settings_select_option::SettingsSelectOption;
use super::settings_state::{AiTextPromptSettings, GitHubStarState, SettingsState};
use super::AleraApp;

impl AleraApp {
    pub(super) fn apply_settings_input(
        &mut self,
        key: &str,
        value: String,
        commit: bool,
        cx: &mut Context<Self>,
    ) {
        match key {
            "terminal-word-separators" => {
                self.update_terminal_settings(
                    |settings| {
                        settings.terminal_word_separators = (!value.is_empty()).then_some(value);
                    },
                    cx,
                );
            }
            "ai-custom-command" => {
                self.update_ai_text_settings(
                    |settings| settings.ai_text_custom_command = value,
                    cx,
                );
            }
            key if key.starts_with("ai-instructions-") => {
                let operation = key.trim_start_matches("ai-instructions-").to_string();
                self.update_ai_text_settings(
                    |settings| {
                        if value.trim().is_empty() {
                            settings
                                .ai_text_instructions_by_operation
                                .remove(&operation);
                        } else {
                            settings
                                .ai_text_instructions_by_operation
                                .insert(operation, value);
                        }
                    },
                    cx,
                );
            }
            _ if !commit => {}
            "host-empty-seconds" => {
                if let Some(value) = parse_i64(&value, 5, 3600) {
                    self.update_terminal_settings(
                        |settings| settings.host_empty_shutdown_delay_seconds = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Empty Host Shutdown", cx);
                }
            }
            "host-detached-seconds" => {
                if let Some(value) = parse_i64(&value, 5, 86_400) {
                    self.update_terminal_settings(
                        |settings| settings.host_detached_shutdown_delay_seconds = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Detached Session Shutdown", cx);
                }
            }
            "editor-tab-size" => {
                if let Some(value) = parse_i64(&value, 1, 8) {
                    self.update_editor_settings(|settings| settings.editor_tab_size = value, cx);
                } else {
                    self.invalid_settings_value("Tab Size", cx);
                }
            }
            "terminal-font-size" => {
                self.update_terminal_f64(
                    &value,
                    8.0,
                    32.0,
                    "Font Size",
                    |settings, value| settings.terminal_font_size = value,
                    cx,
                );
            }
            "terminal-font-weight" => {
                if let Some(value) = parse_i64(&value, 100, 900) {
                    self.update_terminal_settings(
                        |settings| settings.terminal_font_weight = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Font Weight", cx);
                }
            }
            "terminal-line-height" => {
                self.update_terminal_f64(
                    &value,
                    0.8,
                    2.4,
                    "Line Height",
                    |settings, value| settings.terminal_line_height = value,
                    cx,
                );
            }
            "terminal-cursor-opacity" => {
                self.update_terminal_f64(
                    &value,
                    0.0,
                    1.0,
                    "Cursor Opacity",
                    |settings, value| settings.terminal_cursor_opacity = value,
                    cx,
                );
            }
            "terminal-background-opacity" => {
                self.update_terminal_f64(
                    &value,
                    0.0,
                    1.0,
                    "Background Opacity",
                    |settings, value| settings.terminal_background_opacity = value,
                    cx,
                );
            }
            "terminal-padding-x" => {
                self.update_terminal_f64(
                    &value,
                    0.0,
                    64.0,
                    "Horizontal Padding",
                    |settings, value| settings.terminal_padding_x = value,
                    cx,
                );
            }
            "terminal-padding-y" => {
                self.update_terminal_f64(
                    &value,
                    0.0,
                    64.0,
                    "Vertical Padding",
                    |settings, value| settings.terminal_padding_y = value,
                    cx,
                );
            }
            "terminal-tui-scroll" => {
                if let Some(value) = parse_i64(&value, 1, 10) {
                    self.update_terminal_settings(
                        |settings| settings.terminal_tui_scroll_sensitivity = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("TUI Scroll Speed", cx);
                }
            }
            "terminal-scrollback-lines" => {
                if let Some(value) = parse_i64(&value, 100, 200_000) {
                    self.update_terminal_settings(
                        |settings| settings.terminal_scrollback_lines = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Scrollback Lines", cx);
                }
            }
            "terminal-host-scrollback-mb" => {
                if let Some(value) = parse_i64(&value, 1, 256) {
                    self.update_terminal_settings(
                        |settings| settings.terminal_host_scrollback_bytes = value * 1_000_000,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Host Scrollback Size", cx);
                }
            }
            "terminal-buffer-budget-mb" => {
                if let Some(value) = parse_i64(&value, 0, 4096) {
                    self.update_terminal_settings(
                        |settings| settings.terminal_buffer_budget_megabytes = value,
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Terminal Memory Budget", cx);
                }
            }
            key if key.starts_with("terminal-color-") => {
                let color_key = key.trim_start_matches("terminal-color-").to_string();
                if value.trim().is_empty() {
                    self.update_terminal_settings(
                        |settings| {
                            settings.terminal_color_overrides.remove(&color_key);
                        },
                        cx,
                    );
                } else if normalize_hex_color(&value).is_some() {
                    let value = normalize_hex_color(&value).unwrap_or_default();
                    self.update_terminal_settings(
                        |settings| {
                            settings.terminal_color_overrides.insert(color_key, value);
                        },
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Terminal Color", cx);
                }
            }
            key if key.starts_with("quota-env-") => {
                let environment_key = key.trim_start_matches("quota-env-").to_string();
                let value = value.trim().to_string();
                if valid_environment_name(&value) {
                    self.update_quota_settings(
                        |settings| {
                            settings.quota_environment.insert(environment_key, value);
                        },
                        cx,
                    );
                } else {
                    self.invalid_settings_value("Credential Environment", cx);
                }
            }
            _ => {}
        }
    }

    pub(super) fn apply_settings_select(
        &mut self,
        key: &str,
        value: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match key {
            key if key.starts_with("skill-runner-") => {
                let skill = key.trim_start_matches("skill-runner-").to_string();
                self.skill_runners.insert(skill, value);
                self.settings_state.toast = None;
                cx.notify();
            }
            "diagnostics-log-level" => {
                self.settings_state.diagnostics_log_level = match value.as_str() {
                    "Errors Only" => "Error",
                    "Warnings" => "Warning",
                    "Normal" => "Info",
                    "Verbose" => "Debug",
                    _ => return,
                }
                .to_string();
                crate::app_log::set_level(&self.settings_state.diagnostics_log_level);
                self.persist_settings();
                self.persist_shared_flutter_settings(
                    self.settings_state.shared_flutter_local_payload(),
                    cx,
                );
                cx.notify();
            }
            "ai-agent" => {
                let Some(agent) = super::ai_text_settings_catalog::agent_key(&value) else {
                    return;
                };
                let agent = agent.to_string();
                self.update_ai_text_settings(
                    |settings| {
                        settings.ai_text_agent = agent;
                        settings
                            .ai_text_prompt_settings_by_operation
                            .retain(|_, prompt| prompt.agent.is_some());
                    },
                    cx,
                );
                self.sync_ai_text_selects(window, cx);
                self.auto_discover_configured_ai_models(window, cx);
            }
            "ai-model" => {
                let agent = self.settings_state.ai_text_agent.clone();
                let model =
                    super::ai_text_settings_catalog::model_choices(&self.settings_state, &agent)
                        .into_iter()
                        .find(|model| model.label == value)
                        .map(|model| model.id)
                        .unwrap_or(value);
                self.update_ai_text_settings(
                    |settings| {
                        settings
                            .ai_text_selected_model_by_agent
                            .insert(agent, model);
                    },
                    cx,
                );
                self.sync_ai_text_selects(window, cx);
                self.auto_discover_configured_ai_models(window, cx);
            }
            "ai-thinking" => {
                let agent = self.settings_state.ai_text_agent.clone();
                let model = self
                    .settings_state
                    .ai_text_selected_model_by_agent
                    .get(&agent)
                    .cloned()
                    .unwrap_or_else(|| {
                        super::ai_text_settings_catalog::selected_model_id(
                            &self.settings_state,
                            &agent,
                        )
                    });
                let Some(thinking) =
                    super::ai_text_settings_catalog::model_choices(&self.settings_state, &agent)
                        .into_iter()
                        .find(|candidate| candidate.id == model)
                        .and_then(|model| {
                            model
                                .thinking_levels
                                .iter()
                                .find(|(_, label)| *label == value)
                                .map(|(id, _)| id.clone())
                        })
                else {
                    return;
                };
                self.update_ai_text_settings(
                    |settings| {
                        settings
                            .ai_text_selected_thinking_by_model
                            .insert(model, thinking);
                    },
                    cx,
                );
            }
            key if key.starts_with("ai-prompt-") && key.ends_with("-agent") => {
                let operation = key
                    .trim_start_matches("ai-prompt-")
                    .trim_end_matches("-agent")
                    .to_string();
                let previous = self
                    .settings_state
                    .ai_text_prompt_settings_by_operation
                    .get(&operation)
                    .cloned()
                    .unwrap_or_default();
                let previous_agent = previous
                    .agent
                    .as_deref()
                    .unwrap_or(&self.settings_state.ai_text_agent);
                let next_agent = if value.starts_with("Global (") {
                    None
                } else {
                    super::ai_text_settings_catalog::agent_key(&value).map(str::to_string)
                };
                let effective_next_agent = next_agent
                    .as_deref()
                    .unwrap_or(&self.settings_state.ai_text_agent);
                let model = (previous_agent == effective_next_agent)
                    .then_some(previous.model)
                    .flatten();
                self.update_ai_text_settings(
                    |settings| {
                        update_prompt_settings(
                            settings,
                            operation,
                            AiTextPromptSettings {
                                agent: next_agent,
                                model,
                            },
                        );
                    },
                    cx,
                );
                self.sync_ai_text_selects(window, cx);
            }
            key if key.starts_with("ai-prompt-") && key.ends_with("-model") => {
                let operation = key
                    .trim_start_matches("ai-prompt-")
                    .trim_end_matches("-model")
                    .to_string();
                let previous = self
                    .settings_state
                    .ai_text_prompt_settings_by_operation
                    .get(&operation)
                    .cloned()
                    .unwrap_or_default();
                let effective_agent = previous
                    .agent
                    .as_deref()
                    .unwrap_or(&self.settings_state.ai_text_agent);
                let model = if value.starts_with("Global (") {
                    None
                } else {
                    super::ai_text_settings_catalog::model_choices(
                        &self.settings_state,
                        effective_agent,
                    )
                    .into_iter()
                    .find(|model| model.label == value)
                    .map(|model| model.id)
                    .or(Some(value))
                };
                self.update_ai_text_settings(
                    |settings| {
                        update_prompt_settings(
                            settings,
                            operation,
                            AiTextPromptSettings {
                                agent: previous.agent,
                                model,
                            },
                        );
                    },
                    cx,
                );
                self.sync_ai_text_selects(window, cx);
            }
            key if key.starts_with("ai-prompt-") && key.ends_with("-thinking") => {
                let operation = key
                    .trim_start_matches("ai-prompt-")
                    .trim_end_matches("-thinking")
                    .to_string();
                let prompt = self
                    .settings_state
                    .ai_text_prompt_settings_by_operation
                    .get(&operation);
                let agent = prompt
                    .and_then(|prompt| prompt.agent.as_deref())
                    .unwrap_or(&self.settings_state.ai_text_agent);
                let model = prompt
                    .and_then(|prompt| prompt.model.as_deref())
                    .map(str::to_owned)
                    .unwrap_or_else(|| {
                        super::ai_text_settings_catalog::selected_model_id(
                            &self.settings_state,
                            agent,
                        )
                    });
                let Some(thinking) = super::ai_text_settings_catalog::model_choices(
                    &self.settings_state,
                    agent,
                )
                .into_iter()
                .find(|candidate| candidate.id == model)
                .and_then(|candidate| {
                    candidate
                        .thinking_levels
                        .into_iter()
                        .find(|(_, label)| *label == value)
                        .map(|(id, _)| id)
                }) else {
                    return;
                };
                self.update_ai_text_settings(
                    |settings| {
                        settings
                            .ai_text_selected_thinking_by_operation
                            .entry(operation)
                            .or_default()
                            .insert(model, thinking);
                    },
                    cx,
                );
            }
            "terminal-font" => {
                self.update_terminal_settings(|settings| settings.terminal_font_family = value, cx);
            }
            _ => {}
        }
    }
}
fn parse_i64(value: &str, min: i64, max: i64) -> Option<i64> {
    value
        .trim()
        .parse::<i64>()
        .ok()
        .filter(|value| (min..=max).contains(value))
}

fn parse_f64(value: &str, min: f64, max: f64) -> Option<f64> {
    value
        .trim()
        .parse::<f64>()
        .ok()
        .filter(|value| value.is_finite() && *value >= min && *value <= max)
}

fn normalize_hex_color(value: &str) -> Option<String> {
    let value = value.trim();
    let digits = value.strip_prefix('#').unwrap_or(value);
    (digits.len() == 6
        && digits
            .chars()
            .all(|character| character.is_ascii_hexdigit()))
    .then(|| format!("#{}", digits.to_ascii_lowercase()))
}

fn valid_environment_name(value: &str) -> bool {
    let mut characters = value.chars();
    characters
        .next()
        .is_some_and(|character| character == '_' || character.is_ascii_alphabetic())
        && characters.all(|character| character == '_' || character.is_ascii_alphanumeric())
}

fn update_prompt_settings(
    settings: &mut SettingsState,
    operation: String,
    prompt: AiTextPromptSettings,
) {
    if prompt.agent.is_none() && prompt.model.is_none() {
        settings
            .ai_text_prompt_settings_by_operation
            .remove(&operation);
    } else {
        settings
            .ai_text_prompt_settings_by_operation
            .insert(operation, prompt);
    }
}

include!("settings_actions/state_actions.rs");
include!("settings_actions/runtime_tools.rs");
include!("settings_actions/diagnostics_actions.rs");
include!("settings_actions/ai_select_sync.rs");
include!("settings_actions/ai_model_discovery.rs");
include!("settings_actions/update_actions.rs");
