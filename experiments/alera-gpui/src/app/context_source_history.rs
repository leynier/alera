use chrono::{DateTime, Local};
use gpui::{
    div, prelude::FluentBuilder as _, px, AnyElement, AppContext as _, ClipboardItem, Context,
    CursorStyle, DragMoveEvent, Empty, InteractiveElement as _, IntoElement, KeyDownEvent,
    MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, ParentElement as _, Role,
    StatefulInteractiveElement as _, Styled as _,
};

use super::context_source_control_actions::source_icon_button_with_enabled;
use super::source_history_graph::{
    build_history_graph_view_models, history_graph, HistoryGraphKind, HistoryGraphRow,
};
use super::state_types::{GitHistoryResizeDrag, GitHistoryResizeState};
use super::AleraApp;
use crate::file_icons::file_icon;
use crate::icons::{icon, AleraIcon};
use crate::theme;
use crate::workspace_git::{GitCommitChange, GitHistoryItem, GitHistoryRef};
use gpui_component::tooltip::Tooltip;

#[derive(Clone, Debug)]
pub(super) struct SourceHistoryActionMenu {
    commit_id: String,
}

impl AleraApp {
    pub(super) fn source_history_resize_handle(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("source-history-resize")
            .flex_shrink_0()
            .h(px(4.0))
            .cursor(CursorStyle::ResizeUpDown)
            .bg(theme::border_subtle())
            .hover(|style| style.bg(theme::border()))
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(|this, event: &MouseDownEvent, _, cx| {
                    this.git_history_resize = Some(GitHistoryResizeState {
                        start_y: event.position.y,
                        initial_height: this.git_history_height,
                    });
                    cx.notify();
                    cx.stop_propagation();
                }),
            )
            .on_drag(GitHistoryResizeDrag, |_, _, _, cx| cx.new(|_| Empty))
            .on_drag_move(cx.listener(
                |this, event: &DragMoveEvent<GitHistoryResizeDrag>, _, cx| {
                    this.update_source_history_resize(&event.event, cx);
                },
            ))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(Self::finish_source_history_resize),
            )
            .on_mouse_up_out(
                MouseButton::Left,
                cx.listener(Self::finish_source_history_resize),
            )
            .into_any_element()
    }

    fn update_source_history_resize(&mut self, event: &MouseMoveEvent, cx: &mut Context<Self>) {
        let Some(state) = self.git_history_resize else {
            return;
        };
        if !event.dragging() {
            return;
        }
        let delta = (event.position.y - state.start_y) / px(1.0);
        self.git_history_height = (state.initial_height - delta).clamp(96.0, 520.0);
        cx.notify();
    }

    fn finish_source_history_resize(
        &mut self,
        _: &MouseUpEvent,
        _: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        if self.git_history_resize.take().is_some() {
            cx.notify();
        }
    }

    pub(super) fn source_history_footer(&self, cx: &mut Context<Self>) -> AnyElement {
        div()
            .id("toggle-git-history")
            .focusable()
            .tab_stop(true)
            .role(Role::Button)
            .aria_label(if self.git_history_expanded {
                "Hide Commits"
            } else {
                "Show Commits"
            })
            .aria_expanded(self.git_history_expanded)
            .flex()
            .flex_shrink_0()
            .items_center()
            .h(px(40.0))
            .px_3()
            .gap(px(6.0))
            .border_t_1()
            .border_color(theme::border_subtle())
            .cursor(CursorStyle::PointingHand)
            .on_click(cx.listener(|this, _, _, cx| {
                this.git_history_expanded = !this.git_history_expanded;
                if this.git_history_expanded {
                    this.git_history_loaded_once = true;
                }
                cx.notify();
            }))
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
            .when(self.git_history_loaded_once, |footer| {
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
            .when(!self.git_history_loaded_once, |footer| {
                footer.child(div().flex_1())
            })
            .child({
                let loading = self.git_snapshot_loading;
                source_icon_button_with_enabled(
                    "source-history-refresh",
                    if loading {
                        AleraIcon::Loading
                    } else {
                        AleraIcon::GitRefresh
                    },
                    false,
                    !loading && !self.git_busy,
                )
                .aria_label("Refresh Commits")
                .tooltip(|_, cx| cx.new(|_| Tooltip::new("Refresh Commits")).into())
                .when(!loading && !self.git_busy, |button| {
                    button.on_click(cx.listener(|this, _, _, cx| {
                        // The refresh icon lives inside the expandable footer. Keep the
                        // action from bubbling into the footer toggle, matching Flutter's
                        // independent refresh button behavior.
                        cx.stop_propagation();
                        this.git_history_loaded_once = true;
                        this.refresh_git(cx);
                    }))
                })
            })
            .into_any_element()
    }

    pub(super) fn source_history_panel(&self, cx: &mut Context<Self>) -> AnyElement {
        let view_models = build_history_graph_view_models(&self.git_snapshot);
        let empty_message = self
            .git_snapshot_error
            .as_ref()
            .cloned()
            .unwrap_or_else(|| "No Commits Yet".into());
        div()
            .id("source-history-list")
            .role(Role::List)
            .aria_label("Commits")
            .relative()
            .flex()
            .flex_col()
            .flex_shrink_0()
            .h(px(self.git_history_height))
            .overflow_y_scroll()
            .border_b_1()
            .border_color(theme::border_subtle())
            .when(
                view_models.is_empty() && self.git_snapshot_loading,
                |panel| {
                    panel.child(
                        div()
                            .id("source-history-loading")
                            .role(Role::ProgressIndicator)
                            .aria_label("Loading Commits")
                            .flex()
                            .flex_1()
                            .items_center()
                            .justify_center()
                            .child(icon(AleraIcon::Loading, 18.0, theme::text_muted())),
                    )
                },
            )
            .when(
                view_models.is_empty() && !self.git_snapshot_loading,
                |panel| {
                    let empty_label = empty_message.clone();
                    panel.child(
                        div()
                            .id("source-history-empty")
                            .role(Role::Label)
                            .aria_label(empty_label)
                            .flex()
                            .flex_1()
                            .items_center()
                            .justify_center()
                            .text_sm()
                            .text_color(theme::text_muted())
                            .child(empty_message),
                    )
                },
            )
            .when(!view_models.is_empty(), |panel| {
                panel.children(view_models.iter().map(|view_model| {
                    self.source_history_item(
                        &view_model.item,
                        &view_model.graph,
                        view_model.kind,
                        cx,
                    )
                }))
            })
            .when(
                !view_models.is_empty() && self.git_snapshot_loading,
                |panel| {
                    panel.child(div().absolute().top(px(8.0)).right(px(8.0)).child(icon(
                        AleraIcon::Loading,
                        12.0,
                        theme::text_muted(),
                    )))
                },
            )
            .into_any_element()
    }

    fn source_history_item(
        &self,
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
        let menu_open = self
            .source_history_action_menu
            .as_ref()
            .is_some_and(|menu| menu.commit_id == item.full_id);
        div()
            .relative()
            .flex()
            .flex_col()
            .child(
                div()
                    .id(gpui::SharedString::from(format!(
                        "source-history-row-{}",
                        item.full_id
                    )))
                    .when(!boundary, |row| {
                        row.focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label(item.subject.clone())
                            .aria_expanded(expanded)
                    })
                    .flex()
                    .items_center()
                    .h(px(28.0))
                    .px_2()
                    .gap(px(4.0))
                    .when(!boundary, |row| {
                        row.cursor(CursorStyle::PointingHand)
                            .hover(|style| style.bg(theme::surface_selected()))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.toggle_source_history_item(full_id.clone(), cx);
                            }))
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
                                .id(gpui::SharedString::from(format!(
                                    "source-history-actions-{}",
                                    item.full_id
                                )))
                                .focusable()
                                .tab_stop(true)
                                .role(Role::Button)
                                .aria_label(gpui::SharedString::from(format!(
                                    "Commit Actions For {}",
                                    item.subject
                                )))
                                .flex()
                                .items_center()
                                .justify_center()
                                .w(px(24.0))
                                .h(px(24.0))
                                .rounded_md()
                                .cursor(CursorStyle::PointingHand)
                                .hover(|style| style.bg(theme::surface_raised()))
                                .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                                    cx.stop_propagation();
                                })
                                .on_click(cx.listener(move |this, _, window, cx| {
                                    cx.stop_propagation();
                                    this.open_source_history_action_menu(
                                        menu_commit_id.clone(),
                                        window,
                                        cx,
                                    );
                                }))
                                .child(icon(AleraIcon::More, 12.0, theme::text_faint())),
                        )
                    }),
            )
            .when(expanded, |container| {
                container.child(self.source_history_details(item, loading, cx))
            })
            .when(menu_open, |container| {
                container.child(self.source_history_action_menu(cx))
            })
            .into_any_element()
    }

    fn source_history_details(
        &self,
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
                        .text_xs()
                        .text_color(theme::text_muted())
                        .child("Loading Files..."),
                )
            })
            .when_some(files, |details, files| {
                details.children(
                    files
                        .iter()
                        .take(12)
                        .map(|change| self.source_history_file_row(item, change, cx)),
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
                            .id(gpui::SharedString::from(format!(
                                "source-history-open-all-{}",
                                item.full_id
                            )))
                            .focusable()
                            .tab_stop(true)
                            .role(Role::Button)
                            .aria_label("Open All Changes")
                            .flex()
                            .items_center()
                            .h(px(28.0))
                            .gap_2()
                            .text_xs()
                            .text_color(theme::text_muted())
                            .cursor(CursorStyle::PointingHand)
                            .hover(|style| style.text_color(theme::text()))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.open_git_commit_diff_tab(
                                    None,
                                    None,
                                    "all",
                                    open_all_commit_id.clone(),
                                    open_all_subject.clone(),
                                    cx,
                                );
                            }))
                            .child(icon(AleraIcon::External, 13.0, theme::text_muted()))
                            .child("Open All Changes"),
                    )
                },
            )
            .into_any_element()
    }

    fn source_history_file_row(
        &self,
        item: &GitHistoryItem,
        change: &GitCommitChange,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let path = change.path.clone();
        let old_path = change.old_path.clone();
        let commit_id = item.full_id.clone();
        let subject = item.subject.clone();
        history_file_row(
            gpui::SharedString::from(format!(
                "source-history-file-{}-{}",
                item.full_id, change.path
            )),
            change,
        )
        .cursor(CursorStyle::PointingHand)
        .on_click(cx.listener(move |this, _, _, cx| {
            let permanent = this.should_keep_git_preview(format!("commit:{}:{}", commit_id, path));
            this.open_git_commit_diff_preview_tab(
                Some(path.clone()),
                old_path.clone(),
                commit_id.clone(),
                subject.clone(),
                permanent,
                cx,
            );
        }))
        .into_any_element()
    }

    fn open_source_history_action_menu(
        &mut self,
        commit_id: String,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        self.source_history_action_menu = Some(SourceHistoryActionMenu { commit_id });
        self.source_history_menu_previous_focus = window.focused(cx);
        self.source_history_menu_highlighted = 0;
        self.source_history_menu_focus.focus(window, cx);
        cx.notify();
    }

    fn dismiss_source_history_action_menu(
        &mut self,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        self.source_history_action_menu = None;
        if let Some(focus) = self.source_history_menu_previous_focus.take() {
            focus.focus(window, cx);
        }
        cx.notify();
    }

    fn handle_source_history_menu_key(
        &mut self,
        event: &KeyDownEvent,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        match event.keystroke.key.as_str() {
            "escape" => self.dismiss_source_history_action_menu(window, cx),
            "down" | "up" => {
                self.source_history_menu_highlighted =
                    (self.source_history_menu_highlighted + 1) % 2;
                cx.notify();
            }
            "home" => {
                self.source_history_menu_highlighted = 0;
                cx.notify();
            }
            "end" => {
                self.source_history_menu_highlighted = 1;
                cx.notify();
            }
            "enter" | "space" => self.activate_source_history_menu_item(
                self.source_history_menu_highlighted,
                window,
                cx,
            ),
            _ => return,
        }
        cx.stop_propagation();
    }

    fn activate_source_history_menu_item(
        &mut self,
        index: usize,
        window: &mut gpui::Window,
        cx: &mut Context<Self>,
    ) {
        let Some(menu) = self.source_history_action_menu.as_ref() else {
            return;
        };
        let Some(item) = self
            .git_snapshot
            .history
            .iter()
            .find(|item| item.full_id == menu.commit_id)
        else {
            return;
        };
        let (value, feedback) = if index == 0 {
            (item.full_id.clone(), "Commit Hash Copied")
        } else {
            (
                if item.message.trim().is_empty() {
                    item.subject.clone()
                } else {
                    item.message.clone()
                },
                "Commit Message Copied",
            )
        };
        self.dismiss_source_history_action_menu(window, cx);
        cx.write_to_clipboard(ClipboardItem::new_string(value));
        self.local_message = Some(feedback.into());
        cx.notify();
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
            this.update(cx, |this, cx| {
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
            .track_focus(&self.source_history_menu_focus)
            .role(Role::Menu)
            .aria_label("Commit Actions")
            .absolute()
            .right(px(8.0))
            // The menu is rendered inside the selected commit row. Anchor it
            // to that row rather than to the history panel's bottom so it
            // follows the clicked commit while the list is scrolled.
            .top(px(-6.0))
            .w(px(190.0))
            .occlude()
            .rounded_lg()
            .border_1()
            .border_color(theme::border())
            .bg(theme::surface_raised())
            .shadow_lg()
            .py_1()
            .on_mouse_down(gpui::MouseButton::Left, |_, _, cx| {
                cx.stop_propagation();
            })
            .on_mouse_down_out(cx.listener(|this, _, window, cx| {
                this.dismiss_source_history_action_menu(window, cx);
            }))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                this.handle_source_history_menu_key(event, window, cx);
            }))
            .child(
                history_action_row(
                    "history-copy-hash",
                    AleraIcon::GitBranch,
                    "Copy Commit Hash",
                )
                .aria_selected(self.source_history_menu_highlighted == 0)
                .when(self.source_history_menu_highlighted == 0, |row| {
                    row.bg(theme::surface_selected())
                })
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    cx.write_to_clipboard(ClipboardItem::new_string(hash.clone()));
                    this.dismiss_source_history_action_menu(window, cx);
                    this.local_message = Some("Commit Hash Copied".into());
                    cx.notify();
                })),
            )
            .child(
                history_action_row(
                    "history-copy-message",
                    AleraIcon::Copy,
                    "Copy Commit Message",
                )
                .aria_selected(self.source_history_menu_highlighted == 1)
                .when(self.source_history_menu_highlighted == 1, |row| {
                    row.bg(theme::surface_selected())
                })
                .on_click(cx.listener(move |this, _, window, cx| {
                    cx.stop_propagation();
                    cx.write_to_clipboard(ClipboardItem::new_string(message.clone()));
                    this.dismiss_source_history_action_menu(window, cx);
                    this.local_message = Some("Commit Message Copied".into());
                    cx.notify();
                })),
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
        .focusable()
        .tab_stop(true)
        .role(Role::MenuItem)
        .aria_label(label)
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

fn history_file_row(id: gpui::SharedString, change: &GitCommitChange) -> gpui::Stateful<gpui::Div> {
    div()
        .id(id)
        .focusable()
        .tab_stop(true)
        .role(Role::ListBoxOption)
        .aria_label(gpui::SharedString::from(format!(
            "{} {}",
            change.path,
            status_letter(&change.status)
        )))
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
