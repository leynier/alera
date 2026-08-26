use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Styled as _,
};

use super::keyboard_settings::{definition, effective_bindings};
use super::keyboard_settings_render::keyboard_binding_chip;
use super::AleraApp;
use crate::icons::{alera_logo, icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_welcome_dashboard(&self, cx: &mut Context<Self>) -> AnyElement {
        let has_git_projects = self
            .snapshot
            .projects
            .iter()
            .any(|project| project.kind == "gitRepository");
        let quick_start = div()
            .flex()
            .flex_col()
            .flex_1()
            .rounded_lg()
            .border_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface())
            .overflow_hidden()
            .child(
                welcome_action(
                    "welcome-add-project",
                    AleraIcon::NewFolder,
                    "Add Project",
                    "Open a local folder or clone a repository",
                    true,
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(|this, _, window, cx| {
                        this.add_project(window, cx);
                    }),
                ),
            )
            .child(
                welcome_action(
                    "welcome-new-workspace",
                    AleraIcon::GitFork,
                    "New Workspace",
                    "Create a linked workspace for active Git project",
                    has_git_projects,
                )
                .when(has_git_projects, |action| {
                    action.on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, window, cx| {
                            this.open_new_workspace_dialog(window, cx)
                        }),
                    )
                }),
            )
            .child(
                welcome_action(
                    "welcome-settings",
                    AleraIcon::Settings,
                    "Open Settings",
                    "Configure keyboard shortcuts and preferences",
                    true,
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(|this, _, window, cx| {
                        this.open_settings_dialog(window, cx);
                    }),
                ),
            );
        let shortcuts = [
            ("addProject", "Add Project"),
            ("createWorkspace", "New Workspace"),
            ("toggleSidebar", "Toggle Sidebar"),
            ("newTerminalTab", "New Terminal Tab"),
            ("openSettings", "Open Settings"),
            ("splitRight", "Split Right"),
        ]
        .into_iter()
        .enumerate()
        .map(|(index, (id, label))| {
            let shortcut = definition(id)
                .map(|definition| effective_bindings(&self.settings_state, definition))
                .and_then(|bindings| bindings.into_iter().next());
            div()
                .id(("welcome-shortcut", index))
                .flex()
                .items_center()
                .justify_between()
                .h(px(40.0))
                .px_0()
                .border_b_1()
                .border_color(theme::border_subtle())
                .text_sm()
                .text_color(theme::text_muted())
                .child(label)
                .when_some(shortcut, |row, shortcut| {
                    row.child(keyboard_binding_chip(shortcut))
                })
        });

        div()
            .flex_1()
            .flex()
            // Flutter keeps the dashboard at the top of the scroll view and
            // only centers the constrained content horizontally.
            .items_center()
            .justify_center()
            .p_8()
            .child(
                div()
                    .w_full()
                    // The outer Flutter constraint includes the 32 px scroll
                    // padding on each side, leaving 936 px for the content.
                    .max_w(px(936.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_4()
                            .pb_6()
                            .border_b_1()
                            .border_color(theme::border_subtle())
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(50.0))
                                    .h(px(50.0))
                                    .rounded_lg()
                                    .bg(theme::surface_raised())
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .child(alera_logo(32.0)),
                            )
                            .child(
                                div()
                                    .child(
                                        div()
                                            .text_2xl()
                                            .font_weight(gpui::FontWeight::BOLD)
                                            .child("Welcome to Alera"),
                                    )
                                    .child(
                                        div()
                                            .mt_1()
                                            .text_sm()
                                            .text_color(theme::text_muted())
                                            .child(
                                                "A terminal-first agentic developer environment",
                                            ),
                                    ),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .gap_8()
                            .pt_8()
                            .child(
                                div()
                                    .flex_1()
                                    .child(
                                        div()
                                            .mb_3()
                                            .text_sm()
                                            .font_weight(gpui::FontWeight::SEMIBOLD)
                                            .child("Quick Start"),
                                    )
                                    .child(quick_start),
                            )
                            .child(
                                div()
                                    .flex_1()
                                    .child(
                                        div()
                                            .mb_3()
                                            .text_sm()
                                            .font_weight(gpui::FontWeight::SEMIBOLD)
                                            .child("Keyboard Shortcuts"),
                                    )
                                    .child(
                                        div()
                                            .rounded_lg()
                                            .border_1()
                                            .border_color(theme::border_subtle())
                                            .bg(theme::surface())
                                            .overflow_hidden()
                                            .p_4()
                                            .children(shortcuts),
                                    ),
                            ),
                    ),
            )
            .into_any_element()
    }
}

fn welcome_action(
    id: &'static str,
    icon_kind: AleraIcon,
    title: &'static str,
    subtitle: &'static str,
    enabled: bool,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(70.0))
        .px_4()
        .gap_4()
        .border_b_1()
        .border_color(theme::border_subtle())
        .cursor(if enabled {
            CursorStyle::PointingHand
        } else {
            CursorStyle::Arrow
        })
        .when(enabled, |action| {
            action.hover(|style| style.bg(theme::surface_raised()))
        })
        .opacity(if enabled { 1.0 } else { 0.4 })
        .child(icon(icon_kind, 24.0, theme::accent()))
        .child(
            div()
                .flex_1()
                .child(
                    div()
                        .text_sm()
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title),
                )
                .child(
                    div()
                        .mt_1()
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child(subtitle),
                ),
        )
        .child(icon(AleraIcon::ChevronRight, 14.0, theme::text_faint()))
}
