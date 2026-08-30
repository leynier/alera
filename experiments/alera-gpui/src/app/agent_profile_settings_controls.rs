use gpui::{
    deferred, div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    ParentElement as _, Role, SharedString, StatefulInteractiveElement as _, Styled as _, Toggled,
};
use serde_json::Value;

use super::agent_profile_settings::AgentProfileDropdown;
use super::agent_profile_settings_catalog::ManagedOption;
use super::AleraApp;
use crate::design_system;
use crate::icons::{icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_managed_choice(
        &self,
        title: &'static str,
        description: &'static str,
        key: &'static str,
        options: &'static [ManagedOption],
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        self.render_managed_owned_choice(
            title,
            description,
            key,
            options
                .iter()
                .map(|option| (option.value.to_owned(), option.label.to_owned()))
                .collect(),
            cx,
        )
    }

    pub(super) fn render_managed_owned_choice(
        &self,
        title: &'static str,
        description: &'static str,
        key: &'static str,
        options: Vec<(String, String)>,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let selected = self
            .agent_profile_settings
            .managed_config
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default();
        let label = options
            .iter()
            .find(|option| option.0 == selected)
            .map(|option| option.1.as_str())
            .unwrap_or_else(|| {
                if selected.is_empty() {
                    "Agent Default"
                } else {
                    selected
                }
            })
            .to_owned();
        let mut menu_options = vec![(String::new(), "Agent Default".to_owned())];
        menu_options.extend(options);
        if !selected.is_empty() && !menu_options.iter().any(|(value, _)| value == selected) {
            menu_options.push((selected.to_owned(), format!("Custom: {selected}")));
        }
        settings_row(
            title,
            description,
            self.render_agent_profile_dropdown(
                "",
                AgentProfileDropdown::Managed(key),
                label,
                menu_options,
                cx,
            ),
        )
    }

    pub(super) fn render_agent_profile_dropdown(
        &self,
        label: &'static str,
        dropdown: AgentProfileDropdown,
        value: impl Into<SharedString>,
        options: impl IntoIterator<Item = (String, String)>,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let enabled = !self.agent_profile_settings.saving;
        let value = value.into();
        let expanded = self.agent_profile_settings.dropdown == Some(dropdown);
        let selected = selected_value(self, dropdown).to_owned();
        let accessibility_label = match dropdown {
            AgentProfileDropdown::Adapter => "Adapter Type",
            AgentProfileDropdown::LaunchMode => "Launch Mode",
            AgentProfileDropdown::Managed("model") => "Model",
            AgentProfileDropdown::Managed("reasoningEffort") => "Reasoning Effort",
            AgentProfileDropdown::Managed("sandbox") => "Sandbox",
            AgentProfileDropdown::Managed("approvalPolicy") => "Approval Policy",
            AgentProfileDropdown::Managed("persona") => "Persona",
            AgentProfileDropdown::Managed(key) => key,
        };
        let options = options.into_iter().collect::<Vec<_>>();
        let filterable = self.agent_profile_dropdown_is_filterable(dropdown);
        let query = self
            .agent_profile_settings
            .dropdown_filter_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let options = if filterable && !query.is_empty() {
            options
                .into_iter()
                .filter(|(option, name)| {
                    option.to_lowercase().contains(&query) || name.to_lowercase().contains(&query)
                })
                .collect::<Vec<_>>()
        } else {
            options
        };
        div()
            .relative()
            .when(!label.is_empty(), |field| {
                field.child(
                    div()
                        .mb_1()
                        .text_size(px(11.0))
                        .text_color(theme::text_muted())
                        .child(label),
                )
            })
            .child(
                div()
                    .id(SharedString::from(format!("profile-dropdown-{dropdown:?}")))
                    .focusable()
                    .tab_stop(enabled)
                    .role(Role::ComboBox)
                    .aria_label(accessibility_label)
                    .aria_expanded(expanded)
                    .when(expanded && enabled, |trigger| {
                        trigger
                            .track_focus(&self.agent_profile_settings.dropdown_focus)
                            .on_key_down(cx.listener(Self::handle_agent_profile_dropdown_key))
                    })
                    .flex()
                    .items_center()
                    .w_full()
                    .h(px(38.0))
                    .px_3()
                    .rounded_md()
                    .border_1()
                    .border_color(if expanded {
                        theme::accent()
                    } else {
                        theme::border()
                    })
                    .bg(theme::surface_selected())
                    .when(enabled, |trigger| {
                        trigger
                            .cursor(CursorStyle::PointingHand)
                            .on_click(
                                cx.listener(move |this, _, window, cx| {
                                    this.toggle_agent_profile_dropdown(dropdown, window, cx);
                                }),
                            )
                    })
                    .child(value)
                    .child(div().flex_1())
                    .child(icon(
                        if expanded {
                            AleraIcon::ChevronUp
                        } else {
                            AleraIcon::ChevronDown
                        },
                        15.0,
                        theme::text_muted(),
                    )),
            )
            .when(expanded && enabled, |field| {
                field.child(
                    deferred(
                        div()
                            .absolute()
                            .top(px(if label.is_empty() { 40.0 } else { 58.0 }))
                            .left_0()
                            .right_0()
                            .occlude()
                            .rounded_md()
                            .border_1()
                            .border_color(theme::border())
                            .bg(theme::surface())
                            .shadow_md()
                            .p_1()
                            .on_key_down(cx.listener(Self::handle_agent_profile_dropdown_key))
                            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                                this.agent_profile_settings.dropdown = None;
                                cx.notify();
                            }))
                            .when(filterable, |menu| {
                                menu.child(div().mb_1().child(design_system::search_field(
                                    &self.agent_profile_settings.dropdown_filter_input,
                                    true,
                                )))
                            })
                            .child(
                                div()
                                    .id("agent-profile-dropdown-options")
                                    .max_h(px(224.0))
                                    .min_h_0()
                                    .overflow_y_scroll()
                                    .when(options.is_empty(), |list| {
                                        list.child(
                                            div()
                                                .h(px(32.0))
                                                .flex()
                                                .items_center()
                                                .px_2()
                                                .text_size(crate::theme::caption_size())
                                                .text_color(theme::text_muted())
                                                .child("No Matching Options"),
                                        )
                                    })
                                    .children(options.into_iter().enumerate().map(
                                        |(index, (option, name))| {
                                            let selected_option = option.clone();
                                            let option_label = name.clone();
                                            div()
                                                .id(("profile-dropdown-option", index))
                                                .focusable()
                                                .tab_stop(enabled)
                                                .role(Role::ListBoxOption)
                                                .aria_label(option_label)
                                                .aria_selected(selected == option)
                                                .flex()
                                                .items_center()
                                                .h(px(30.0))
                                                .px_2()
                                                .rounded_sm()
                                                .when(
                                                    index
                                                        == self
                                                            .agent_profile_settings
                                                            .dropdown_highlighted_index,
                                                    |row| row.bg(theme::surface_raised()),
                                                )
                                                .when(enabled, |row| {
                                                    row.cursor(CursorStyle::PointingHand)
                                                        .hover(|style| {
                                                            style.bg(theme::surface_raised())
                                                        })
                                                        .on_click(
                                                            cx.listener(
                                                                move |this, _, window, cx| {
                                                                    this.select_agent_profile_dropdown_value(
                                                                        dropdown,
                                                                        selected_option.clone(),
                                                                        window,
                                                                        cx,
                                                                    );
                                                                },
                                                            ),
                                                        )
                                                })
                                                .child(div().w(px(18.0)).when(
                                                    selected == option,
                                                    |slot| {
                                                        slot.child(icon(
                                                            AleraIcon::Check,
                                                            13.0,
                                                            theme::text(),
                                                        ))
                                                    },
                                                ))
                                                .child(name)
                                        },
                                    )),
                            ),
                    )
                    .with_priority(2),
                )
            })
    }
}

fn selected_value(app: &AleraApp, dropdown: AgentProfileDropdown) -> &str {
    match dropdown {
        AgentProfileDropdown::Adapter => &app.agent_profile_settings.adapter,
        AgentProfileDropdown::LaunchMode => &app.agent_profile_settings.launch_mode,
        AgentProfileDropdown::Managed(key) => app
            .agent_profile_settings
            .managed_config
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default(),
    }
}

pub(super) fn launch_mode_label(mode: &str) -> &'static str {
    if mode == "managed" {
        "Managed"
    } else {
        "Command"
    }
}

pub(super) fn settings_group(
    title: &'static str,
    description: &'static str,
    rows: Vec<gpui::Div>,
) -> gpui::Div {
    div()
        .child(
            div()
                .ml_1()
                .mb_2()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title),
                )
                .child(
                    div()
                        .mt_1()
                        .text_size(px(12.0))
                        .text_color(theme::text_muted())
                        .child(description),
                ),
        )
        .child(
            div()
                .overflow_hidden()
                .rounded_lg()
                .border_1()
                .border_color(theme::border_subtle())
                .bg(theme::surface_selected())
                .children(rows),
        )
}

pub(super) fn settings_row(
    title: &'static str,
    description: &'static str,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    settings_row_width(title, description, 220.0, control)
}

pub(super) fn settings_row_width(
    title: &'static str,
    description: &'static str,
    control_width: f32,
    control: impl gpui::IntoElement,
) -> gpui::Div {
    div()
        .flex()
        .items_center()
        .min_h(px(68.0))
        .p_3()
        .border_b_1()
        .border_color(theme::border_subtle())
        .child(
            div()
                .flex_1()
                .child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::MEDIUM)
                        .child(title),
                )
                .when(!description.is_empty(), |copy| {
                    copy.child(
                        div()
                            .mt_1()
                            .text_size(px(12.0))
                            .text_color(theme::text_muted())
                            .child(description),
                    )
                }),
        )
        .child(div().w(px(control_width)).child(control))
}

pub(super) fn settings_checkbox(
    id: impl Into<gpui::ElementId>,
    label: impl Into<SharedString>,
    enabled: bool,
    interactive: bool,
) -> gpui::Stateful<gpui::Div> {
    design_system::checkbox(enabled, interactive, None)
        .id(id)
        .focusable()
        .tab_stop(interactive)
        .role(Role::CheckBox)
        .aria_label(label.into())
        .aria_toggled(if enabled {
            Toggled::True
        } else {
            Toggled::False
        })
}

pub(super) fn profile_action_button(
    id: &'static str,
    label: &'static str,
    icon_kind: AleraIcon,
    filled: bool,
    disabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(!disabled)
        .role(Role::Button)
        .aria_label(label)
        .flex()
        .items_center()
        .justify_center()
        .h(px(34.0))
        .px_3()
        .gap_2()
        .rounded_lg()
        .border_1()
        .border_color(if filled {
            theme::accent()
        } else {
            theme::border()
        })
        .bg(if filled {
            if disabled {
                theme::surface_raised()
            } else {
                theme::accent()
            }
        } else {
            theme::transparent()
        })
        .text_color(if filled && !disabled {
            theme::on_accent()
        } else if disabled {
            theme::text_faint()
        } else {
            theme::text()
        })
        .when(!disabled, |button| {
            button
                .cursor(CursorStyle::PointingHand)
                .hover(|style| style.bg(theme::surface_raised()))
        })
        .child(icon(
            icon_kind,
            15.0,
            if filled && !disabled {
                theme::on_accent()
            } else {
                theme::text_muted()
            },
        ))
        .child(label)
}
