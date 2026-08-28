use gpui::{Context, Window};
use serde_json::{json, Number, Value};

use super::command_terminal::CommandTerminalRequest;
use super::agent_profile_settings::{
    default_agent_command, managed_command_preview, managed_risk_markers, parse_agent_profiles,
    profile_input_value, profile_number_text, set_profile_input, AgentProfileDropdown,
    AgentProfileRecord,
};
use super::AleraApp;

impl AleraApp {
    pub(super) fn test_agent_profile_command(&mut self, cx: &mut Context<Self>) {
        let command = if self.agent_profile_settings.launch_mode == "managed" {
            managed_command_preview(
                &self.agent_profile_settings.adapter,
                &self.agent_profile_settings.managed_config,
            )
        } else {
            profile_input_value(&self.agent_profile_settings.command_input, cx)
        };
        if command.is_empty() {
            self.agent_profile_settings.error = Some("Command Is Required".into());
            cx.notify();
            return;
        }
        self.open_command_terminal(
            CommandTerminalRequest {
                title: "Test Agent Profile".to_owned(),
                command,
                description: Some(
                    "The Profile Command Runs Here. It Does Not Receive A Dispatched Task."
                        .to_owned(),
                ),
                working_directory: None,
            },
            cx,
        );
    }

    pub(super) fn refresh_agent_profiles(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.agent_profile_settings.loading {
            return;
        }
        self.agent_profile_settings.loading = true;
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.load_error = None;
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge.request("agentProfile.list", json!({})).await;
            let _ = this.update_in(cx, |this, window, cx| {
                this.agent_profile_settings.loading = false;
                match result.and_then(parse_agent_profiles) {
                    Ok(profiles) => {
                        let mut profiles = profiles;
                        profiles.sort_by(|left, right| {
                            left.name
                                .to_ascii_lowercase()
                                .cmp(&right.name.to_ascii_lowercase())
                                .then_with(|| left.id.cmp(&right.id))
                        });
                        let selected = this
                            .agent_profile_settings
                            .selected_id
                            .clone()
                            .filter(|id| profiles.iter().any(|profile| &profile.id == id))
                            .or_else(|| profiles.first().map(|profile| profile.id.clone()));
                        this.agent_profile_settings.profiles = profiles;
                        if this.agent_profile_settings.selected_id != selected {
                            if let Some(id) = selected {
                                this.select_agent_profile(id, window, cx);
                            } else if !this.agent_profile_settings.creating_new {
                                this.new_agent_profile(window, cx);
                                this.agent_profile_settings.creating_new = false;
                            }
                        }
                        this.agent_profile_settings.load_error = None;
                    }
                    Err(error) => {
                        // Flutter's AsyncError replaces the pane with an unavailable state;
                        // do not leave stale profiles visible after a failed refresh.
                        this.agent_profile_settings.profiles.clear();
                        this.agent_profile_settings.selected_id = None;
                        this.agent_profile_settings.creating_new = false;
                        this.agent_profile_settings.load_error = Some(error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn new_agent_profile(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.agent_profile_settings.selected_id = None;
        self.agent_profile_settings.creating_new = true;
        self.agent_profile_settings.adapter = "codex".to_owned();
        self.agent_profile_settings.launch_mode = "managed".to_owned();
        self.agent_profile_settings.managed_config.clear();
        self.agent_profile_settings.dropdown = None;
        self.agent_profile_settings.risk_confirmation_open = false;
        self.agent_profile_settings.original_risk_markers.clear();
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        set_profile_input(&self.agent_profile_settings.name_input, "", window, cx);
        set_profile_input(
            &self.agent_profile_settings.command_input,
            default_agent_command("codex"),
            window,
            cx,
        );
        for input in [
            &self.agent_profile_settings.model_input,
            &self.agent_profile_settings.persona_input,
            &self.agent_profile_settings.max_ai_credits_input,
            &self.agent_profile_settings.max_autopilot_continues_input,
            &self.agent_profile_settings.ccs_profile_input,
            &self.agent_profile_settings.description_input,
            &self.agent_profile_settings.quota_group_input,
        ] {
            set_profile_input(input, "", window, cx);
        }
        self.agent_profile_settings
            .custom_prompt_input
            .update(cx, |input, cx| input.set_value("", window, cx));
        self.auto_discover_agent_profile_options("codex".to_owned(), window, cx);
        cx.notify();
    }

    pub(super) fn select_agent_profile(
        &mut self,
        id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(profile) = self
            .agent_profile_settings
            .profiles
            .iter()
            .find(|profile| profile.id == id)
            .cloned()
        else {
            return;
        };
        self.seed_agent_profile(&profile, window, cx);
    }

    pub(super) fn seed_agent_profile(
        &mut self,
        profile: &AgentProfileRecord,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.agent_profile_settings.selected_id = Some(profile.id.clone());
        self.agent_profile_settings.creating_new = false;
        self.agent_profile_settings.adapter = profile.agent_type.clone();
        self.agent_profile_settings.launch_mode = profile.launch_mode.clone();
        self.agent_profile_settings.managed_config = profile.managed_config.clone();
        self.agent_profile_settings.dropdown = None;
        self.agent_profile_settings.risk_confirmation_open = false;
        self.agent_profile_settings.original_risk_markers =
            managed_risk_markers(&profile.agent_type, &profile.managed_config);
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        set_profile_input(
            &self.agent_profile_settings.name_input,
            &profile.name,
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.command_input,
            &profile.command,
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.model_input,
            profile
                .managed_config
                .get("model")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.persona_input,
            profile
                .managed_config
                .get("agent")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.max_ai_credits_input,
            profile_number_text(profile.managed_config.get("maxAiCredits")),
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.max_autopilot_continues_input,
            profile_number_text(profile.managed_config.get("maxAutopilotContinues")),
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.ccs_profile_input,
            profile
                .managed_config
                .get("ccsProfile")
                .and_then(Value::as_str)
                .unwrap_or_default(),
            window,
            cx,
        );
        set_profile_input(
            &self.agent_profile_settings.description_input,
            &profile.description,
            window,
            cx,
        );
        self.agent_profile_settings
            .custom_prompt_input
            .update(cx, |input, cx| input.set_value(&profile.custom_prompt, window, cx));
        set_profile_input(
            &self.agent_profile_settings.quota_group_input,
            profile.quota_group.as_deref().unwrap_or_default(),
            window,
            cx,
        );
        if profile.launch_mode == "managed" {
            self.auto_discover_agent_profile_options(profile.agent_type.clone(), window, cx);
        }
        cx.notify();
    }

    pub(super) fn toggle_agent_profile_dropdown(
        &mut self,
        dropdown: AgentProfileDropdown,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let opening = self.agent_profile_settings.dropdown != Some(dropdown);
        self.agent_profile_settings.dropdown = opening.then_some(dropdown);
        if opening {
            self.agent_profile_settings
                .dropdown_filter_input
                .update(cx, |input, cx| input.set_value("", window, cx));
            self.agent_profile_settings.dropdown_highlighted_index = self
                .agent_profile_dropdown_options(dropdown)
                .iter()
                .position(|(value, _)| {
                    value == self.agent_profile_dropdown_selected_value(dropdown)
                })
                .unwrap_or(0);
            if self.agent_profile_dropdown_is_filterable(dropdown) {
                self.agent_profile_settings
                    .dropdown_filter_input
                    .update(cx, |input, cx| input.focus(window, cx));
            } else {
                self.agent_profile_settings.dropdown_focus.focus(window, cx);
            }
        }
        self.agent_profile_settings.error = None;
        cx.notify();
    }

    pub(super) fn select_agent_profile_dropdown_value(
        &mut self,
        dropdown: AgentProfileDropdown,
        value: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match dropdown {
            AgentProfileDropdown::Adapter => {
                let previous_default =
                    default_agent_command(&self.agent_profile_settings.adapter).to_owned();
                let current_command =
                    profile_input_value(&self.agent_profile_settings.command_input, cx);
                self.agent_profile_settings.adapter = value.clone();
                self.agent_profile_settings.managed_config.clear();
                for input in [
                    &self.agent_profile_settings.model_input,
                    &self.agent_profile_settings.persona_input,
                    &self.agent_profile_settings.max_ai_credits_input,
                    &self.agent_profile_settings.max_autopilot_continues_input,
                    &self.agent_profile_settings.ccs_profile_input,
                ] {
                    set_profile_input(input, "", window, cx);
                }
                if current_command.is_empty() || current_command == previous_default {
                    set_profile_input(
                        &self.agent_profile_settings.command_input,
                        default_agent_command(&value),
                        window,
                        cx,
                    );
                }
                if self.agent_profile_settings.launch_mode == "managed" {
                    self.auto_discover_agent_profile_options(value, window, cx);
                }
            }
            AgentProfileDropdown::LaunchMode => {
                self.agent_profile_settings.launch_mode = value;
            }
            AgentProfileDropdown::Managed(key) => {
                if value.is_empty() {
                    self.agent_profile_settings.managed_config.remove(key);
                } else {
                    self.agent_profile_settings
                        .managed_config
                        .insert(key.to_owned(), Value::String(value));
                }
            }
        }
        self.agent_profile_settings.dropdown = None;
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        cx.notify();
    }

    pub(super) fn apply_agent_profile_managed_input(
        &mut self,
        key: &'static str,
        value: String,
        cx: &mut Context<Self>,
    ) {
        let trimmed = value.trim();
        if matches!(key, "description" | "quotaGroup") {
            self.agent_profile_settings.error = None;
            self.agent_profile_settings.toast = None;
            cx.notify();
            return;
        }
        if trimmed.is_empty() {
            self.agent_profile_settings.managed_config.remove(key);
        } else if matches!(key, "maxAiCredits" | "maxAutopilotContinues") {
            match trimmed.parse::<f64>().ok().and_then(Number::from_f64) {
                Some(number) => {
                    self.agent_profile_settings
                        .managed_config
                        .insert(key.to_owned(), Value::Number(number));
                }
                None => {
                    self.agent_profile_settings.error = Some("Enter A Valid Number".into());
                    cx.notify();
                    return;
                }
            }
        } else {
            self.agent_profile_settings
                .managed_config
                .insert(key.to_owned(), Value::String(trimmed.to_owned()));
        }
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        cx.notify();
    }

    pub(super) fn toggle_agent_profile_flag(&mut self, key: &'static str, cx: &mut Context<Self>) {
        let enabled = self
            .agent_profile_settings
            .managed_config
            .get(key)
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if enabled {
            self.agent_profile_settings.managed_config.remove(key);
        } else {
            self.agent_profile_settings
                .managed_config
                .insert(key.to_owned(), Value::Bool(true));
            if key == "bypassApprovalsAndSandbox" {
                self.agent_profile_settings.managed_config.remove("sandbox");
                self.agent_profile_settings
                    .managed_config
                    .remove("approvalPolicy");
            }
        }
        self.agent_profile_settings.error = None;
        self.agent_profile_settings.toast = None;
        cx.notify();
    }
}
