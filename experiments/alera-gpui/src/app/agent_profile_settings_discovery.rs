use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, px, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, ParentElement as _, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::tooltip::Tooltip;
use serde_json::{json, Value};

use super::agent_profile_settings::AgentProfileDropdown;
use super::agent_profile_settings_controls::settings_row;
use super::ai_assist_settings_catalog::model_choices;
use super::AleraApp;
use crate::icons::{icon, AleraIcon};
use crate::theme;

struct DiscoverableChoice {
    title: &'static str,
    description: &'static str,
    key: &'static str,
    refresh_tooltip: &'static str,
    choices: Vec<(String, String)>,
    can_refresh: bool,
    busy: bool,
    refresh_id: &'static str,
}

impl AleraApp {
    pub(super) fn auto_discover_agent_profile_options(
        &mut self,
        adapter: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if super::settings_actions::supports_ai_model_discovery(&adapter)
            && self.ai_model_auto_discovered.insert(adapter.clone())
        {
            self.discover_ai_assist_models(adapter.clone(), window, cx);
        }
        if supports_persona_discovery(&adapter)
            && self
                .agent_profile_settings
                .persona_auto_discovered
                .insert(adapter.clone())
        {
            self.discover_agent_profile_personas(adapter, window, cx);
        }
    }

    pub(super) fn discover_agent_profile_personas(
        &mut self,
        adapter: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !supports_persona_discovery(&adapter)
            || !self
                .agent_profile_settings
                .persona_discovery_busy
                .insert(adapter.clone())
        {
            return;
        }
        self.agent_profile_settings
            .persona_discovery_errors
            .remove(&adapter);
        let bridge = self.bridge.clone();
        cx.notify();
        cx.spawn_in(window, async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "agentProfile.personas.discover",
                    json!({"adapter": adapter}),
                    Duration::from_secs(35),
                )
                .await;
            let _ = this.update_in(cx, |this, _, cx| {
                this.agent_profile_settings
                    .persona_discovery_busy
                    .remove(&adapter);
                match result {
                    Ok(value) if value.get("success").and_then(Value::as_bool) == Some(true) => {
                        let personas = value
                            .get("personas")
                            .and_then(Value::as_array)
                            .into_iter()
                            .flatten()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect();
                        this.agent_profile_settings
                            .discovered_personas
                            .insert(adapter.clone(), personas);
                    }
                    Ok(value) => {
                        let error = value
                            .get("error")
                            .and_then(Value::as_str)
                            .unwrap_or("Persona Discovery Failed.")
                            .to_owned();
                        this.agent_profile_settings
                            .persona_discovery_errors
                            .insert(adapter.clone(), error.into());
                    }
                    Err(error) => {
                        this.agent_profile_settings
                            .persona_discovery_errors
                            .insert(adapter.clone(), error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_agent_profile_model_choice(&self, cx: &mut Context<Self>) -> gpui::Div {
        let adapter = self.agent_profile_settings.adapter.clone();
        let choices = model_choices(&self.settings_state, &adapter)
            .into_iter()
            .map(|model| (model.id, model.label))
            .collect();
        let busy = self.ai_model_discovery_busy.contains(&adapter);
        self.render_discoverable_profile_choice(
            DiscoverableChoice {
                title: "Model",
                description: "Leave As Default To Use The Agent Configuration.",
                key: "model",
                refresh_tooltip: "Refresh Models",
                choices,
                can_refresh: super::settings_actions::supports_ai_model_discovery(&adapter),
                busy,
                refresh_id: "refresh-agent-profile-models",
            },
            move |this, window, cx| {
                this.discover_ai_assist_models(adapter.clone(), window, cx);
            },
            cx,
        )
    }

    pub(super) fn render_agent_profile_persona_choice(&self, cx: &mut Context<Self>) -> gpui::Div {
        let adapter = self.agent_profile_settings.adapter.clone();
        let personas = self
            .agent_profile_settings
            .discovered_personas
            .get(&adapter)
            .cloned()
            .unwrap_or_else(|| {
                if adapter == "opencode" || adapter == "opencode2" {
                    vec!["build".to_owned()]
                } else {
                    Vec::new()
                }
            })
            .into_iter()
            .map(|persona| {
                let label = title_from_id(&persona);
                (persona, label)
            })
            .collect();
        let busy = self
            .agent_profile_settings
            .persona_discovery_busy
            .contains(&adapter);
        self.render_discoverable_profile_choice(
            DiscoverableChoice {
                title: "Persona",
                description: "Select A Known Agent Persona Or Enter An Exact Name.",
                key: "agent",
                refresh_tooltip: "Refresh Personas",
                choices: personas,
                can_refresh: supports_persona_discovery(&adapter),
                busy,
                refresh_id: "refresh-agent-profile-personas",
            },
            move |this, window, cx| {
                this.discover_agent_profile_personas(adapter.clone(), window, cx);
            },
            cx,
        )
    }

    fn render_discoverable_profile_choice(
        &self,
        choice: DiscoverableChoice,
        on_refresh: impl Fn(&mut AleraApp, &mut Window, &mut Context<AleraApp>) + 'static,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let selected = self
            .agent_profile_settings
            .managed_config
            .get(choice.key)
            .and_then(Value::as_str)
            .unwrap_or_default();
        let label = choice
            .choices
            .iter()
            .find(|(id, _)| id == selected)
            .map(|(_, label)| label.clone())
            .unwrap_or_else(|| {
                if selected.is_empty() {
                    "Agent Default".to_owned()
                } else {
                    format!("Custom: {selected}")
                }
            });
        let mut options = vec![(String::new(), "Agent Default".to_owned())];
        options.extend(choice.choices);
        if !selected.is_empty() && !options.iter().any(|(value, _)| value == selected) {
            options.push((selected.to_owned(), format!("Custom: {selected}")));
        }
        settings_row(
            choice.title,
            choice.description,
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(div().flex_1().child(self.render_agent_profile_dropdown(
                    "",
                    AgentProfileDropdown::Managed(choice.key),
                    label,
                    options,
                    cx,
                )))
                .when(choice.can_refresh, |row| {
                    row.child(
                        div()
                            .id(choice.refresh_id)
                            .focusable()
                            .tab_stop(!self.agent_profile_settings.saving && !choice.busy)
                            .role(Role::Button)
                            .aria_label(choice.refresh_tooltip)
                            .tooltip(move |_, cx| {
                                cx.new(|_| Tooltip::new(choice.refresh_tooltip)).into()
                            })
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(30.0))
                            .h(px(30.0))
                            .rounded_md()
                            .when(
                                !self.agent_profile_settings.saving && !choice.busy,
                                |button| {
                                    button
                                        .cursor(CursorStyle::PointingHand)
                                        .hover(|style| style.bg(theme::surface_raised()))
                                        .on_click(cx.listener(move |this, _, window, cx| {
                                            on_refresh(this, window, cx);
                                        }))
                                },
                            )
                            .when(
                                self.agent_profile_settings.saving || choice.busy,
                                |button| button.opacity(0.5),
                            )
                            .child(icon(
                                if choice.busy {
                                    AleraIcon::Loading
                                } else {
                                    AleraIcon::Refresh
                                },
                                15.0,
                                theme::text_muted(),
                            )),
                    )
                }),
        )
    }

    pub(super) fn agent_profile_discovery_error(&self) -> Option<SharedString> {
        let adapter = &self.agent_profile_settings.adapter;
        self.agent_profile_settings
            .persona_discovery_errors
            .get(adapter)
            .cloned()
            .or_else(|| self.ai_model_discovery_errors.get(adapter).cloned())
    }
}

fn supports_persona_discovery(adapter: &str) -> bool {
    matches!(adapter, "agy" | "opencode" | "opencode2")
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
