use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, Context, CursorStyle,
    InteractiveElement as _, IntoElement, ParentElement as _, Render, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::Textarea;
use gpui_component::scroll::ScrollableElement as _;
use serde_json::Value;

use super::agent_profile_settings::{
    adapter_icon, adapter_label, managed_command_preview, profile_input_value, AgentProfileDropdown,
};
use super::agent_profile_settings_catalog::{
    controls_for, supports_model, supports_persona, ManagedControl, ADAPTERS, LAUNCH_MODES,
};
use super::agent_profile_settings_controls::{
    launch_mode_label, profile_action_button, settings_checkbox, settings_group, settings_row,
    settings_row_width,
};
use super::settings_panes::settings_master_resize_handle;
use super::AleraApp;
use crate::design_system;
use crate::icons::{agent_icon, icon, loading_indicator, AleraIcon};
use crate::theme;

#[derive(Clone, Debug)]
struct AgentProfileDragData {
    id: String,
    name: String,
}

struct AgentProfileDragPreview {
    name: String,
}

impl Render for AgentProfileDragPreview {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .items_center()
            .gap_2()
            .px_3()
            .py_2()
            .rounded_md()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .text_size(px(13.0))
            .child(icon(AleraIcon::Agent, 15.0, theme::text_muted()))
            .child(self.name.clone())
    }
}

impl AleraApp {
    pub(super) fn render_agent_profiles_settings_pane(&self, cx: &mut Context<Self>) -> AnyElement {
        if self.agent_profile_settings.loading && self.agent_profile_settings.profiles.is_empty() {
            return div()
                .id("agent-profiles-loading")
                .role(Role::ProgressIndicator)
                .aria_label("Loading Agent Profiles")
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .child(loading_indicator(18.0, theme::text_muted()))
                .into_any_element();
        }
        if let Some(error) = self.agent_profile_settings.load_error.clone() {
            return div()
                .id("agent-profiles-error")
                .role(Role::Alert)
                .aria_label(error.clone())
                .flex()
                .flex_1()
                .flex_col()
                .items_center()
                .justify_center()
                .gap_2()
                .child(icon(AleraIcon::Agent, 24.0, theme::text_faint()))
                .child(
                    div()
                        .text_size(px(14.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child("Agent Profiles Unavailable"),
                )
                .child(
                    div()
                        .max_w(px(420.0))
                        .text_center()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .child(error),
                )
                .into_any_element();
        }
        div()
            .relative()
            .flex()
            .flex_1()
            .min_h_0()
            .child(self.render_agent_profiles_master(cx))
            .child(settings_master_resize_handle(
                super::SettingsMasterResizeTarget::AgentProfiles,
                cx,
            ))
            .child(self.render_agent_profile_editor(cx))
            .when(self.agent_profile_settings.risk_confirmation_open, |pane| {
                pane.child(self.render_agent_profile_risk_confirmation(cx))
            })
            .when(
                self.agent_profile_settings.removal_confirmation.is_some(),
                |pane| pane.child(self.render_agent_profile_removal_confirmation(cx)),
            )
            .into_any_element()
    }

    fn render_agent_profiles_master(&self, cx: &mut Context<Self>) -> gpui::Div {
        let state = &self.agent_profile_settings;
        div()
            .flex()
            .flex_col()
            .flex_shrink_0()
            .min_h_0()
            // Flutter's AleraMasterDetail starts at 240 logical pixels and
            // lets the user drag the splitter between 180 and 420 pixels.
            .w(px(self.settings_agent_profiles_master_width))
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(px(34.0))
                    .pl_4()
                    .child(
                        div()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Agent Profiles"),
                    )
                    .child(div().flex_1())
                    .child(
                        div()
                            .id("new-agent-profile")
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("New Agent Profile")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(30.0))
                            .h(px(30.0))
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.new_agent_profile(window, cx);
                            }))
                            .child(icon(AleraIcon::Add, 16.0, theme::text_muted())),
                    ),
            )
            // Flutter keeps the last AsyncData mounted during a refresh
            // (`skipLoadingOnRefresh`), so a live list must not be replaced by
            // a loading banner. The full-pane spinner above covers the first
            // load when there is no snapshot yet.
            .child(if state.profiles.is_empty() {
                div()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .items_center()
                    .justify_center()
                    .text_center()
                    .child(icon(AleraIcon::Agent, 22.0, theme::text_faint()))
                    .child(
                        div()
                            .mt_3()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("No Agent Profiles"),
                    )
                    .child(
                        div()
                            .mt_2()
                            .max_w(px(176.0))
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .child("Declare A Profile To Let A Run Dispatch Work To It."),
                    )
                    .into_any_element()
            } else {
                div()
                    .id("agent-profile-list")
                    .role(Role::List)
                    .aria_label("Agent Profiles")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .mt_2()
                    .rounded_lg()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .children(state.profiles.iter().map(|profile| {
                        let id = profile.id.clone();
                        let set_default_id = profile.id.clone();
                        let clone_id = profile.id.clone();
                        let reorder_target_id = profile.id.clone();
                        let selected = state.selected_id.as_deref() == Some(&profile.id);
                        let is_default = self.settings_state.default_agent_profile_id.as_deref()
                            == Some(profile.id.as_str());
                        let subtitle = if let Some(quota) = &profile.quota_group {
                            format!(
                                "{}  ·  {}  ·  {}",
                                launch_mode_label(&profile.launch_mode),
                                profile.command,
                                quota
                            )
                        } else {
                            format!(
                                "{}  ·  {}",
                                launch_mode_label(&profile.launch_mode),
                                profile.command
                            )
                        };
                        div()
                            .id(SharedString::from(format!(
                                "agent-profile-row-{}",
                                profile.id
                            )))
                            .focusable()
                            .tab_stop(true)
                            .role(Role::ListBoxOption)
                            .aria_label(profile.name.clone())
                            .aria_selected(selected)
                            .flex()
                            .items_center()
                            .gap_2()
                            .p_3()
                            .border_b_1()
                            .border_color(theme::border_subtle())
                            .when(selected, |row| row.bg(theme::accent_subtle()))
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.select_agent_profile(id.clone(), window, cx);
                            }))
                            .on_drag(
                                AgentProfileDragData {
                                    id: profile.id.clone(),
                                    name: profile.name.clone(),
                                },
                                |drag, _, _, cx| {
                                    cx.new(|_| AgentProfileDragPreview {
                                        name: drag.name.clone(),
                                    })
                                },
                            )
                            .on_drop(cx.listener(
                                move |this, drag: &AgentProfileDragData, window, cx| {
                                    this.reorder_agent_profiles(
                                        drag.id.clone(),
                                        reorder_target_id.clone(),
                                        window,
                                        cx,
                                    );
                                },
                            ))
                            .child(agent_icon(
                                adapter_icon(&profile.agent_type),
                                16.0,
                                if selected {
                                    theme::text()
                                } else {
                                    theme::text_muted()
                                },
                            ))
                            .child(
                                div()
                                    .min_w_0()
                                    .flex_1()
                                    .child(
                                        div()
                                            .truncate()
                                            .text_size(px(13.0))
                                            .font_weight(gpui::FontWeight::SEMIBOLD)
                                            .child(profile.name.clone()),
                                    )
                                    .child(
                                        div()
                                            .mt_1()
                                            .truncate()
                                            .text_size(px(11.0))
                                            .text_color(theme::text_muted())
                                            .child(subtitle),
                                    ),
                            )
                            .child(
                                design_system::icon_button(
                                    SharedString::from(format!(
                                        "agent-profile-default-{}",
                                        profile.id
                                    )),
                                    if is_default {
                                        "Default Agent Profile"
                                    } else {
                                        "Set As Default"
                                    },
                                    AleraIcon::Star,
                                    !state.saving && !is_default,
                                    26.0,
                                    None,
                                    None,
                                )
                                .text_color(if is_default {
                                    theme::accent()
                                } else {
                                    theme::text_faint()
                                })
                                .on_click(cx.listener(
                                    move |this, _, _, cx| {
                                        this.set_default_agent_profile(
                                            Some(set_default_id.clone()),
                                            cx,
                                        );
                                        cx.stop_propagation();
                                    },
                                )),
                            )
                            .child(
                                design_system::icon_button(
                                    SharedString::from(format!(
                                        "agent-profile-clone-{}",
                                        profile.id
                                    )),
                                    "Clone Profile",
                                    AleraIcon::Duplicate,
                                    !state.saving,
                                    26.0,
                                    None,
                                    None,
                                )
                                .on_click(cx.listener(
                                    move |this, _, window, cx| {
                                        this.clone_agent_profile(clone_id.clone(), window, cx);
                                        cx.stop_propagation();
                                    },
                                )),
                            )
                    }))
                    .into_any_element()
            })
    }

    fn render_agent_profile_editor(&self, cx: &mut Context<Self>) -> AnyElement {
        let state = &self.agent_profile_settings;
        let mut content = div()
            .flex()
            .flex_col()
            .gap_4()
            .child(self.render_agent_profile_identity_group(cx));
        if state.launch_mode == "managed" {
            content = content.child(self.render_agent_profile_managed_group(cx));
        }
        content = content
            .child(self.render_agent_profile_routing_group())
            .when(state.selected_id.is_some(), |content| {
                content.child(self.render_automation_profile_policy(cx))
            })
            .when_some(state.error.clone(), |content, error| {
                content.child(
                    div()
                        .px_1()
                        .text_size(px(12.0))
                        .text_color(theme::danger())
                        .child(error),
                )
            })
            .when_some(state.toast.clone(), |content, toast| {
                content.child(
                    div()
                        .px_1()
                        .text_size(px(12.0))
                        .text_color(theme::success())
                        .child(toast),
                )
            })
            .child(
                div()
                    .flex()
                    .gap_2()
                    .child(
                        profile_action_button(
                            "save-agent-profile",
                            if state.saving { "Saving" } else { "Save" },
                            if state.saving {
                                AleraIcon::Loading
                            } else {
                                AleraIcon::Save
                            },
                            true,
                            state.saving,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.save_agent_profile(window, cx);
                        })),
                    )
                    .child(
                        profile_action_button(
                            "remove-agent-profile",
                            "Remove",
                            AleraIcon::Delete,
                            false,
                            state.selected_id.is_none() || state.saving,
                        )
                        .on_click(cx.listener(|this, _, window, cx| {
                            this.inspect_agent_profile_removal(window, cx);
                        })),
                    ),
            );
        div()
            .flex_1()
            .min_w_0()
            .min_h_0()
            .overflow_hidden()
            .child(
                div()
                    .id("agent-profile-editor-scroll")
                    .flex()
                    .flex_col()
                    .size_full()
                    .pr_1()
                    .overflow_y_scrollbar()
                    .child(content),
            )
            .into_any_element()
    }

    fn render_agent_profile_identity_group(&self, cx: &mut Context<Self>) -> gpui::Div {
        let state = &self.agent_profile_settings;
        let command_preview = managed_command_preview(&state.adapter, &state.managed_config);
        settings_group(
            "Profile",
            "How This Agent Is Launched For A Dispatched Task.",
            vec![
                div().p_3().child(
                    design_system::text_field(&state.name_input)
                        .disabled(state.saving)
                        .label("Name")
                        .prefix(icon(AleraIcon::Text, 15.0, theme::text_faint())),
                ),
                div().px_3().pb_3().child(
                    self.render_agent_profile_dropdown(
                        "Adapter Type",
                        AgentProfileDropdown::Adapter,
                        adapter_label(&state.adapter),
                        ADAPTERS
                            .iter()
                            .map(|(value, label)| ((*value).to_owned(), (*label).to_owned())),
                        cx,
                    ),
                ),
                div().px_3().pb_3().child(
                    self.render_agent_profile_dropdown(
                        "Launch Mode",
                        AgentProfileDropdown::LaunchMode,
                        launch_mode_label(&state.launch_mode),
                        LAUNCH_MODES
                            .iter()
                            .map(|(value, label)| ((*value).to_owned(), (*label).to_owned())),
                        cx,
                    ),
                ),
                if state.launch_mode == "command" {
                    div()
                        .px_3()
                        .pb_3()
                        .child(
                            design_system::text_field(&state.command_input)
                                .disabled(state.saving)
                                .label("Command")
                                .prefix(icon(
                                    AleraIcon::Terminal,
                                    15.0,
                                    theme::text_faint(),
                                )),
                        )
                        .child(
                            div()
                                .mt_2()
                                .text_size(px(12.0))
                                .text_color(theme::text_muted())
                                .child(
                                    "Command Mode Is For Advanced Or Unsupported CLI Options. Use An Interactive Command That Can Accept A Dispatch And Report Completion.",
                                ),
                        )
                        .child(
                            div()
                                .flex()
                                .justify_end()
                                .mt_2()
                                .child(
                                    design_system::button_with_leading_icon(
                                        "test-agent-profile-command",
                                        "Test Command",
                                        crate::design_system::ButtonKind::Outlined,
                                        state.saving,
                                        icon(AleraIcon::Terminal, 15.0, theme::text_muted()),
                                    )
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.test_agent_profile_command(cx);
                                    })),
                                ),
                        )
                        .child(
                            div()
                                .mt_3()
                                .flex()
                                .items_start()
                                .gap_2()
                                .text_size(px(12.0))
                                .text_color(theme::text_muted())
                                .child(icon(AleraIcon::Info, 15.0, theme::text_faint()))
                                .child(if state.adapter == "codex" {
                                    "Alera Appends The Dispatch Prompt After -- As One Quoted Argument."
                                } else {
                                    "Alera Types The Dispatch Prompt After The Agent Reports Ready."
                                }),
                        )
                        .when(state.adapter == "codex", |field| {
                            let command = profile_input_value(&state.command_input, cx);
                            let preview = if command.trim().is_empty() {
                                String::new()
                            } else {
                                format!("{} -- 'Dispatched Prompt'", command.trim())
                            };
                            field.child(
                                div()
                                    .mt_2()
                                    .p_2()
                                    .rounded_md()
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .bg(theme::surface())
                                    .font_family("JetBrains Mono")
                                    .text_size(px(12.0))
                                    .child(preview),
                            )
                        })
                } else {
                    let has_command_preview = !command_preview.trim().is_empty();
                    settings_row_width(
                        "Command Preview",
                        "The Host Quotes These Arguments For The Actual Platform Shell.",
                        320.0,
                        div()
                            .flex()
                            .flex_col()
                            .items_end()
                            .gap_2()
                            .child(
                                div()
                                    .w(px(320.0))
                                    .text_size(px(12.0))
                                    .text_color(theme::text_muted())
                                    .child(command_preview),
                            )
                            .child(
                                profile_action_button(
                                    "test-agent-profile-managed-command",
                                    "Test Command",
                                    AleraIcon::Terminal,
                                    false,
                                    state.saving || !has_command_preview,
                                )
                                .on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.test_agent_profile_command(cx);
                                    },
                                )),
                            ),
                    )
                },
                div()
                    .p_3()
                    .child(
                        div()
                            .text_size(px(13.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .child("Custom Prompt"),
                    )
                    .child(
                        div()
                            .mt_1()
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .child("Optional instructions for every dispatched task."),
                    )
                    .child(
                        div().mt_2().h(px(104.0)).child(
                            Textarea::new(&state.custom_prompt_input)
                                .disabled(state.saving)
                                .h_full(),
                        ),
                    ),
            ],
        )
    }

    fn render_agent_profile_managed_group(&self, cx: &mut Context<Self>) -> gpui::Div {
        let state = &self.agent_profile_settings;
        let mut rows = Vec::new();
        if state.adapter == "claude" {
            rows.push(settings_row(
                "CCS Profile",
                concat!(
                    "Leave empty to run Claude directly. A profile launches ccs with the ",
                    "profile first and the same flags after it. CCS points CLAUDE_CONFIG_DIR ",
                    "at its instance directory. Alera writes Claude status hooks into that ",
                    "instance settings.local.json."
                ),
                div().w(px(220.0)).child(
                    design_system::text_field(&state.ccs_profile_input).disabled(state.saving),
                ),
            ));
        }
        if supports_model(&state.adapter) {
            rows.push(self.render_agent_profile_model_choice(cx));
            rows.push(settings_row(
                "Exact Model ID",
                "Use A Model ID That Is Not In The Discovered List.",
                div()
                    .w(px(220.0))
                    .child(design_system::text_field(&state.model_input).disabled(state.saving)),
            ));
        }
        if supports_persona(&state.adapter) {
            rows.push(self.render_agent_profile_persona_choice(cx));
            rows.push(settings_row(
                "Exact Persona",
                "Use A Persona Name That Is Not In The Discovered List.",
                div()
                    .w(px(220.0))
                    .child(design_system::text_field(&state.persona_input).disabled(state.saving)),
            ));
        }
        for control in controls_for(&state.adapter) {
            rows.push(match control {
                ManagedControl::Choice {
                    key,
                    title,
                    description,
                    options,
                } => self.render_managed_choice(title, description, key, options, cx),
                ManagedControl::Flag {
                    key,
                    title,
                    description,
                } => {
                    let enabled = state
                        .managed_config
                        .get(key)
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    settings_row(
                        title,
                        description,
                        settings_checkbox(
                            SharedString::from(format!("profile-flag-{key}")),
                            title,
                            enabled,
                            !state.saving,
                        )
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.toggle_agent_profile_flag(key, cx);
                        })),
                    )
                }
                ManagedControl::Number {
                    key,
                    title,
                    description,
                } => {
                    let input = if key == "maxAiCredits" {
                        &state.max_ai_credits_input
                    } else {
                        &state.max_autopilot_continues_input
                    };
                    settings_row(
                        title,
                        description,
                        div()
                            .w(px(220.0))
                            .child(design_system::text_field(input).disabled(state.saving)),
                    )
                }
            });
        }
        if let Some(error) = self.agent_profile_discovery_error() {
            let error_label = error.clone();
            rows.push(
                div()
                    .p_4()
                    .text_size(px(13.0))
                    .text_color(theme::warning())
                    .child(
                        div()
                            .id("agent-profile-discovery-error")
                            .role(Role::Alert)
                            .aria_label(error_label)
                            .child(error),
                    ),
            );
        }
        settings_group(
            "Managed Options",
            "Alera Builds The Interactive Command From These Agent-Specific Settings.",
            rows,
        )
    }

    fn render_agent_profile_routing_group(&self) -> gpui::Div {
        let state = &self.agent_profile_settings;
        settings_group(
            "Routing",
            "Signals The Orchestrator Reads When Planning A Run.",
            vec![
                div().p_3().child(
                    design_system::text_field(&state.description_input)
                        .disabled(state.saving)
                        .label("Description")
                        .prefix(icon(AleraIcon::Info, 15.0, theme::text_faint())),
                ),
                div().px_3().pb_3().child(
                    design_system::text_field(&state.quota_group_input)
                        .disabled(state.saving)
                        .label("Quota Group")
                        .prefix(icon(AleraIcon::Tag, 15.0, theme::text_faint())),
                ),
                div()
                    .px_3()
                    .pb_3()
                    .text_size(px(12.0))
                    .text_color(theme::text_muted())
                    .child(
                        "Profiles Sharing A Quota Group Drain The Same Usage Bucket. Alera Never Measures This; It Only Avoids Falling Back Inside The Same Group. Leave Empty If Unsure.",
                    ),
            ],
        )
    }
}
