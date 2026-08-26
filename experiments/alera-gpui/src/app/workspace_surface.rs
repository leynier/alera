use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, AnyElement, AppContext as _, Context, CursorStyle,
    DragMoveEvent, Entity, Image, ImageFormat, InteractiveElement as _, IntoElement, MouseButton,
    MouseDownEvent, MouseUpEvent, ParentElement as _, Render, SharedString,
    StatefulInteractiveElement as _, Styled as _, Timer, Window,
};
use gpui_component::scroll::{Scrollbar, ScrollbarShow};
use gpui_component::input::{InputEvent, InputState};
use regex::Regex;
use serde_json::Value;

use super::{AleraApp, ExplorerDragData, ExplorerMenuTarget};
use crate::activity::ContextPanel;
use crate::file_icons::file_icon;
use crate::icons::{icon, loading_indicator, AleraIcon};
use crate::model::WorkspaceTab;
use crate::theme;
use crate::workspace_service::{apply_explorer_git_status, ExplorerGitStatusSnapshot, FileEntry};

#[derive(Clone, Debug)]
pub(super) struct ExplorerRow {
    pub entry: FileEntry,
    pub depth: usize,
    pub expanded: bool,
}

struct DraggedExplorerFeedback {
    name: String,
    is_directory: bool,
    is_symlink: bool,
    depth: usize,
    expanded: bool,
    git_status: Option<String>,
    source_control_root: bool,
}

impl Render for DraggedExplorerFeedback {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        div()
            .relative()
            .flex()
            .items_center()
            .h(gpui::px(32.0))
            .w(gpui::px(300.0))
            .pr_2()
            .text_size(gpui::px(12.0))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_center()
                    .w(gpui::px(24.0 + self.depth as f32 * 16.0))
                    .h(gpui::px(24.0))
                    .when(self.is_directory, |expander| {
                        expander.child(icon(
                            if self.expanded {
                                AleraIcon::ChevronDown
                            } else {
                                AleraIcon::ChevronRight
                            },
                            16.0,
                            theme::text_muted(),
                        ))
                    }),
            )
            .child(file_icon(
                &self.name,
                self.is_directory,
                self.expanded,
                self.is_symlink,
                15.0,
                theme::text_muted(),
            ))
            .child(
                div()
                    .ml(gpui::px(6.0))
                    .flex_1()
                    .overflow_hidden()
                    .text_ellipsis()
                    .child(self.name.clone()),
            )
            .when_some(self.git_status.clone(), |item, status| {
                let color = if matches!(status.as_str(), "U" | "A") {
                    theme::success()
                } else {
                    theme::warning()
                };
                item.child(div().ml_2().text_xs().text_color(color).child(status))
            })
            .when(self.source_control_root, |item| {
                item.child(
                    div()
                        .ml_2()
                        .child(icon(AleraIcon::GitBranch, 14.0, theme::text_muted())),
                )
            })
    }
}

#[derive(Clone, Debug)]
pub(super) enum PreviewAsset {
    Markdown,
    Mermaid(Arc<Image>),
    Image(Arc<Image>),
}

enum OpenFileResult {
    Text {
        document: crate::workspace_service::EditorDocument,
        preview: Option<PreviewAsset>,
    },
    Image {
        relative_path: String,
        image: Arc<Image>,
    },
}

fn push_editor_tab_path(candidates: &mut Vec<String>, tab: &WorkspaceTab) {
    if !matches!(tab.kind.as_str(), "editor" | "markdownViewer") {
        return;
    }
    let Some(path) = tab
        .payload
        .get("filePath")
        .and_then(serde_json::Value::as_str)
    else {
        return;
    };
    if !candidates.iter().any(|candidate| candidate == path) {
        candidates.push(path.to_owned());
    }
}

impl AleraApp {
    pub(super) fn editor_input_for_path(&self, path: &str) -> Entity<InputState> {
        self.editor_inputs
            .get(path)
            .cloned()
            .unwrap_or_else(|| self.editor_input.clone())
    }

    fn ensure_editor_input(
        &mut self,
        path: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Entity<InputState> {
        if let Some(input) = self.editor_inputs.get(path) {
            return input.clone();
        }
        let input = if self.editor_inputs.is_empty() {
            self.editor_input.clone()
        } else {
            cx.new(|cx| {
                InputState::new(window, cx)
                    .code_editor("text")
                    .soft_wrap(true)
            })
        };
        if !self.editor_inputs.is_empty() {
            let path = path.to_owned();
            self._subscriptions.push(cx.subscribe_in(
                &input,
                window,
                move |this, input, event: &InputEvent, _, cx| {
                    if !matches!(event, InputEvent::Change)
                        || this.editor_input_syncing
                        || this.editor_document.is_none()
                        || this.opened_file_path.as_deref() != Some(path.as_str())
                    {
                        return;
                    }
                    this.editor_buffer_text
                        .insert(path.clone(), input.read(cx).value().to_string());
                    this.editor_dirty_paths.insert(path.clone());
                    this.editor_dirty = true;
                    cx.notify();
                },
            ));
        }
        self.editor_inputs.insert(path.to_owned(), input.clone());
        input
    }

    pub(super) fn refresh_local_activity(&mut self, cx: &mut Context<Self>) {
        match self.context_panel {
            ContextPanel::Explorer => self.load_root_directory(cx),
            ContextPanel::SourceControl => self.refresh_git(cx),
            ContextPanel::PullRequest => self.refresh_forge(cx),
            ContextPanel::Search => {}
        }
    }

    pub(super) fn ensure_explorer_watcher(&mut self, cx: &mut Context<Self>) {
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        let generation = self.explorer_watch_generation;
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        cx.spawn(async move |this, cx| loop {
            Timer::after(Duration::from_secs(2)).await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let should_continue = this
                .update(cx, |this, cx| {
                    if generation != this.explorer_watch_generation
                        || this.context_panel != ContextPanel::Explorer
                        || this.selected_workspace_id.as_deref() != Some(workspace_id.as_str())
                    {
                        return false;
                    }
                    if !this.explorer_busy {
                        this.load_root_directory(cx);
                    }
                    true
                })
                .unwrap_or(false);
            if !should_continue {
                break;
            }
        })
        .detach();
    }

    pub(super) fn reset_local_workspace(&mut self, _cx: &mut Context<Self>) {
        self.search_generation += 1;
        self.git_generation += 1;
        self.explorer_generation += 1;
        self.editor_generation += 1;
        self.search_busy = false;
        self.search_replacing = false;
        self.git_busy = false;
        self.explorer_busy = false;
        self.editor_busy = false;
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        self.explorer_scroll_handle
            .set_offset(gpui::point(gpui::px(0.0), gpui::px(0.0)));
        self.explorer_rows.clear();
        self.explorer_loaded_workspace_id = None;
        self.explorer_expanded_paths.clear();
        self.explorer_menu = None;
        self.explorer_selected_path = None;
        self.explorer_clipboard = None;
        self.explorer_drop_target = None;
        self.explorer_create_directory = None;
        self.explorer_rename_path = None;
        self.explorer_delete_path = None;
        self.terminal_scrollbar_drag = None;
        self.terminal_scrollbar_last_activity.clear();
        self.editor_document = None;
        self.editor_inputs.clear();
        self.editor_documents.clear();
        self.editor_load_error_paths.clear();
        self.editor_error_messages.clear();
        self.editor_buffer_text.clear();
        self.editor_dirty_paths.clear();
        self.editor_cursor_positions.clear();
        self.editor_input_syncing = false;
        self.opened_file_path = None;
        self.editor_loading_path = None;
        self.preview_asset = None;
        self.editor_preview_assets.clear();
        self.preview_scale = 1.0;
        self.preview_offset = gpui::point(gpui::px(0.0), gpui::px(0.0));
        self.preview_drag = None;
        self.show_preview = false;
        self.editor_dirty = false;
        self.editor_conflict = false;
        self.search_results = Default::default();
        self.search_error = None;
        self.search_error_is_query_failure = false;
        self.replace_confirmation = None;
        self.git_snapshot = Default::default();
        self.explorer_git_status = ExplorerGitStatusSnapshot::default();
        self.git_snapshot_loading = false;
        self.git_snapshot_error = None;
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        self.forge_snapshot = Default::default();
        self.forge_review_action = None;
        self.forge_review_action_menu_open = false;
        self.forge_review_confirmation = None;
        self.forge_review_editing = false;
        self.forge_review_base_menu_open = false;
        self.forge_comment_composing = false;
        self.forge_expanded_checks.clear();
        self.forge_collapsed_check_groups.clear();
        self.local_message = None;
        // Toasts are scoped to the workspace interaction that produced them.
        // Do not carry a stale filesystem error into the next workspace while
        // its contextual surface is being rehydrated.
        self.local_message_started_at = None;
        self.local_message_timer_message = None;
        self.toast_entries.clear();
    }

    pub(super) fn selected_workspace_path(&self) -> Option<String> {
        self.selected_workspace_id
            .as_deref()
            .and_then(|id| self.snapshot.workspace(id))
            .map(|workspace| workspace.path.clone())
    }

    pub(super) fn load_root_directory(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let explorer_scroll_offset = self.explorer_scroll_handle.offset();
        self.explorer_generation += 1;
        let generation = self.explorer_generation;
        self.explorer_busy = true;
        self.local_message = None;
        let service = self.workspace_service.clone();
        let hide_ignored = self.explorer_hide_ignored;
        let mut expanded_paths = self
            .explorer_expanded_paths
            .iter()
            .cloned()
            .collect::<Vec<_>>();
        expanded_paths.sort_by(|left, right| {
            left.split('/')
                .count()
                .cmp(&right.split('/').count())
                .then_with(|| left.cmp(right))
        });
        cx.spawn(async move |weak_this, cx| {
            let explorer_git_status = service
                .explorer_status_snapshot(workspace_path.clone())
                .await
                .unwrap_or_default();
            let result = service
                .list(workspace_path.clone(), String::new(), hide_ignored)
                .await;
            let Some(this) = weak_this.upgrade() else {
                return;
            };
            let root_applied = this
                .update(cx, |this, cx| {
                    if generation != this.explorer_generation {
                        return false;
                    }
                    match result {
                        Ok(entries) => {
                            this.explorer_loaded_workspace_id = Some(workspace_id.clone());
                            this.toast_entries
                                .retain(|(message, _)| !is_workspace_file_error(message));
                            this.explorer_git_status = explorer_git_status.clone();
                            this.explorer_rows =
                                apply_explorer_git_status(entries, &this.explorer_git_status)
                                    .into_iter()
                                    .map(|entry| ExplorerRow {
                                        entry,
                                        depth: 0,
                                        expanded: false,
                                    })
                                    .collect();
                            this.local_message = None;
                        }
                        Err(error) => {
                            // Flutter rebuilds an empty projection after a
                            // root refresh failure instead of leaving stale
                            // rows visible behind the error state.
                            this.explorer_rows.clear();
                            this.explorer_loaded_workspace_id = Some(workspace_id.clone());
                            this.explorer_git_status = ExplorerGitStatusSnapshot::default();
                            this.explorer_expanded_paths.clear();
                            this.local_message = Some(error.into());
                        }
                    }
                    cx.notify();
                    true
                })
                .unwrap_or(false);
            if !root_applied {
                return;
            }

            for relative_path in expanded_paths {
                let should_restore = this
                    .update(cx, |this, _| {
                        generation == this.explorer_generation
                            && this.explorer_rows.iter().any(|row| {
                                row.entry.relative_path == relative_path && row.entry.is_directory
                            })
                    })
                    .unwrap_or(false);
                if !should_restore {
                    continue;
                }
                let result = service
                    .list(workspace_path.clone(), relative_path.clone(), hide_ignored)
                    .await;
                let Some(this) = weak_this.upgrade() else {
                    return;
                };
                let applied = this
                    .update(cx, |this, cx| {
                        if generation != this.explorer_generation {
                            return false;
                        }
                        match result {
                            Ok(entries) => {
                                let entries =
                                    apply_explorer_git_status(entries, &this.explorer_git_status);
                                let Some(index) = this
                                    .explorer_rows
                                    .iter()
                                    .position(|row| row.entry.relative_path == relative_path)
                                else {
                                    this.explorer_expanded_paths.remove(&relative_path);
                                    return true;
                                };
                                let depth = this.explorer_rows[index].depth;
                                let end = this.explorer_rows[index + 1..]
                                    .iter()
                                    .position(|row| row.depth <= depth)
                                    .map(|offset| index + 1 + offset)
                                    .unwrap_or(this.explorer_rows.len());
                                this.explorer_rows.drain(index + 1..end);
                                this.explorer_rows[index].expanded = true;
                                let child_depth = depth + 1;
                                this.explorer_rows.splice(
                                    index + 1..index + 1,
                                    entries.into_iter().map(|entry| ExplorerRow {
                                        entry,
                                        depth: child_depth,
                                        expanded: false,
                                    }),
                                );
                                this.local_message = None;
                            }
                            Err(error) => this.local_message = Some(error.into()),
                        }
                        cx.notify();
                        true
                    })
                    .unwrap_or(false);
                if !applied {
                    return;
                }
            }

            let Some(this) = weak_this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.explorer_generation {
                    return;
                }
                this.explorer_busy = false;
                // File watchers refresh the rows every few seconds. Keep the
                // user's viewport stable across that rebuild; switching the
                // workspace explicitly resets it in `reset_local_workspace`.
                this.explorer_scroll_handle
                    .set_offset(explorer_scroll_offset);
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn toggle_directory(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let Some(index) = self
            .explorer_rows
            .iter()
            .position(|row| row.entry.relative_path == relative_path)
        else {
            return;
        };
        let depth = self.explorer_rows[index].depth;
        if self.explorer_rows[index].expanded {
            self.explorer_generation += 1;
            self.explorer_expanded_paths.remove(&relative_path);
            self.explorer_rows[index].expanded = false;
            let end = self.explorer_rows[index + 1..]
                .iter()
                .position(|row| row.depth <= depth)
                .map(|offset| index + 1 + offset)
                .unwrap_or(self.explorer_rows.len());
            self.explorer_rows.drain(index + 1..end);
            cx.notify();
            return;
        }

        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.explorer_generation += 1;
        let generation = self.explorer_generation;
        self.explorer_busy = true;
        let service = self.workspace_service.clone();
        let hide_ignored = self.explorer_hide_ignored;
        cx.spawn(async move |this, cx| {
            let result = service
                .list(workspace_path, relative_path.clone(), hide_ignored)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.explorer_generation {
                    return;
                }
                this.explorer_busy = false;
                match result {
                    Ok(entries) => {
                        let Some(index) = this
                            .explorer_rows
                            .iter()
                            .position(|row| row.entry.relative_path == relative_path)
                        else {
                            return;
                        };
                        let entries = apply_explorer_git_status(entries, &this.explorer_git_status);
                        this.explorer_rows[index].expanded = true;
                        this.explorer_expanded_paths.insert(relative_path.clone());
                        let child_depth = this.explorer_rows[index].depth + 1;
                        this.explorer_rows.splice(
                            index + 1..index + 1,
                            entries.into_iter().map(|entry| ExplorerRow {
                                entry,
                                depth: child_depth,
                                expanded: false,
                            }),
                        );
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn collapse_all_explorer_directories(&mut self, cx: &mut Context<Self>) {
        self.explorer_generation += 1;
        self.explorer_expanded_paths.clear();
        self.explorer_rows.retain(|row| row.depth == 0);
        for row in &mut self.explorer_rows {
            row.expanded = false;
        }
        cx.notify();
    }

    pub(super) fn toggle_explorer_ignored_files(&mut self, cx: &mut Context<Self>) {
        self.explorer_hide_ignored = !self.explorer_hide_ignored;
        self.persist_sidebar_view_prefs(cx);
        self.load_root_directory(cx);
    }

    pub(super) fn open_workspace_file(
        &mut self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.open_editor_tab(relative_path.clone(), cx);
        self.load_workspace_file(relative_path, window, cx);
    }

    pub(super) fn ensure_selected_editor_loaded(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let selected_file_path = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
            .and_then(|tab| tab.payload.get("filePath"))
            .and_then(Value::as_str);
        if self
            .editor_loading_path
            .as_deref()
            .is_some_and(|loading| Some(loading) == selected_file_path)
        {
            // Keep the current request alive while the selected tab still
            // points at the same path. A different tab must be allowed to
            // supersede it; load_workspace_file bumps editor_generation and
            // safely discards the old response.
            return;
        }
        let selected_tab = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected));
        let mut candidates = Vec::new();

        if let Some(tab) = selected_tab {
            push_editor_tab_path(&mut candidates, tab);
        }
        if let Some(layout) = self.snapshot.layout.as_ref() {
            for group in layout
                .groups
                .values()
                .filter(|group| group.id != layout.active_group_id)
            {
                if let Some(active_tab_id) = group.active_tab_id.as_deref() {
                    if let Some(tab) = self.snapshot.tabs.iter().find(|tab| tab.id == active_tab_id)
                    {
                        push_editor_tab_path(&mut candidates, tab);
                    }
                }
                for tab_id in &group.tab_ids {
                    if let Some(tab) = self.snapshot.tabs.iter().find(|tab| &tab.id == tab_id) {
                        push_editor_tab_path(&mut candidates, tab);
                    }
                }
            }
        }
        if candidates.is_empty() {
            for tab in &self.snapshot.tabs {
                push_editor_tab_path(&mut candidates, tab);
            }
        }

        for path in candidates {
            let is_selected = selected_tab
                .and_then(|tab| tab.payload.get("filePath"))
                .and_then(serde_json::Value::as_str)
                == Some(path.as_str());
            // A failed read must not be retried on every render. Keep the
            // error visible until an explicit tab activation/open retries it.
            if self.editor_load_error_paths.contains(&path) {
                continue;
            }
            if is_selected && self.opened_file_path.as_deref() != Some(path.as_str()) {
                self.load_workspace_file(path, window, cx);
                return;
            }
            if !self.editor_documents.contains_key(&path)
                && !self.editor_preview_assets.contains_key(&path)
            {
                self.load_workspace_file(path, window, cx);
                return;
            }
        }
    }

    pub(super) fn load_workspace_file(
        &mut self,
        relative_path: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.editor_load_error_paths.remove(&relative_path);
        self.editor_error_messages.remove(&relative_path);
        self.editor_generation += 1;
        let generation = self.editor_generation;
        self.editor_busy = true;
        self.editor_loading_path = Some(relative_path.clone());
        // Flutter keeps file-opening feedback inside the editor/image loading
        // surface. Do not leak an `Opening ...` global toast over a different
        // tab when the user switches panes before the read completes.
        self.local_message = None;
        self.preview_scale = 1.0;
        self.preview_offset = gpui::point(gpui::px(0.0), gpui::px(0.0));
        self.preview_drag = None;
        let service = self.workspace_service.clone();
        let requested_path = relative_path.clone();
        cx.spawn_in(window, async move |this, cx| {
            let extension = extension_for_path(&relative_path).to_owned();
            let result = if is_image_extension(&extension) {
                service
                    .image(workspace_path, relative_path.clone())
                    .await
                    .and_then(|image| {
                        image_format(&image.format).map(|format| OpenFileResult::Image {
                            relative_path,
                            image: Arc::new(Image::from_bytes(format, image.bytes)),
                        })
                    })
            } else {
                match service
                    .read(workspace_path.clone(), relative_path.clone())
                    .await
                {
                    Ok(document) if is_mermaid_extension(&extension) => service
                        .mermaid(workspace_path, relative_path)
                        .await
                        .map(|svg| OpenFileResult::Text {
                            document,
                            preview: Some(PreviewAsset::Mermaid(Arc::new(Image::from_bytes(
                                ImageFormat::Svg,
                                prepare_merman_svg_for_gpui(&svg).into_bytes(),
                            )))),
                        }),
                    Ok(document) => Ok(OpenFileResult::Text {
                        preview: (extension == "md" || extension == "mdx")
                            .then_some(PreviewAsset::Markdown),
                        document,
                    }),
                    Err(error) => Err(error),
                }
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update_in(cx, |this, window, cx| {
                if generation != this.editor_generation {
                    return;
                }
                this.editor_busy = false;
                match result {
                        Ok(OpenFileResult::Text { document, preview }) => {
                            let language = language_for_path(&document.relative_path);
                            let cached_path = document.relative_path.clone();
                            this.editor_load_error_paths.remove(&cached_path);
                            this.editor_error_messages.remove(&cached_path);
                        let editor_input =
                            this.ensure_editor_input(&cached_path, window, cx);
                        let display_content = this
                            .editor_buffer_text
                            .get(&cached_path)
                            .cloned()
                            .unwrap_or_else(|| document.display_content.clone());
                        this.editor_documents
                            .insert(cached_path.clone(), document.clone());
                        if let Some(asset) = preview.clone() {
                            this.editor_preview_assets
                                .insert(cached_path.clone(), asset);
                        } else {
                            this.editor_preview_assets.remove(&cached_path);
                        }
                        this.editor_input_syncing = true;
                        editor_input.update(cx, |input, cx| {
                            input.set_highlighter(language, cx);
                            input.set_value(display_content, window, cx);
                            if let Some((_, line, column, _)) = this
                                .pending_editor_cursor
                                .as_ref()
                                .filter(|(path, _, _, _)| path == &document.relative_path)
                            {
                                input.set_cursor_position(
                                    gpui_component::input::Position::new(
                                        *line as u32,
                                        *column as u32,
                                    ),
                                    window,
                                    cx,
                                );
                            } else if let Some((line, column)) =
                                this.editor_cursor_positions.get(&cached_path).copied()
                            {
                                input.set_cursor_position(
                                    gpui_component::input::Position::new(line, column),
                                    window,
                                    cx,
                                );
                            }
                        });
                        this.editor_input_syncing = false;
                        this.editor_loading_path = None;
                        if this
                            .pending_editor_cursor
                            .as_ref()
                            .is_some_and(|(path, _, _, _)| path == &document.relative_path)
                        {
                            let selection_length = this
                                .pending_editor_cursor
                                .take()
                                .map_or(0, |(_, _, _, length)| length);
                            let select_right = gpui::Keystroke::parse("shift-right")
                                .expect("shift-right must be a valid GPUI keystroke");
                            let editor_input = editor_input.clone();
                            window.on_next_frame(move |window, cx| {
                                editor_input.update(cx, |input, cx| input.focus(window, cx));
                                // The input needs one paint cycle to become the focused
                                // key context before selection keystrokes can reach it.
                                // Dispatching in this same callback moves the caret but
                                // drops the selection, so copy after opening a search match
                                // returns the user's previous clipboard contents.
                                window.on_next_frame(move |window, cx| {
                                    for _ in 0..selection_length {
                                        window.dispatch_keystroke(select_right.clone(), cx);
                                    }
                                });
                            });
                        }
                        let loaded_relative_path = document.relative_path.clone();
                        this.opened_file_path = Some(document.relative_path.clone());
                        this.editor_document = Some(document);
                        this.show_preview = this
                            .selected_tab_id
                            .as_ref()
                            .and_then(|selected| {
                                this.snapshot.tabs.iter().find(|tab| &tab.id == selected)
                            })
                            .is_some_and(|tab| tab.kind == "markdownViewer")
                            || this
                                .selected_tab_id
                                .as_ref()
                                .and_then(|selected| {
                                    this.snapshot.tabs.iter().find(|tab| &tab.id == selected)
                                })
                            .is_some_and(|tab| {
                                tab.kind == "editor"
                                    && tab.payload.get("fileRole").and_then(Value::as_str)
                                        == Some("mermanPreview")
                            });
                        this.preview_asset = preview;
                        this.editor_dirty = this.editor_dirty_paths.contains(&loaded_relative_path);
                        this.editor_conflict = false;
                        this.local_message = None;
                    }
                    Ok(OpenFileResult::Image {
                        relative_path,
                        image,
                    }) => {
                        this.editor_load_error_paths.remove(&relative_path);
                        this.editor_error_messages.remove(&relative_path);
                        this.editor_loading_path = None;
                        this.editor_buffer_text.remove(&relative_path);
                        this.editor_dirty_paths.remove(&relative_path);
                        this.editor_preview_assets
                            .insert(relative_path.clone(), PreviewAsset::Image(image.clone()));
                        this.opened_file_path = Some(relative_path);
                        this.editor_document = None;
                        this.preview_asset = Some(PreviewAsset::Image(image));
                        this.show_preview = true;
                        this.editor_dirty = false;
                        this.editor_conflict = false;
                        this.local_message = None;
                    }
                    Err(error) => {
                        this.editor_load_error_paths.insert(requested_path.clone());
                        this.editor_loading_path = None;
                        let message: SharedString = if is_image_extension(&extension) {
                            image_preview_error_message(&error)
                        } else {
                            editor_file_error_message(&error)
                        }
                        .into();
                        this.editor_error_messages
                            .insert(requested_path.clone(), message.clone());
                        this.local_message = Some(message);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn save_editor(&mut self, overwrite: bool, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        let Some(document) = self.editor_document.clone() else {
            return;
        };
        let editor_input = self.editor_input_for_path(&document.relative_path);
        let display_content = editor_input.read(cx).value().to_string();
        self.editor_generation += 1;
        let generation = self.editor_generation;
        self.editor_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .write(workspace_path, document, display_content, overwrite)
                .await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.editor_generation {
                    return;
                }
                this.editor_busy = false;
                match result {
                    Ok(document) => {
                        let path = document.relative_path.clone();
                        this.editor_documents.insert(path.clone(), document.clone());
                        this.editor_buffer_text.remove(&path);
                        this.editor_dirty_paths.remove(&path);
                        this.editor_document = Some(document);
                        this.editor_dirty = false;
                        this.editor_conflict = false;
                        this.local_message = Some(
                            if overwrite {
                                "File overwritten"
                            } else {
                                "File saved"
                            }
                            .into(),
                        );
                    }
                    Err(error) if super::editor_actions::is_editor_conflict(&error) => {
                        this.editor_conflict = true;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn render_explorer_panel(
        &self,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let rows = self
            .explorer_rows
            .iter()
            .enumerate()
            .map(|(index, row)| {
                let path = row.entry.relative_path.clone();
                let is_directory = row.entry.is_directory;
                let name = row.entry.name.clone();
                let expanded = row.expanded;
                let is_symlink = row.entry.is_symlink;
                let is_faint = row.entry.is_hidden || row.entry.is_protected;
                let status = row.entry.git_status.clone();
                let selected = self.explorer_selected_path.as_deref() == Some(path.as_str());
                let source_control_root = self.is_focused_source_control_root(&path);
                let click_path = path.clone();
                let menu_path = path.clone();
                let drop_path = path.clone();
                let drag_data = ExplorerDragData {
                    relative_path: path.clone(),
                    name: name.clone(),
                    is_directory,
                    is_symlink,
                    depth: row.depth,
                    expanded,
                    git_status: status.clone(),
                    source_control_root,
                };
                let drop_target = self.explorer_drop_target.as_deref() == Some(path.as_str());
                let mut item = div()
                    .id(("explorer-row", index))
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(gpui::px(32.0))
                    .pl(gpui::px(row.depth as f32 * 16.0))
                    .pr_2()
                    .text_size(gpui::px(12.0))
                    .cursor(CursorStyle::PointingHand)
                    .hover(|style| style.bg(theme::surface()))
                    .when(selected, |item| item.bg(theme::surface_raised()))
                    .when(drop_target, |item| {
                        item.bg(theme::surface_selected())
                            .border_l_1()
                            .border_color(theme::border())
                    })
                    .on_mouse_up(
                        gpui::MouseButton::Left,
                        cx.listener(move |this, event: &MouseUpEvent, window, cx| {
                            // The scrollbar is layered above the rows. GPUI's
                            // pointer-up can still bubble to the row when a
                            // thumb drag ends, so reserve the final 12 px of
                            // the window for scrollbar interaction and never
                            // open a file as a side effect of scrolling.
                            if event.position.x >= window.bounds().right() - gpui::px(12.0) {
                                cx.stop_propagation();
                                return;
                            }
                            this.select_explorer_entry(click_path.clone());
                            if is_directory {
                                this.toggle_directory(click_path.clone(), cx);
                            } else {
                                this.open_file_tab(click_path.clone(), cx);
                            }
                        }),
                    )
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(move |this, event: &MouseDownEvent, _, cx| {
                            this.show_explorer_menu(
                                ExplorerMenuTarget::Entry(menu_path.clone()),
                                event.position,
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
                    .on_drag(drag_data, |drag, _, _, cx| {
                        cx.new(|_| DraggedExplorerFeedback {
                            name: drag.name.clone(),
                            is_directory: drag.is_directory,
                            is_symlink: drag.is_symlink,
                            depth: drag.depth,
                            expanded: drag.expanded,
                            git_status: drag.git_status.clone(),
                            source_control_root: drag.source_control_root,
                        })
                    })
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .flex_1()
                            .overflow_hidden()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .w(gpui::px(24.0))
                                    .h(gpui::px(24.0))
                                    .when(is_directory, |expander| {
                                        expander.child(icon(
                                            if expanded {
                                                AleraIcon::ChevronDown
                                            } else {
                                                AleraIcon::ChevronRight
                                            },
                                            16.0,
                                            theme::text_muted(),
                                        ))
                                    }),
                            )
                            .child(file_icon(
                                &name,
                                is_directory,
                                expanded,
                                is_symlink,
                                15.0,
                                theme::text_muted(),
                            ))
                            .child(
                                div()
                                    .ml(gpui::px(6.0))
                                    .flex_1()
                                    .overflow_hidden()
                                    .text_ellipsis()
                                    .when(is_faint, |label| label.text_color(theme::text_faint()))
                                    .child(name),
                            ),
                    )
                    .when_some(status, |item, status| {
                        let color = if matches!(status.as_str(), "U" | "A") {
                            theme::success()
                        } else {
                            theme::warning()
                        };
                        item.child(div().ml_2().text_xs().text_color(color).child(status))
                    })
                    .when(source_control_root, |item| {
                        item.child(
                            div()
                                .id(("explorer-source-root", index))
                                .ml_2()
                                .tooltip(|_, cx| {
                                    cx.new(|_| {
                                        gpui_component::tooltip::Tooltip::new("Source Control Root")
                                    })
                                    .into()
                                })
                                .child(icon(AleraIcon::GitBranch, 14.0, theme::text_muted())),
                        )
                    });
                if is_directory {
                    let drag_target_path = drop_path.clone();
                    let drop_target_path = drop_path.clone();
                    item = item
                        .drag_over::<ExplorerDragData>(|style, _, _, _| {
                            style.bg(theme::surface_selected())
                        })
                        .on_drag_move(cx.listener(
                            move |this, event: &DragMoveEvent<ExplorerDragData>, _, cx| {
                                let drag = event.drag(cx);
                                if this
                                    .can_drop_explorer_entry(&drag.relative_path, &drag_target_path)
                                {
                                    if this.explorer_drop_target.as_deref()
                                        != Some(drag_target_path.as_str())
                                    {
                                        this.explorer_drop_target = Some(drag_target_path.clone());
                                        cx.notify();
                                    }
                                } else if this.explorer_drop_target.as_deref()
                                    == Some(drag_target_path.as_str())
                                {
                                    this.explorer_drop_target = None;
                                    cx.notify();
                                }
                            },
                        ))
                        .on_drop(cx.listener(move |this, drag: &ExplorerDragData, _, cx| {
                            this.drop_explorer_entry(drag, drop_target_path.clone(), cx);
                        }));
                }
                item
            })
            .collect::<Vec<_>>();
        let empty_state = if self.explorer_busy && rows.is_empty() {
            Some(
                div()
                    .absolute()
                    .inset_0()
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_sm()
                    .text_color(theme::text_muted())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap_2()
                            .child(loading_indicator(15.0, theme::text_muted()))
                            .child("Loading..."),
                    )
                    .into_any_element(),
            )
        } else {
            // Flutter leaves a successfully empty tree, and also leaves the
            // tree blank after a root read fails while the normalized error is
            // shown by the global toast. Rendering a second centered error
            // card here diverges from that contract and exposes filesystem
            // details in the panel.
            None
        };

        div()
            .relative()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .min_h_0()
            .child(
                div()
                    .id("explorer-tree")
                    .relative()
                    .flex_1()
                    .min_h_0()
                    .track_scroll(&self.explorer_scroll_handle)
                    .overflow_y_scroll()
                    .bg(theme::surface())
                    .py_1()
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(|this, event: &MouseDownEvent, _, cx| {
                            this.show_explorer_menu(
                                ExplorerMenuTarget::Background,
                                event.position,
                                cx,
                            );
                            cx.stop_propagation();
                        }),
                    )
                    .on_mouse_up(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.clear_explorer_drop_target(cx)),
                    )
                    .on_mouse_up_out(
                        MouseButton::Left,
                        cx.listener(|this, _, _, cx| this.clear_explorer_drop_target(cx)),
                    )
                    .children(rows),
            )
            .child(
                Scrollbar::vertical(&self.explorer_scroll_handle)
                    .id("explorer-scrollbar")
                    .scrollbar_show(ScrollbarShow::Always),
            )
            // Flutter replaces the tree with a centered loader/error when no
            // rows are available. Keep the tree's background hit target, but
            // overlay the state across the full panel instead of allocating a
            // second flex child and vertically halving the empty surface.
            .when_some(empty_state, |panel, state| panel.child(state))
            .into_any_element()
    }
}

fn language_for_path(path: &str) -> SharedString {
    let language = match extension_for_path(path) {
        "rs" => "rust",
        "dart" => "dart",
        "js" | "jsx" => "javascript",
        "ts" | "tsx" => "typescript",
        "py" => "python",
        "go" => "go",
        "json" => "json",
        "yaml" | "yml" => "yaml",
        "toml" => "toml",
        "md" | "mdx" => "markdown",
        "html" => "html",
        "css" => "css",
        "sh" | "zsh" | "bash" => "bash",
        "zig" => "zig",
        _ => "text",
    };
    language.into()
}

fn extension_for_path(path: &str) -> &str {
    Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .unwrap_or_default()
}

fn is_mermaid_extension(extension: &str) -> bool {
    extension == "mmd" || extension == "mermain" || extension == "mermaid"
}

fn is_image_extension(extension: &str) -> bool {
    matches!(
        extension,
        "avif"
            | "jpg"
            | "jpeg"
            | "png"
            | "gif"
            | "webp"
            | "tif"
            | "tiff"
            | "tga"
            | "dds"
            | "bmp"
            | "ico"
            | "hdr"
            | "exr"
            | "pbm"
            | "pam"
            | "ppm"
            | "pgm"
            | "ff"
            | "farbfeld"
            | "qoi"
            | "svg"
    )
}

fn image_format(format: &str) -> Result<ImageFormat, String> {
    match format {
        "png" => Ok(ImageFormat::Png),
        "jpeg" => Ok(ImageFormat::Jpeg),
        "webp" => Ok(ImageFormat::Webp),
        "gif" => Ok(ImageFormat::Gif),
        "svg" => Ok(ImageFormat::Svg),
        "bmp" => Ok(ImageFormat::Bmp),
        "tiff" => Ok(ImageFormat::Tiff),
        _ => Err(format!("Unsupported Workspace Image Format: {format}")),
    }
}

fn prepare_merman_svg_for_gpui(svg: &str) -> String {
    let mut next = svg
        .replace("background-color:white", "background-color:#101010")
        .replace(
            "background-color:rgba(255, 255, 255, 0.5)",
            "background-color:#242424",
        )
        .replace("fill:#eee;", "fill:#242424;")
        .replace("stroke:#999;", "stroke:#323232;")
        .replace("fill:#666", "fill:#A1A1A1")
        .replace("stroke:#666", "stroke:#A1A1A1")
        .replace("fill:#333333;", "fill:#A1A1A1;")
        .replace("stroke:#333333;", "stroke:#A1A1A1;")
        .replace("fill:#333;", "fill:#F5F5F5;")
        .replace("color:#333;", "color:#F5F5F5;")
        .replace("fill:white", "fill:#242424")
        .replace("color:#000000", "color:#F5F5F5")
        .replace("fill:#000000", "fill:#F5F5F5")
        .replace("fill=\"#333\"", "fill=\"#F5F5F5\"")
        .replace("fill=\"#333333\"", "fill=\"#F5F5F5\"")
        .replace("stroke=\"#333333\"", "stroke=\"#A1A1A1\"")
        .replace("fill=\"#000\"", "fill=\"#A1A1A1\"")
        .replace("fill=\"#000000\"", "fill=\"#A1A1A1\"")
        .replace("stroke=\"#000\"", "stroke=\"#A1A1A1\"")
        .replace("stroke=\"#000000\"", "stroke=\"#A1A1A1\"");
    for tag in ["rect", "circle", "ellipse", "polygon", "path"] {
        next = replace_merman_class_attributes(
            &next,
            tag,
            "basic label-container",
            Some("#242424"),
            Some("#323232"),
        );
    }
    next = replace_merman_class_attributes(
        &next,
        "path",
        "flowchart-link",
        Some("none"),
        Some("#A1A1A1"),
    );
    for tag in ["path", "polygon", "circle"] {
        next = replace_merman_class_attributes(
            &next,
            tag,
            "arrowMarkerPath",
            Some("#A1A1A1"),
            Some("#A1A1A1"),
        );
    }
    next
}

fn replace_merman_class_attributes(
    svg: &str,
    tag_name: &str,
    class_name: &str,
    fill: Option<&str>,
    stroke: Option<&str>,
) -> String {
    let pattern = format!(
        r#"<{tag}\b[^>]*class="[^"]*\b{class}\b[^"]*"[^>]*>"#,
        tag = regex::escape(tag_name),
        class = regex::escape(class_name),
    );
    let matcher = Regex::new(&pattern).expect("Merman SVG class pattern is valid");
    matcher
        .replace_all(svg, |captures: &regex::Captures<'_>| {
            let mut tag = captures[0].to_owned();
            if let Some(fill) = fill {
                tag = replace_merman_attribute(&tag, "fill", fill);
            }
            if let Some(stroke) = stroke {
                tag = replace_merman_attribute(&tag, "stroke", stroke);
            }
            tag
        })
        .into_owned()
}

fn replace_merman_attribute(tag: &str, name: &str, value: &str) -> String {
    let pattern = format!(r#"\s{name}="[^"]*""#, name = regex::escape(name));
    let matcher = Regex::new(&pattern).expect("Merman SVG attribute pattern is valid");
    if matcher.is_match(tag) {
        matcher
            .replace(tag, format!(" {name}=\"{value}\""))
            .into_owned()
    } else {
        let insert_at = if tag.ends_with("/>") {
            tag.len() - 2
        } else {
            tag.len() - 1
        };
        format!(
            "{} {name}=\"{value}\"{}",
            &tag[..insert_at],
            &tag[insert_at..]
        )
    }
}

fn image_preview_error_message(error: &str) -> String {
    let normalized = error.to_ascii_lowercase();
    if normalized.contains("outside") {
        "Image is outside the workspace".to_owned()
    } else if normalized.contains("invalid") {
        "Image path is invalid".to_owned()
    } else if normalized.contains("not found") || normalized.contains("no such file") {
        "Image not found".to_owned()
    } else {
        "Image cannot be opened".to_owned()
    }
}

fn is_workspace_file_error(message: &str) -> bool {
    matches!(
        message.trim().to_ascii_lowercase().as_str(),
        "file not found"
            | "file operation failed"
            | "file is outside the workspace"
            | "file cannot be edited"
            | "item not found"
            | "item already exists"
            | "path is protected"
            | "path is outside the workspace"
            | "operation is unsupported"
            | "file changed on disk"
    )
}

fn editor_file_error_message(error: &str) -> String {
    let normalized = error.to_ascii_lowercase();
    if normalized.contains("unsupported") {
        "File cannot be edited".to_owned()
    } else if normalized.contains("not found") || normalized.contains("no such file") {
        "File not found".to_owned()
    } else if normalized.contains("outside") {
        "File is outside the workspace".to_owned()
    } else if normalized.contains("protected") {
        "File is protected".to_owned()
    } else if normalized.contains("conflict") || normalized.contains("changed on disk") {
        "File changed on disk".to_owned()
    } else {
        "File operation failed".to_owned()
    }
}

#[cfg(test)]
mod merman_svg_tests {
    use super::prepare_merman_svg_for_gpui;

    #[test]
    fn prepares_merman_svg_for_flutter_dark_theme() {
        let svg = r##"<svg><rect class="basic label-container" fill="#000000"/><path class="flowchart-link"/><path class="arrowMarkerPath" fill="#000000"/><text fill="#333333">Preview</text></svg>"##;
        let prepared = prepare_merman_svg_for_gpui(svg);
        assert!(prepared.contains("class=\"basic label-container\" fill=\"#242424\""));
        assert!(prepared.contains("class=\"flowchart-link\" fill=\"none\" stroke=\"#A1A1A1\""));
        assert!(prepared.contains("class=\"arrowMarkerPath\" fill=\"#A1A1A1\" stroke=\"#A1A1A1\""));
        assert!(prepared.contains("<text fill=\"#F5F5F5\">"));
    }
}

#[cfg(test)]
mod image_preview_tests {
    use super::image_preview_error_message;

    #[test]
    fn image_preview_errors_match_flutter_copy() {
        assert_eq!(
            image_preview_error_message("Workspace Image Is Outside The Workspace."),
            "Image is outside the workspace"
        );
        assert_eq!(
            image_preview_error_message("Invalid Workspace Image Path."),
            "Image path is invalid"
        );
        assert_eq!(
            image_preview_error_message(
                "Workspace Image Is Unavailable: No such file or directory"
            ),
            "Image not found"
        );
        assert_eq!(
            image_preview_error_message("Workspace Image Is Unsupported."),
            "Image cannot be opened"
        );
    }
}

#[cfg(test)]
mod editor_file_error_tests {
    use super::editor_file_error_message;

    #[test]
    fn editor_errors_use_flutter_copy() {
        assert_eq!(
            editor_file_error_message("readme.md: No such file or directory (os error 2)"),
            "File not found"
        );
        assert_eq!(
            editor_file_error_message("Workspace File Conflict: File changed on disk"),
            "File changed on disk"
        );
        assert_eq!(
            editor_file_error_message("workspace path is outside the workspace"),
            "File is outside the workspace"
        );
        assert_eq!(
            editor_file_error_message("unexpected filesystem failure"),
            "File operation failed"
        );
    }
}
