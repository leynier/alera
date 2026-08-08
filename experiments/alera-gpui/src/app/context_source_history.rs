use chrono::{DateTime, Local};
use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, ClipboardItem, Context, CursorStyle,
    InteractiveElement as _, IntoElement, MouseDownEvent, ParentElement as _,
    StatefulInteractiveElement as _, Styled as _,
};

use super::context_source_control_actions::source_icon_button;
use super::source_history_graph::{
    build_history_graph_view_models, history_graph, HistoryGraphKind, HistoryGraphRow,
};
use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::{GitCommitChange, GitHistoryItem, GitHistoryRef};

#[derive(Clone, Debug)]
pub(super) struct SourceHistoryActionMenu {
    commit_id: String,
}

impl AleraApp {
    pub(super) fn source_history_footer(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("toggle-git-history")
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(40.0))
            .px_3()
            .gap(px(6.0))
            .border_t_1()
            .border_color(theme::border_subtle())
            .cursor(CursorStyle::PointingHand)
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(|this, _, _, cx| {
                    this.git_history_expanded = !this.git_history_expanded;
                    cx.notify();
                }),
            )
            .child(icon(
                if self.git_history_expanded {
                    AleraIcon::ChevronDown
                } else {
                    AleraIcon::ChevronRight
                },
                14.0,
                theme::text_muted(),
            ))
            .child(
                div()
                    .text_xs()
                    .font_weight(gpui::FontWeight::SEMIBOLD)
                    .child("COMMITS"),
            )
            .when(!self.git_snapshot.history.is_empty(), |footer| {
                footer.child(
                    div()
                        .ml(px(6.0))
                        .flex_1()
                        .text_xs()
                        .text_color(theme::text_faint())
                        .child(if self.git_snapshot.history_metadata.has_more {
                            format!("{}+", self.git_snapshot.history.len())
                        } else {
                            self.git_snapshot.history.len().to_string()
                        }),
                )
            })
            .when(self.git_snapshot.history.is_empty(), |footer| {
                footer.child(div().flex_1())
            })
            .child(
                source_icon_button("source-history-refresh", AleraIcon::GitRefresh, false)
                    .on_mouse_down(
                        gpui::MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.refresh_git(cx)),
                    ),
            )
            .into_any_element()
    }

    pub(super) fn source_history_panel(&self, cx: &mut Context<Self>) -> AnyElement {
        let view_models = build_history_graph_view_models(&self.git_snapshot);
        div()
            .id("source-history-list")
            .flex()
            .flex_col()
            .flex_shrink_0()
            .h(px(264.0))
            .overflow_y_scroll()
            .border_b_1()
            .border_color(theme::border_subtle())
            .children(view_models.iter().enumerate().map(|(index, view_model)| {
                self.source_history_item(
                    index,
                    &view_model.item,
                    &view_model.graph,
                    view_model.kind,
                    cx,
                )
            }))
            .into_any_element()
    }

    fn source_history_item(
        &self,
        index: usize,
        item: &GitHistoryItem,
        graph: &HistoryGraphRow,
        kind: HistoryGraphKind,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let boundary = kind.boundary();
        let expanded = !boundary && self.source_history_expanded_ids.contains(&item.full_id);
        let loading = self.source_history_loading_ids.contains(&item.full_id);
        let full_id = item.full_id.clone();
        let menu_commit_id = item.full_id.clone();
        div()
            .flex()
            .flex_col()
            .child(
                div()
                    .id(("source-history-row", index))
                    .flex()
                    .items_center()
                    .h(px(28.0))
                    .px_2()
                    .gap(px(4.0))
                    .when(!boundary, |row| {
                        row.cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_selected()))
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    this.toggle_source_history_item(full_id.clone(), cx);
                                }),
                            )
                    })
                    .child(history_graph(graph))
                    .when(!boundary, |row| {
                        row.child(icon(
                            if expanded {
                                AleraIcon::ChevronDown
                            } else {
                                AleraIcon::ChevronRight
                            },
                            11.0,
                            theme::text_faint(),
                        ))
                    })
                    .when(boundary, |row| row.child(div().w(px(11.0))))
                    .child(
                        div()
                            .flex_1()
                            .overflow_hidden()
                            .text_ellipsis()
                            .text_xs()
                            .when(boundary, |text| text.text_color(theme::text_muted()))
                            .child(item.subject.clone()),
                    )
                    .children(item.references.iter().take(2).map(history_ref_badge))
                    .when(item.references.len() > 2, |row| {
                        row.child(
                            div()
                                .text_size(px(9.0))
                                .text_color(theme::text_faint())
                                .child(format!("+{}", item.references.len() - 2)),
                        )
                    })
                    .when(!boundary, |row| {
                        row.child(
                            div()
                                .id(("source-history-actions", index))
                                .flex()
                                .items_center()
                                .justify_center()
                                .w(px(24.0))
                                .h(px(24.0))
                                .rounded_md()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_raised()))
                                .on_mouse_down(
                                    gpui::MouseButton::Left,
                                    cx.listener(move |this, _: &MouseDownEvent, _, cx| {
                                        cx.stop_propagation();
                                        this.source_history_action_menu =
                                            Some(SourceHistoryActionMenu {
                                                commit_id: menu_commit_id.clone(),
                                            });
                                        cx.notify();
                                    }),
                                )
                                .child(icon(AleraIcon::More, 12.0, theme::text_faint())),
                        )
                    }),
            )
            .when(expanded, |container| {
                container.child(self.source_history_details(index, item, loading, cx))
            })
            .into_any_element()
    }

    fn source_history_details(
        &self,
        index: usize,
        item: &GitHistoryItem,
        loading: bool,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let files = self.source_history_files.get(&item.full_id);
        let metadata = match (&item.author, item.timestamp_millis) {
            (Some(author), Some(timestamp)) => {
                format!("{author} - {}", format_history_time(timestamp))
            }
            (Some(author), None) => author.clone(),
            (None, Some(timestamp)) => format_history_time(timestamp),
            (None, None) => String::new(),
        };
        let open_all_commit_id = item.full_id.clone();
        let open_all_subject = item.subject.clone();
        div()
            .flex()
            .flex_col()
            .ml(px(28.0))
            .mr_2()
            .pb_1()
            .when(!metadata.is_empty(), |details| {
                details.child(
                    div()
                        .h(px(22.0))
                        .flex()
                        .items_center()
                        .text_size(px(9.0))
                        .text_color(theme::text_faint())
                        .child(metadata),
                )
            })
            .when(loading, |details| {
                details.child(
                    div()
                        .h(px(26.0))
                        .flex()
                        .items_center()
                        .gap_2()
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child(icon(AleraIcon::Loading, 13.0, theme::text_muted()))
                        .child("Loading Changes"),
                )
            })
            .when_some(files, |details, files| {
                details.children(
                    files
                        .iter()
                        .take(12)
                        .enumerate()
                        .map(|(row_index, change)| {
                            self.source_history_file_row(index, row_index, item, change, cx)
                        }),
                )
            })
            .when(
                matches!(files, Some(files) if files.is_empty()),
                |details| {
                    details.child(
                        div()
                            .h(px(26.0))
                            .flex()
                            .items_center()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .child("No Changed Files"),
                    )
                },
            )
            .when(
                matches!(files, Some(files) if files.len() > 12),
                |details| {
                    details.child(
                        div()
                            .h(px(26.0))
                            .flex()
                            .items_center()
                            .text_xs()
                            .text_color(theme::text_faint())
                            .child(format!(
                                "{} More Files",
                                files.map_or(0, |items| items.len().saturating_sub(12))
                            )),
                    )
                },
            )
            .when(
                matches!(files, Some(files) if !files.is_empty()),
                |details| {
                    details.child(
                        div()
                            .id(("source-history-open-all", index))
                            .flex()
                            .items_center()
                            .h(px(28.0))
                            .gap_2()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.text_color(theme::text()))
                            .on_mouse_down(
                                gpui::MouseButton::Left,
                                cx.listener(move |this, _, _, cx| {
                                    this.open_git_commit_diff_tab(
                                        None,
                                        None,
                                        "all",
                                        open_all_commit_id.clone(),
                                        open_all_subject.clone(),
                                        cx,
                                    );
                                }),
                            )
                            .child(icon(AleraIcon::External, 13.0, theme::text_muted()))
                            .child("Open All Changes"),
                    )
                },
            )
            .into_any_element()
    }

    fn source_history_file_row(
        &self,
        group_index: usize,
        row_index: usize,
        item: &GitHistoryItem,
        change: &GitCommitChange,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let path = change.path.clone();
        let old_path = change.old_path.clone();
        let commit_id = item.full_id.clone();
        let subject = item.subject.clone();
        history_file_row(group_index * 1000 + row_index, change)
            .cursor(CursorStyle::PointingHand)
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.open_git_commit_diff_tab(
                        Some(path.clone()),
                        old_path.clone(),
                        "file",
                        commit_id.clone(),
                        subject.clone(),
                        cx,
                    );
                }),
            )
            .into_any_element()
    }

    fn toggle_source_history_item(&mut self, commit_id: String, cx: &mut Context<Self>) {
        if !self.source_history_expanded_ids.insert(commit_id.clone()) {
            self.source_history_expanded_ids.remove(&commit_id);
            cx.notify();
            return;
        }
        if self.source_history_files.contains_key(&commit_id)
            || self.source_history_loading_ids.contains(&commit_id)
        {
            cx.notify();
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.source_history_loading_ids.insert(commit_id.clone());
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .git_commit_compare(workspace_path, commit_id.clone())
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                this.source_history_loading_ids.remove(&commit_id);
                match result {
                    Ok(files) => {
                        this.source_history_files.insert(commit_id, files);
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn source_history_action_menu(&self, cx: &mut Context<Self>) -> AnyElement {
        let Some(menu) = &self.source_history_action_menu else {
            return div().into_any_element();
        };
        let Some(item) = self
            .git_snapshot
            .history
            .iter()
            .find(|item| item.full_id == menu.commit_id)
        else {
            return div().into_any_element();
        };
        let hash = item.full_id.clone();
        let message = if item.message.trim().is_empty() {
            item.subject.clone()
        } else {
            item.message.clone()
        };
        div()
            .id("source-history-action-menu")
            .absolute()
            .right(px(8.0))
            .bottom(px(48.0))
            .w(px(190.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .py_1()
            .on_mouse_down_out(cx.listener(|this, _, _, cx| {
                this.source_history_action_menu = None;
                cx.notify();
            }))
            .child(
                history_action_row(
                    "history-copy-hash",
                    AleraIcon::GitBranch,
                    "Copy Commit Hash",
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.write_to_clipboard(ClipboardItem::new_string(hash.clone()));
                        this.source_history_action_menu = None;
                        this.local_message = Some("Commit Hash Copied".into());
                        cx.notify();
                    }),
                ),
            )
            .child(
                history_action_row(
                    "history-copy-message",
                    AleraIcon::Copy,
                    "Copy Commit Message",
                )
                .on_mouse_down(
                    gpui::MouseButton::Left,
                    cx.listener(move |this, _, _, cx| {
                        cx.write_to_clipboard(ClipboardItem::new_string(message.clone()));
                        this.source_history_action_menu = None;
                        this.local_message = Some("Commit Message Copied".into());
                        cx.notify();
                    }),
                ),
            )
            .into_any_element()
    }
}

fn history_action_row(
    id: &'static str,
    kind: AleraIcon,
    label: &'static str,
) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .flex()
        .items_center()
        .h(px(30.0))
        .px_2()
        .gap_2()
        .cursor(CursorStyle::PointingHand)
        .hover(|style| style.bg(theme::surface_selected()))
        .text_size(px(13.0))
        .child(icon(kind, 16.0, theme::text_muted()))
        .child(label)
}

fn history_ref_badge(item_ref: &GitHistoryRef) -> gpui::Div {
    let color = match item_ref.color {
        Some(crate::workspace_git::GitHistoryColor::Reference) => theme::success(),
        Some(crate::workspace_git::GitHistoryColor::RemoteReference) => theme::info(),
        Some(crate::workspace_git::GitHistoryColor::BaseReference) => theme::warning(),
        _ if item_ref.category.eq_ignore_ascii_case("Branches") => theme::success(),
        _ if item_ref.category.eq_ignore_ascii_case("RemoteBranches") => theme::info(),
        _ => theme::warning(),
    };
    div()
        .max_w(px(78.0))
        .overflow_hidden()
        .text_ellipsis()
        .rounded_full()
        .border_1()
        .border_color(color)
        .px(px(5.0))
        .py(px(1.0))
        .text_size(px(9.0))
        .text_color(color)
        .child(item_ref.name.clone())
}

fn history_file_row(index: usize, change: &GitCommitChange) -> gpui::Stateful<gpui::Div> {
    div()
        .id(("source-history-file", index))
        .flex()
        .items_center()
        .h(px(25.0))
        .gap(px(6.0))
        .hover(|style| style.bg(theme::surface_selected()))
        .child(file_icon(
            &change.path,
            false,
            false,
            false,
            13.0,
            theme::text_muted(),
        ))
        .child(
            div()
                .flex_1()
                .overflow_hidden()
                .text_ellipsis()
                .text_xs()
                .child(change.path.clone()),
        )
        .when_some(change.added, |row, added| {
            row.child(
                div()
                    .text_size(px(9.0))
                    .text_color(theme::success())
                    .child(format!("+{added}")),
            )
        })
        .when_some(change.removed, |row, removed| {
            row.child(
                div()
                    .text_size(px(9.0))
                    .text_color(theme::danger())
                    .child(format!("-{removed}")),
            )
        })
        .child(
            div()
                .w(px(10.0))
                .text_xs()
                .text_color(theme::warning())
                .child(status_letter(&change.status)),
        )
}

fn status_letter(status: &str) -> &'static str {
    match status.to_ascii_lowercase().as_str() {
        "added" | "untracked" => "A",
        "deleted" => "D",
        "renamed" => "R",
        _ => "M",
    }
}

fn format_history_time(timestamp_millis: i64) -> String {
    DateTime::from_timestamp_millis(timestamp_millis)
        .map(|time| {
            time.with_timezone(&Local)
                .format("%Y-%m-%d %H:%M")
                .to_string()
        })
        .unwrap_or_default()
}
