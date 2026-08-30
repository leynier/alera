use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, Context, CursorStyle,
    InteractiveElement as _, IntoElement as _, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};

use super::keyboard_settings::{definition, effective_bindings};
use super::keyboard_settings_render::keyboard_binding_chip;
use super::AleraApp;
use gpui_component::scroll::ScrollableElement as _;
use crate::icons::{alera_logo, icon, AleraIcon};
use crate::theme;

impl AleraApp {
    pub(super) fn render_welcome_dashboard(&self, cx: &mut Context<Self>) -> AnyElement {
        let has_git_projects = self
            .snapshot
            .projects
            .iter()
            .any(|project| project.kind == "gitRepository");
        let quick_start =
            div()
                .flex()
                .flex_col()
                .w_full()
                .rounded(px(10.0))
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
                    .on_click(cx.listener(|this, _, window, cx| {
                        this.add_project(window, cx);
                    })),
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
                        action.on_click(cx.listener(|this, _, window, cx| {
                            this.open_new_workspace_dialog_for_project(None, window, cx)
                        }))
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
                    .on_click(cx.listener(|this, _, window, cx| {
                        this.open_settings_dialog(window, cx);
                    })),
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
                .when(index > 0, |row| row.mt(px(8.0)).pt(px(8.0)).border_t_1().border_color(theme::border_subtle()))
                .text_size(crate::theme::body_size())
                .text_color(theme::text_muted())
                .child(label)
                .when_some(shortcut, |row, shortcut| {
                    row.child(keyboard_binding_chip(shortcut).h(px(26.0)).rounded(px(4.0)).border_1().border_color(theme::border()).font_weight(gpui::FontWeight::MEDIUM).text_color(theme::text()))
                })
        }).collect::<Vec<_>>();

        gpui::container_query(move |size, _, _| {
            let wide = welcome_is_wide(size.width.as_f32());
            welcome_scroll_surface(size.height,
                div()
                    .w_full()
                    .flex_shrink_0()
                    .max_w(px(1000.0))
                    .p(px(32.0))
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
                                    .flex_shrink_0()
                                    .rounded(px(10.0))
                                    .bg(theme::surface_raised())
                                    .border_1()
                                    .border_color(theme::border_subtle())
                                    .child(alera_logo(32.0)),
                            )
                            .child(
                                div()
                                    .min_w_0()
                                    .flex_1()
                                    .child(
                                        div()
                                            .text_ellipsis()
                                            .text_size(crate::theme::headline_size())
                                            .font_weight(gpui::FontWeight::BOLD)
                                            .child("Welcome to Alera"),
                                    )
                                    .child(
                                        div()
                                            .mt_1()
                                            .text_size(crate::theme::body_size())
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
                            .when(!wide, |columns| columns.flex_col())
                            .gap_8()
                            .pt_8()
                            .child(
                                div()
                                    .when(wide, |column| column.flex_1())
                                    .when(!wide, |column| column.w_full())
                                    .child(
                                        div()
                                            .mb_3()
                                            .text_size(crate::theme::body_size())
                                            .font_weight(gpui::FontWeight::BOLD)
                                            .text_color(theme::text_muted())
                                            .child("Quick Start"),
                                    )
                                    .child(quick_start),
                            )
                            .child(
                                div()
                                    .when(wide, |column| column.flex_1())
                                    .when(!wide, |column| column.w_full())
                                    .child(
                                        div()
                                            .mb_3()
                                            .text_size(crate::theme::body_size())
                                            .font_weight(gpui::FontWeight::BOLD)
                                            .text_color(theme::text_muted())
                                            .child("Keyboard Shortcuts"),
                                    )
                                    .child(
                                        div()
                                            .rounded(px(10.0))
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
        })
            .into_any_element()
    }
}

fn welcome_scroll_surface(height: gpui::Pixels, content: impl gpui::IntoElement) -> AnyElement {
    div()
        .size_full()
        .overflow_y_scrollbar()
        .id("welcome-scroll")
        .child(
            div()
                .flex()
                .flex_col()
                .flex_shrink_0()
                .min_h(height)
                .items_center()
                .justify_center()
                .child(content),
        )
        .into_any_element()
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
        .focusable()
        .tab_stop(enabled)
        .role(Role::Button)
        .aria_label(title)
        .flex()
        .items_center()
        .p(px(16.0))
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
                        .text_size(crate::theme::body_size())
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(title),
                )
                .child(
                    div()
                        .mt(px(2.0))
                        .text_size(crate::theme::caption_size())
                        .text_color(theme::text_muted())
                        .child(subtitle),
                ),
        )
        .child(icon(AleraIcon::ChevronRight, 16.0, theme::text_faint()))
}

fn welcome_is_wide(available_width: f32) -> bool {
    available_width.min(1000.0) - 64.0 >= 760.0
}

#[cfg(test)]
mod tests {
    #[test]
    fn welcome_breakpoint_matches_flutter_inner_constraints() {
        assert!(!super::welcome_is_wide(823.0));
        assert!(super::welcome_is_wide(824.0));
        assert!(super::welcome_is_wide(1600.0));
    }

    #[cfg(feature = "gpui-tests")]
    mod scroll {
        use super::super::*;
        use gpui::{IntoElement, Render, ScrollDelta, ScrollWheelEvent, TestAppContext, Window, point};

        struct WelcomeScrollProbe;

        impl Render for WelcomeScrollProbe {
            fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
                gpui::container_query(|size, _, _| {
                    welcome_scroll_surface(size.height, div().w_full().flex_shrink_0().child(
                        div().h(px(750.0)).child(
                            div().h(px(20.0)).debug_selector(|| "welcome-first".into()),
                        ),
                    ))
                }).w(px(500.0)).h(px(300.0))
            }
        }

        #[gpui::test]
        fn welcome_scroll_preserves_intrinsic_content_height(cx: &mut TestAppContext) {
            cx.update(gpui_component::init);
            let (_, cx) = cx.add_window_view(|_, _| WelcomeScrollProbe);
            cx.run_until_parked();
            cx.update(|window, cx| { let _ = window.draw(cx); });
            let before = cx.debug_bounds("welcome-first").unwrap().origin.y;
            cx.simulate_event(ScrollWheelEvent {
                position: point(px(200.0), px(150.0)),
                delta: ScrollDelta::Pixels(point(px(0.0), px(-100.0))),
                ..Default::default()
            });
            cx.run_until_parked();
            cx.update(|window, cx| { let _ = window.draw(cx); });
            let after = cx.debug_bounds("welcome-first").unwrap().origin.y;
            assert!(after < before, "overflowing Welcome content must scroll");
        }
    }
}
