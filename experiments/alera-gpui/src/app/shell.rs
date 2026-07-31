use gpui::{
    div, prelude::FluentBuilder as _, px, Context, CursorStyle, InteractiveElement as _,
    IntoElement, ParentElement as _, Render, SharedString, StatefulInteractiveElement as _,
    Styled as _, Window,
};

use super::AleraApp;
use crate::activity::Activity;
use crate::theme;

impl AleraApp {
    fn render_activity_rail(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .flex_col()
            .items_center()
            .w(theme::activity_rail_width())
            .h_full()
            .border_r_1()
            .border_color(theme::border())
            .bg(theme::app_background())
            .pt_2()
            .gap_1()
            .children(
                Activity::ALL
                    .into_iter()
                    .enumerate()
                    .map(|(index, activity)| {
                        let selected = self.activity == activity;
                        div()
                            .id(("activity", index))
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(38.0))
                            .h(px(38.0))
                            .rounded_md()
                            .text_lg()
                            .cursor(CursorStyle::PointingHand)
                            .when(selected, |item| {
                                item.bg(theme::surface_selected())
                                    .text_color(theme::accent())
                            })
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.select_activity(activity, cx);
                            }))
                            .child(activity.icon())
                    }),
            )
    }

    fn render_sidebar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let mut rows = Vec::new();
        for project in &self.snapshot.projects {
            rows.push(
                div()
                    .px_3()
                    .pt_3()
                    .pb_1()
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(format!("{} · {}", project.name, project.kind))
                    .into_any_element(),
            );
            for workspace in &project.workspaces {
                let workspace_id = workspace.id.clone();
                let selected = self.selected_workspace_id.as_deref() == Some(workspace.id.as_str());
                rows.push(
                    div()
                        .id(SharedString::from(workspace.id.clone()))
                        .mx_2()
                        .px_2()
                        .py_2()
                        .rounded_md()
                        .cursor(CursorStyle::PointingHand)
                        .when(selected, |item| item.bg(theme::surface_selected()))
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.select_workspace(workspace_id.clone(), cx);
                        }))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .justify_between()
                                .child(workspace.name.clone())
                                .when(workspace.is_pinned, |item| {
                                    item.child(
                                        div().text_xs().text_color(theme::warning()).child("◆"),
                                    )
                                }),
                        )
                        .child(
                            div()
                                .mt_1()
                                .text_xs()
                                .text_color(theme::text_muted())
                                .child(format!(
                                    "{} · {}{}",
                                    workspace
                                        .branch
                                        .clone()
                                        .unwrap_or_else(|| workspace.kind.clone()),
                                    workspace.status,
                                    if workspace.tag_names.is_empty() {
                                        String::new()
                                    } else {
                                        format!(" · {}", workspace.tag_names.join(", "))
                                    }
                                )),
                        )
                        .into_any_element(),
                );
            }
        }

        div()
            .flex()
            .flex_col()
            .w(theme::sidebar_width())
            .h_full()
            .border_r_1()
            .border_color(theme::border())
            .bg(theme::surface())
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::title_bar_height())
                    .px_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .child(
                        div()
                            .text_sm()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child("Projects"),
                    )
                    .child(div().text_color(theme::text_muted()).child("＋")),
            )
            .child(div().flex_1().overflow_hidden().py_2().children(rows))
    }
}

impl Render for AleraApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.sync_terminal_size(window, cx);
        div()
            .flex()
            .flex_col()
            .size_full()
            .bg(theme::app_background())
            .text_color(theme::text())
            .font_family("Inter")
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::title_bar_height())
                    .px_3()
                    .border_b_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(
                                div()
                                    .text_color(theme::accent())
                                    .font_weight(gpui::FontWeight::BOLD)
                                    .child("A"),
                            )
                            .child("Alera GPUI"),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child(self.connection_label.clone()),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(self.render_activity_rail(cx))
                    .child(self.render_sidebar(cx))
                    .child(self.render_workbench(window, cx)),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(theme::status_bar_height())
                    .px_3()
                    .border_t_1()
                    .border_color(theme::border())
                    .bg(theme::surface())
                    .text_xs()
                    .text_color(theme::text_muted())
                    .child(
                        self.error
                            .clone()
                            .unwrap_or_else(|| SharedString::from("GPUI POC")),
                    )
                    .child(format!(
                        "{} Projects · {} Tabs · {}",
                        self.snapshot.projects.len(),
                        self.snapshot.tabs.len(),
                        if self.snapshot.layout.is_some() {
                            "Layout Loaded"
                        } else {
                            "Default Layout"
                        }
                    )),
            )
    }
}
