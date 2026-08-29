use gpui::{Context, KeyDownEvent, Window};

use super::agent_profile_settings::AgentProfileDropdown;
use super::agent_profile_settings_catalog::{controls_for, ManagedControl, ADAPTERS, LAUNCH_MODES};
use super::ai_text_settings_catalog::model_choices;
use super::AleraApp;

impl AleraApp {
    pub(super) fn handle_agent_profile_dropdown_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(dropdown) = self.agent_profile_settings.dropdown else {
            return;
        };
        let options = self.agent_profile_dropdown_filtered_options(dropdown, cx);
        match event.keystroke.key.as_str() {
            "escape" => {
                self.agent_profile_settings.dropdown = None;
            }
            "down" | "arrowdown" => {
                if !options.is_empty() {
                    self.agent_profile_settings.dropdown_highlighted_index =
                        (self.agent_profile_settings.dropdown_highlighted_index + 1)
                            .min(options.len() - 1);
                }
            }
            "up" | "arrowup" => {
                self.agent_profile_settings.dropdown_highlighted_index = self
                    .agent_profile_settings
                    .dropdown_highlighted_index
                    .saturating_sub(1);
            }
            "enter" | "return" => {
                if let Some((value, _)) =
                    options.get(self.agent_profile_settings.dropdown_highlighted_index)
                {
                    self.select_agent_profile_dropdown_value(dropdown, value.clone(), window, cx);
                }
            }
            _ => return,
        }
        cx.stop_propagation();
        cx.notify();
    }

    pub(super) fn confirm_agent_profile_dropdown_filter(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(dropdown) = self.agent_profile_settings.dropdown else {
            return;
        };
        let options = self.agent_profile_dropdown_filtered_options(dropdown, cx);
        if let Some((value, _)) =
            options.get(self.agent_profile_settings.dropdown_highlighted_index)
        {
            self.select_agent_profile_dropdown_value(dropdown, value.clone(), window, cx);
        }
    }

    pub(super) fn agent_profile_dropdown_is_filterable(
        &self,
        dropdown: AgentProfileDropdown,
    ) -> bool {
        matches!(dropdown, AgentProfileDropdown::Managed("model" | "agent"))
    }

    pub(super) fn agent_profile_dropdown_filtered_options(
        &self,
        dropdown: AgentProfileDropdown,
        cx: &Context<Self>,
    ) -> Vec<(String, String)> {
        let options = self.agent_profile_dropdown_options(dropdown);
        if !self.agent_profile_dropdown_is_filterable(dropdown) {
            return options;
        }
        let query = self
            .agent_profile_settings
            .dropdown_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        if query.is_empty() {
            return options;
        }
        options
            .into_iter()
            .filter(|(value, label)| {
                value.to_lowercase().contains(&query) || label.to_lowercase().contains(&query)
            })
            .collect()
    }

    pub(super) fn agent_profile_dropdown_options(
        &self,
        dropdown: AgentProfileDropdown,
    ) -> Vec<(String, String)> {
        match dropdown {
            AgentProfileDropdown::Adapter => owned_options(ADAPTERS),
            AgentProfileDropdown::LaunchMode => owned_options(LAUNCH_MODES),
            AgentProfileDropdown::Managed("model") => {
                let mut options = default_option();
                options.extend(
                    model_choices(&self.settings_state, &self.agent_profile_settings.adapter)
                        .into_iter()
                        .map(|model| (model.id, model.label)),
                );
                append_custom_option(
                    options,
                    self.agent_profile_dropdown_selected_value(dropdown),
                )
            }
            AgentProfileDropdown::Managed("agent") => {
                let adapter = &self.agent_profile_settings.adapter;
                let personas = self
                    .agent_profile_settings
                    .discovered_personas
                    .get(adapter)
                    .cloned()
                    .unwrap_or_else(|| {
                        if adapter == "opencode" || adapter == "opencode2" {
                            vec!["build".to_owned()]
                        } else {
                            Vec::new()
                        }
                    });
                let mut options = default_option();
                options.extend(personas.into_iter().map(|persona| {
                    let label = title_from_id(&persona);
                    (persona, label)
                }));
                append_custom_option(
                    options,
                    self.agent_profile_dropdown_selected_value(dropdown),
                )
            }
            AgentProfileDropdown::Managed(key) => {
                let mut options = default_option();
                for control in controls_for(&self.agent_profile_settings.adapter) {
                    if let ManagedControl::Choice {
                        key: candidate,
                        options: choices,
                        ..
                    } = control
                    {
                        if candidate == key {
                            options.extend(
                                choices.iter().map(|choice| {
                                    (choice.value.to_owned(), choice.label.to_owned())
                                }),
                            );
                            break;
                        }
                    }
                }
                append_custom_option(
                    options,
                    self.agent_profile_dropdown_selected_value(dropdown),
                )
            }
        }
    }

    pub(super) fn agent_profile_dropdown_selected_value(
        &self,
        dropdown: AgentProfileDropdown,
    ) -> &str {
        match dropdown {
            AgentProfileDropdown::Adapter => &self.agent_profile_settings.adapter,
            AgentProfileDropdown::LaunchMode => &self.agent_profile_settings.launch_mode,
            AgentProfileDropdown::Managed(key) => self
                .agent_profile_settings
                .managed_config
                .get(key)
                .and_then(serde_json::Value::as_str)
                .unwrap_or_default(),
        }
    }
}

fn owned_options(options: &[(&str, &str)]) -> Vec<(String, String)> {
    options
        .iter()
        .map(|(value, label)| ((*value).to_owned(), (*label).to_owned()))
        .collect()
}

fn default_option() -> Vec<(String, String)> {
    vec![(String::new(), "Agent Default".to_owned())]
}

fn append_custom_option(
    mut options: Vec<(String, String)>,
    selected: &str,
) -> Vec<(String, String)> {
    if !selected.is_empty() && !options.iter().any(|(value, _)| value == selected) {
        options.push((selected.to_owned(), format!("Custom: {selected}")));
    }
    options
}

fn title_from_id(value: &str) -> String {
    value
        .split(['-', '_', '.', ' '])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut characters = part.chars();
            characters.next().map_or_else(String::new, |first| {
                first.to_uppercase().collect::<String>() + characters.as_str()
            })
        })
        .collect::<Vec<_>>()
        .join(" ")
}
