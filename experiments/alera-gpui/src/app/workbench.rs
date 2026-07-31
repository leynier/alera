use gpui::{
    div, prelude::FluentBuilder as _, Context, CursorStyle, InteractiveElement as _, IntoElement,
    ParentElement as _, StatefulInteractiveElement as _, Styled as _, Window,
};

use super::AleraApp;
use crate::activity::Activity;
use crate::theme;

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
        let content = if matches!(
            self.activity,
            Activity::Explorer
                | Activity::Search
                | Activity::SourceControl
                | Activity::PullRequests
                | Activity::AiText
        ) {
            self.render_local_surface(window, cx)
        } else if self.activity.uses_runtime_catalog() {
            self.render_runtime_feature(cx)
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

        div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .bg(theme::app_background())
            .child(
                div()
                    .flex()
                    .items_center()
                    .h(theme::tab_bar_height())
                    .border_b_1()
                    .border_color(theme::border())
                    .children(self.snapshot.tabs.iter().enumerate().map(|(index, tab)| {
                        let tab_id = tab.id.clone();
                        let selected = self.selected_tab_id.as_deref() == Some(tab.id.as_str());
                        div()
                            .id(("tab", index))
                            .flex()
                            .items_center()
                            .h_full()
                            .px_3()
                            .gap_2()
                            .border_r_1()
                            .border_color(theme::border())
                            .cursor(CursorStyle::PointingHand)
                            .when(selected, |item| item.bg(theme::surface_raised()))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.selected_tab_id = Some(tab_id.clone());
                                this.ensure_selected_terminal(cx);
                                cx.notify();
                            }))
                            .child(tab_kind_icon(&tab.kind))
                            .child(tab.title.clone())
                    }))
                    .child(div().px_3().text_color(theme::text_muted()).child("＋")),
            )
            .child(content)
    }
}

fn tab_kind_icon(kind: &str) -> &'static str {
    match kind {
        "terminal" => "›_",
        "editor" => "≡",
        "markdownViewer" => "M",
        "gitDiff" => "±",
        _ => "◇",
    }
}

fn title_case_kind(kind: &str) -> &'static str {
    match kind {
        "terminal" => "Terminal",
        "editor" => "Editor",
        "markdownViewer" => "Markdown Preview",
        "gitDiff" => "Git Diff",
        "mobileEmulator" => "Mobile Device",
        _ => "Workbench",
    }
}
