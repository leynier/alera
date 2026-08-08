use gpui::{
    div, px, AnyElement, Context, CursorStyle, InteractiveElement as _, IntoElement as _,
    ParentElement as _, Styled as _,
};

use super::AleraApp;
use crate::icons::{alera_logo, icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_welcome_dashboard(&self, cx: &mut Context<Self>) -> AnyElement {
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
                    AleraIcon::FolderSpecial,
                    "Add Project",
                    "Open a local folder or clone a repository",
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
                    AleraIcon::Workflow,
                    "New Workspace",
                    "Create a linked workspace for active Git project",
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(|this, _, _, cx| this.open_new_workspace_dialog(cx)),
                ),
            )
            .child(
                welcome_action(
                    "welcome-settings",
                    AleraIcon::Settings,
                    "Open Settings",
                    "Configure keyboard shortcuts and preferences",
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(|this, _, window, cx| {
                        this.open_settings_dialog(window, cx);
                    }),
                ),
            );
        let shortcuts = [
            ("Add Project", "⇧⌘O"),
            ("New Workspace", "⇧⌘N"),
            ("Toggle Sidebar", "⌘B"),
            ("New Terminal Tab", "⌘T"),
            ("Open Settings", "⌘,"),
            ("Split Right", "⌘D"),
        ]
        .into_iter()
        .enumerate()
        .map(|(index, (label, shortcut))| {
            div()
                .id(("welcome-shortcut", index))
                .flex()
                .items_center()
                .justify_between()
                .h(px(44.0))
                .px_3()
                .border_b_1()
                .border_color(theme::border_subtle())
                .text_sm()
                .text_color(theme::text_muted())
                .child(label)
                .child(
                    div()
                        .px_2()
                        .py_1()
                        .rounded_md()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface_raised())
                        .font_family("JetBrains Mono")
                        .text_xs()
                        .text_color(theme::text())
                        .child(shortcut),
                )
        });

        div()
            .flex_1()
            .flex()
            .items_center()
            .justify_center()
            .p_8()
            .child(
                div()
                    .w_full()
                    .max_w(px(1000.0))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_3()
                            .pb_5()
                            .border_b_1()
                            .border_color(theme::border_subtle())
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(px(52.0))
                                    .h(px(52.0))
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
                                            .font_weight(gpui::FontWeight::SEMIBOLD)
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
                            .pt_5()
                            .child(
                                div()
                                    .flex_1()
                                    .child(
                                        div()
                                            .mb_2()
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
                                            .mb_2()
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
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(72.0))
        .px_3()
        .gap_3()
        .border_b_1()
        .border_color(theme::border_subtle())
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_raised()))
        .child(icon(icon_kind, 18.0, theme::text()))
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
