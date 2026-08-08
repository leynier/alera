use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    IntoElement, MouseButton, MouseDownEvent, ParentElement as _, StatefulInteractiveElement as _,
    Styled as _,
};

use super::AleraApp;
use crate::activity::SettingsPane;
use crate::icons::{icon, AleraIcon};
use crate::{design_system, theme};

impl AleraApp {
    pub(crate) fn open_settings_dialog(
        &mut self,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        if !self.show_settings_dialog {
            self.settings_previous_focus = window.focused(cx);
        }
        self.show_settings_dialog = true;
        self.dismiss_status_popover(cx);
        self.refresh_settings_values(cx);
        if self.settings_pane == SettingsPane::Agents {
            self.load_cli_registration_status(cx);
        }
        cx.notify();
    }

    pub(crate) fn open_settings_dialog_from_menu(&mut self, cx: &mut Context<Self>) {
        self.show_settings_dialog = true;
        self.dismiss_status_popover(cx);
        self.refresh_settings_values(cx);
        if self.settings_pane == SettingsPane::Agents {
            self.load_cli_registration_status(cx);
        }
        cx.notify();
    }

    pub(super) fn close_settings_dialog(
        &mut self,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        self.show_settings_dialog = false;
        self.mobile_access.overlay = None;
        self.keyboard_settings.recording_id = None;
        self.keyboard_settings.conflict = None;
        self.keyboard_settings.error = None;
        self.show_claude_profile_dialog = false;
        self.claude_profile_error = None;
        if let Some(focus) = self.settings_previous_focus.take() {
            focus.focus(window);
        } else {
            self.terminal_focus.focus(window);
        }
        cx.notify();
    }

    pub(super) fn select_settings_pane(
        &mut self,
        pane: SettingsPane,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        self.settings_pane = pane;
        self.settings_scroll_handle
            .set_offset(gpui::point(px(0.0), px(0.0)));
        if pane != SettingsPane::Keyboard {
            self.keyboard_settings.recording_id = None;
            self.keyboard_settings.conflict = None;
            self.keyboard_settings.error = None;
        }
        if pane == SettingsPane::MobileDevices {
            self.refresh_mobile_access(window, cx);
        }
        if pane == SettingsPane::Projects {
            self.refresh_project_config_settings(window, cx);
        }
        if pane == SettingsPane::AgentProfiles {
            self.refresh_agent_profiles(window, cx);
        }
        if pane == SettingsPane::Agents {
            self.load_cli_registration_status(cx);
        }
        cx.notify();
    }

    pub(super) fn render_settings_dialog(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let query = self
            .settings_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let has_matches = SettingsPane::ALL
            .into_iter()
            .any(|pane| super::settings_search_catalog::pane_matches(pane, &query));
        div()
            .absolute()
            .top_0()
            .right_0()
            .bottom_0()
            .left_0()
            .occlude()
            .bg(theme::overlay_scrim())
            .child(
                div()
                    .absolute()
                    .top(px(39.0))
                    .right(px(68.0))
                    .bottom(px(39.0))
                    .left(px(68.0))
                    .flex()
                    .min_w_0()
                    .min_h_0()
                    .overflow_hidden()
                    .rounded_xl()
                    .border_1()
                    .border_color(theme::border_subtle())
                    .bg(theme::surface())
                    .shadow_lg()
                    .child(self.render_settings_navigation(cx))
                    .child(if has_matches {
                        div()
                            .flex()
                            .flex_col()
                            .flex_1()
                            .min_w_0()
                            .min_h_0()
                            .overflow_hidden()
                            .child(self.render_settings_header(cx))
                            .child(self.render_settings_pane(cx))
                            .into_any_element()
                    } else {
                        self.render_no_settings_results(cx).into_any_element()
                    }),
            )
            .when_some(
                self.keyboard_settings.conflict.as_ref(),
                |dialog, conflict| dialog.child(self.render_keyboard_conflict(conflict, cx)),
            )
            .when(self.show_claude_profile_dialog, |dialog| {
                dialog.child(self.render_claude_profile_dialog(cx))
            })
    }

    fn render_no_settings_results(&self, cx: &mut Context<Self>) -> gpui::Div {
        div()
            .relative()
            .flex()
            .flex_1()
            .items_center()
            .justify_center()
            .text_size(px(13.0))
            .text_color(theme::text_muted())
            .child("No matching settings.")
            .child(
                div()
                    .id("close-empty-settings")
                    .absolute()
                    .top(px(16.0))
                    .right(px(16.0))
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(28.0))
                    .h(px(28.0))
                    .rounded_md()
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.close_settings_dialog(window, cx);
                        }),
                    )
                    .child(icon(AleraIcon::Close, 14.0, theme::text_muted())),
            )
    }

    fn render_settings_header(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let groups = settings_pane_groups(self.settings_pane);
        div()
            .flex()
            .flex_col()
            .px_6()
            .pt_5()
            .pb_4()
            .border_b_1()
            .border_color(theme::border_subtle())
            .child(
                div()
                    .flex()
                    .items_center()
                    .child(icon(self.settings_pane.icon(), 18.0, theme::accent()))
                    .child(
                        div()
                            .ml_2()
                            .text_size(px(16.0))
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(self.settings_pane.label()),
                    )
                    .child(div().flex_1())
                    .when(settings_pane_supports_reset(self.settings_pane), |row| {
                        row.child(
                            div()
                                .id("reset-settings-pane")
                                .flex()
                                .items_center()
                                .justify_center()
                                .h(px(34.0))
                                .px_3()
                                .rounded_lg()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_raised()))
                                .on_mouse_down(
                                    MouseButton::Left,
                                    cx.listener(|this, _, _, cx| match this.settings_pane {
                                        SettingsPane::AiText => this.reset_ai_text_settings(cx),
                                        SettingsPane::Editor => this.reset_editor_settings(cx),
                                        SettingsPane::Terminal => {
                                            this.reset_terminal_settings(cx);
                                        }
                                        SettingsPane::Keyboard => {
                                            this.reset_keyboard_settings(cx);
                                        }
                                        _ => {}
                                    }),
                                )
                                .child(format!("Reset {}", self.settings_pane.label())),
                        )
                    })
                    .child(
                        div()
                            .id("close-settings")
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(34.0))
                            .h(px(34.0))
                            .rounded_md()
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(|this, _, window, cx| {
                                    this.close_settings_dialog(window, cx);
                                }),
                            )
                            .child(icon(AleraIcon::Close, 16.0, theme::text_muted())),
                    ),
            )
            .child(
                div()
                    .mt_1()
                    .text_size(px(12.0))
                    .text_color(theme::text_muted())
                    .child(settings_pane_description(self.settings_pane)),
            )
            .when(groups.len() >= 3, |header| {
                header.child(div().flex().flex_wrap().gap(px(6.0)).mt_3().children(
                    groups.iter().enumerate().map(|(index, group)| {
                        let anchor = self
                            .settings_group_anchors
                            .get(&(self.settings_pane, index))
                            .cloned();
                        div()
                            .id(("settings-group-chip", index))
                            .px(px(6.0))
                            .py(px(2.0))
                            .rounded_sm()
                            .bg(theme::accent_subtle())
                            .text_size(px(10.0))
                            .font_weight(gpui::FontWeight::MEDIUM)
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_raised()))
                            .when_some(anchor, |chip, anchor| {
                                chip.on_mouse_down(
                                    MouseButton::Left,
                                    move |_: &MouseDownEvent, window, cx| {
                                        anchor.scroll_to(window, cx);
                                        cx.stop_propagation();
                                    },
                                )
                            })
                            .child(*group)
                    }),
                ))
            })
    }

    fn render_settings_navigation(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let filter = self
            .settings_search_input
            .read(cx)
            .value()
            .trim()
            .to_lowercase();
        let mut navigation_rows = Vec::new();
        for (section_index, section) in ["Preferences", "Resources"].into_iter().enumerate() {
            let panes = SettingsPane::ALL
                .into_iter()
                .filter(|pane| {
                    pane.section() == section
                        && super::settings_search_catalog::pane_matches(*pane, &filter)
                })
                .collect::<Vec<_>>();
            if panes.is_empty() {
                continue;
            }
            navigation_rows.push(
                div()
                    .px_2()
                    .pt_1()
                    .pb_1()
                    .text_size(px(10.0))
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .text_color(theme::text_faint())
                    .child(section.to_uppercase())
                    .into_any_element(),
            );
            for (pane_index, pane) in panes.into_iter().enumerate() {
                let selected = self.settings_pane == pane;
                let match_count = super::settings_search_catalog::pane_match_count(pane, &filter);
                navigation_rows.push(
                    div()
                        .id(("settings-pane", pane_index + section_index * 20))
                        .flex()
                        .items_center()
                        .mb(px(2.0))
                        .px_2()
                        .py_2()
                        .gap_2()
                        .rounded_md()
                        .cursor(CursorStyle::PointingHand)
                        .text_sm()
                        .text_color(if selected {
                            theme::text()
                        } else {
                            theme::text_muted()
                        })
                        .hover(|style| style.bg(theme::surface_raised()))
                        .when(selected, |row| row.bg(theme::surface_raised()))
                        .on_mouse_down(
                            MouseButton::Left,
                            cx.listener(move |this, _: &MouseDownEvent, window, cx| {
                                this.select_settings_pane(pane, window, cx);
                                if pane == SettingsPane::AiText {
                                    this.auto_discover_configured_ai_models(window, cx);
                                }
                                cx.stop_propagation();
                            }),
                        )
                        .child(div().w(px(2.0)).h(px(16.0)).rounded_full().bg(if selected {
                            theme::accent()
                        } else {
                            theme::transparent()
                        }))
                        .child(icon(
                            pane.icon(),
                            16.0,
                            if selected {
                                theme::text()
                            } else {
                                theme::text_muted()
                            },
                        ))
                        .child(pane.label())
                        .when(match_count > 0, |row| {
                            row.child(div().flex_1()).child(
                                div()
                                    .min_w(px(18.0))
                                    .h(px(18.0))
                                    .px(px(5.0))
                                    .rounded_full()
                                    .bg(theme::accent_subtle())
                                    .text_size(px(10.0))
                                    .text_color(theme::text_muted())
                                    .child(match_count.to_string()),
                            )
                        })
                        .into_any_element(),
                );
            }
        }
        div()
            .flex()
            .flex_col()
            .w(px(260.0))
            .h_full()
            .min_h_0()
            .border_r_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface_selected())
            .child(
                div().flex().items_center().h(px(44.0)).px_3().child(
                    div()
                        .text_size(px(13.0))
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child("Settings"),
                ),
            )
            .child(div().h(px(1.0)).bg(theme::border_subtle()))
            .child(div().p_3().child(design_system::search_field(
                &self.settings_search_input,
                false,
            )))
            .child(div().h(px(1.0)).bg(theme::border_subtle()))
            .child(
                div()
                    .id("settings-navigation")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .p_2()
                    .children(navigation_rows),
            )
    }
}

fn settings_pane_description(pane: SettingsPane) -> &'static str {
    match pane {
        SettingsPane::Application => "Storage, safety, runtime, diagnostics and updates.",
        SettingsPane::Agents => "Agent Hooks, Notifications And Alera Skills.",
        SettingsPane::Quotas => "Provider Usage, Claude Profiles And Credential Environment.",
        SettingsPane::AiText => "AI-Generated Source Control Text.",
        SettingsPane::Editor => "Code Editor Defaults.",
        SettingsPane::Terminal => "Appearance Defaults For New Terminal Sessions.",
        SettingsPane::Keyboard => "Shortcuts And Key Bindings.",
        SettingsPane::Projects => "Per-Project Workspace Setup.",
        SettingsPane::MobileDevices => "Pair And Manage The Mobile Companion App.",
        SettingsPane::AgentProfiles => "Launch Configurations Orchestration Can Dispatch To.",
    }
}

pub(super) fn settings_pane_groups(pane: SettingsPane) -> &'static [&'static str] {
    match pane {
        SettingsPane::Application => &["Storage", "Safety", "Runtime", "Diagnostics"],
        SettingsPane::Agents => &["CLI And Skills", "Status Hooks", "Behavior"],
        SettingsPane::Quotas => &["Providers", "Claude", "Credentials"],
        SettingsPane::AiText => &["Generation", "Prompt Overrides", "Instructions"],
        SettingsPane::Editor => &[],
        SettingsPane::Terminal => &[
            "Typography",
            "Cursor",
            "Appearance",
            "Interaction",
            "Advanced",
        ],
        SettingsPane::Keyboard => &[],
        SettingsPane::Projects => &[],
        SettingsPane::MobileDevices => &[
            "Mobile Gateway",
            "Link A Device",
            "Active Pairing Offers",
            "Paired Devices",
        ],
        SettingsPane::AgentProfiles => &[],
    }
}

fn settings_pane_supports_reset(pane: SettingsPane) -> bool {
    matches!(
        pane,
        SettingsPane::AiText
            | SettingsPane::Editor
            | SettingsPane::Terminal
            | SettingsPane::Keyboard
    )
}
