use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    IntoElement, MouseButton, MouseDownEvent, ParentElement as _, Styled as _, Window,
};

use super::AleraApp;
use crate::{
    icons::{icon, AleraIcon},
    theme,
};

impl AleraApp {
    pub(super) fn render_workbench(
        &self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let workspace = self
            .selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id));
        let project = self
            .selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.project_for_workspace(id));
        let selected_tab = self
            .selected_tab_id
            .as_deref()
            .and_then(|id| self.snapshot.tabs.iter().find(|tab| tab.id == id));
        let has_tabs = !self.snapshot.tabs.is_empty();
        let content = if workspace.is_none() || !has_tabs {
            self.render_welcome_dashboard(cx)
        } else if let Some(tab) = selected_tab.filter(|tab| tab.kind == "gitDiff") {
            self.render_git_diff_surface(tab, cx)
        } else if selected_tab.is_some_and(|tab| {
            matches!(tab.kind.as_str(), "editor" | "markdownViewer" | "pdf")
                && tab
                    .payload
                    .get("filePath")
                    .and_then(|value| value.as_str())
                    .is_some()
        }) {
            self.render_editor(window, cx)
        } else if selected_tab.is_some_and(|tab| tab.kind == "terminal") {
            self.render_terminal_surface(cx)
        } else {
            div()
                .flex_1()
                .p_6()
                .child(
                    div()
                        .text_2xl()
                        .font_weight(gpui::FontWeight::SEMIBOLD)
                        .child(
                            workspace
                                .map(|item| item.name.clone())
                                .unwrap_or_else(|| "No Workspace Selected".to_string()),
                        ),
                )
                .child(
                    div()
                        .mt_2()
                        .text_sm()
                        .text_color(theme::text_muted())
                        .child(
                            project
                                .map(|item| item.repo_path.clone())
                                .unwrap_or_else(|| "Select A Workspace To Begin".to_string()),
                        ),
                )
                .child(
                    div()
                        .mt_6()
                        .rounded_lg()
                        .border_1()
                        .border_color(theme::border())
                        .bg(theme::surface())
                        .p_5()
                        .child(
                            div().text_lg().font_weight(gpui::FontWeight::MEDIUM).child(
                                selected_tab
                                    .map(|tab| tab.title.clone())
                                    .unwrap_or_else(|| "Workbench".to_string()),
                            ),
                        )
                        .child(
                            div()
                                .mt_2()
                                .text_sm()
                                .text_color(theme::text_muted())
                                .child(match selected_tab {
                                    Some(tab) => format!(
                                        "{} Surface · Runtime-Backed Tab {}",
                                        title_case_kind(&tab.kind),
                                        tab.id
                                    ),
                                    None => "Open Or Create A Tab To Begin.".to_string(),
                                }),
                        ),
                )
                .into_any_element()
        };

        let tab_bar = div()
            .flex()
            .items_center()
            .h(theme::tab_bar_height())
            .border_b_1()
            .border_color(theme::border_subtle())
            .bg(theme::surface())
            .px_2()
            .py_1()
            .gap_1()
            .children(self.snapshot.tabs.iter().enumerate().map(|(index, tab)| {
                let tab_id = tab.id.clone();
                let close_tab_id = tab.id.clone();
                let context_tab_id = tab.id.clone();
                let context_group_id = self
                    .snapshot
                    .layout
                    .as_ref()
                    .map(|layout| layout.active_group_id.clone())
                    .unwrap_or_else(|| "legacy".to_string());
                let selected = self.selected_tab_id.as_deref() == Some(tab.id.as_str());
                let title = if selected && tab.kind == "terminal" {
                    self.terminal_sessions
                        .get(
                            tab.payload
                                .get("terminalSessionId")
                                .and_then(serde_json::Value::as_str)
                                .unwrap_or(&tab.id),
                        )
                        .and_then(|session| session.emulator.title())
                        .unwrap_or_else(|| tab.title.clone())
                } else {
                    tab.title.clone()
                };
                div()
                    .id(("tab", index))
                    .flex()
                    .items_center()
                    .h(px(32.0))
                    .px_3()
                    .gap_2()
                    .rounded_lg()
                    .border_1()
                    .border_color(if selected {
                        theme::border()
                    } else {
                        theme::border_subtle()
                    })
                    .cursor(CursorStyle::PointingHand)
                    .text_sm()
                    .text_color(if selected {
                        theme::text()
                    } else {
                        theme::text_muted()
                    })
                    .hover(|style| style.bg(theme::surface_raised()))
                    .when(selected, |item| item.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(move |this, _, _, cx| {
                            this.activate_workspace_tab(tab_id.clone(), cx);
                        }),
                    )
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(move |this, event: &MouseDownEvent, window, cx| {
                            cx.stop_propagation();
                            this.open_tab_context_menu(
                                context_group_id.clone(),
                                context_tab_id.clone(),
                                event.position,
                                window,
                                cx,
                            );
                        }),
                    )
                    .child(tab_kind_icon(
                        &tab.kind,
                        tab.payload
                            .get("filePath")
                            .and_then(serde_json::Value::as_str),
                        if selected {
                            theme::text()
                        } else {
                            theme::text_muted()
                        },
                    ))
                    .child(title)
                    .child(
                        div()
                            .id(("close-tab", index))
                            .text_xs()
                            .text_color(theme::text_muted())
                            .hover(|style| style.text_color(theme::text()))
                            .on_mouse_down(
                                MouseButton::Left,
                                cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                    cx.stop_propagation();
                                    this.request_close_tab(close_tab_id.clone(), cx);
                                }),
                            )
                            .child(icon(AleraIcon::Close, 14.0, theme::text_muted())),
                    )
            }))
            .child(
                div()
                    .id("new-terminal-tab")
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(px(28.0))
                    .h(px(28.0))
                    .rounded_lg()
                    .text_color(theme::text_muted())
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface_raised()))
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| {
                            this.create_terminal_tab(cx);
                        }),
                    )
                    .child(icon(AleraIcon::Add, 16.0, theme::text_muted())),
            );

        let primary = div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .bg(theme::app_background())
            .when(workspace.is_some() && has_tabs, |view| view.child(tab_bar))
            .child(content);
        let primary = self
            .snapshot
            .layout
            .as_ref()
            .filter(|_| workspace.is_some() && has_tabs)
            .map(|layout| self.render_persisted_workbench_layout(layout, window, cx))
            .unwrap_or_else(|| primary.into_any_element());

        div()
            .flex()
            .flex_1()
            .h_full()
            .child(
                div()
                    .w_0()
                    .flex_1()
                    .h_full()
                    .overflow_hidden()
                    .child(primary),
            )
            .when(workspace.is_some() && has_tabs, |layout| {
                layout.child(self.render_context_sidebar(window, cx))
            })
    }
}

pub(super) fn tab_kind_icon(kind: &str, path: Option<&str>, color: gpui::Rgba) -> gpui::AnyElement {
    match kind {
        "editor" | "markdownViewer" => path.map_or_else(
            || icon(AleraIcon::File, 15.0, color),
            |path| crate::file_icons::file_icon(path, false, false, false, 15.0, color),
        ),
        "terminal" => icon(AleraIcon::Terminal, 15.0, color),
        // Flutter's workspace tab leading icon uses gitBranch for diff tabs;
        // the diff/compare glyph is reserved for the diff surface itself.
        "gitDiff" => icon(AleraIcon::GitBranch, 15.0, color),
        _ => icon(AleraIcon::File, 15.0, color),
    }
    .into_any_element()
}

pub(super) fn title_case_kind(kind: &str) -> &'static str {
    match kind {
        "terminal" => "Terminal",
        "editor" => "Editor",
        "markdownViewer" => "Markdown Preview",
        "gitDiff" => "Git Diff",
        "mobileEmulator" => "Mobile Device",
        _ => "Workbench",
    }
}
