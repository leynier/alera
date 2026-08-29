use std::io::Cursor;
use std::path::{Component, Path};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use gpui::{
    div, prelude::FluentBuilder as _, uniform_list, AnyElement, AppContext as _, ClickEvent,
    Context, CursorStyle, DragMoveEvent, Entity, Image, ImageFormat, InteractiveElement as _,
    IntoElement, MouseButton, MouseDownEvent, ParentElement as _, Render, Role, SharedString,
    StatefulInteractiveElement as _, Styled as _, Window,
};
use gpui_component::input::{EditorState, InputEvent};
use gpui_component::scroll::{Scrollbar, ScrollbarMode};
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
                item.child(div().ml_2().child(icon(
                    AleraIcon::GitBranch,
                    14.0,
                    theme::text_muted(),
                )))
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
        markdown_content: Option<String>,
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

fn resolve_markdown_asset_urls(
    markdown: &str,
    workspace_path: &str,
    document_relative_path: &str,
) -> String {
    static IMAGE_DESTINATION: OnceLock<Regex> = OnceLock::new();
    let image_destination = IMAGE_DESTINATION.get_or_init(|| {
        Regex::new(r#"(!\[[^\]]*\]\(\s*)([^)\s]+)([^)]*\))"#)
            .expect("markdown image destination regex must be valid")
    });
    let document_parent = Path::new(document_relative_path)
        .parent()
        .unwrap_or_else(|| Path::new(""));
    image_destination
        .replace_all(markdown, |captures: &regex::Captures<'_>| {
            let destination = captures.get(2).map_or("", |capture| capture.as_str());
            if destination.is_empty()
                || destination.starts_with('/')
                || destination.starts_with('#')
                || destination.starts_with("data:")
                || destination.contains("://")
            {
                return captures
                    .get(0)
                    .map_or("", |capture| capture.as_str())
                    .to_owned();
            }
            let relative = document_parent.join(destination);
            if relative
                .components()
                .any(|component| !matches!(component, Component::Normal(_) | Component::CurDir))
            {
                return captures
                    .get(0)
                    .map_or("", |capture| capture.as_str())
                    .to_owned();
            }
            let Some(workspace) = Path::new(workspace_path).canonicalize().ok() else {
                return captures
                    .get(0)
                    .map_or("", |capture| capture.as_str())
                    .to_owned();
            };
            let Some(absolute) = Path::new(workspace_path)
                .join(relative)
                .canonicalize()
                .ok()
                .filter(|path| path.starts_with(&workspace) && path.is_file())
            else {
                return captures
                    .get(0)
                    .map_or("", |capture| capture.as_str())
                    .to_owned();
            };
            crate::markdown_images::register_local_image_path(absolute.clone());
            format!(
                "{}{}{}",
                captures.get(1).map_or("", |capture| capture.as_str()),
                local_file_uri(&absolute),
                captures.get(3).map_or("", |capture| capture.as_str()),
            )
        })
        .into_owned()
}

fn local_file_uri(path: &Path) -> String {
    let path = path.to_string_lossy().replace('\\', "/");
    let mut encoded = String::with_capacity(path.len() + 8);
    encoded.push_str(if path.starts_with('/') {
        "file://"
    } else {
        "file:///"
    });
    for byte in path.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'-' | b'_' | b'.' | b'~' | b':') {
            encoded.push(char::from(byte));
        } else {
            use std::fmt::Write as _;
            let _ = write!(encoded, "%{byte:02X}");
        }
    }
    encoded
}

impl AleraApp {
    pub(super) fn cache_markdown_preview_content(&mut self, path: &str, content: &str) {
        if !matches!(extension_for_path(path), "md" | "mdx") {
            return;
        }
        let Some(workspace_path) = self.selected_workspace_path() else {
            return;
        };
        self.markdown_preview_content.insert(
            path.to_owned(),
            resolve_markdown_asset_urls(content, &workspace_path, path),
        );
    }

    pub(super) fn editor_input_for_path(&self, path: &str) -> Entity<EditorState> {
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
    ) -> Entity<EditorState> {
        if let Some(input) = self.editor_inputs.get(path) {
            return input.clone();
        }
        let input = if self.editor_inputs.is_empty() {
            self.editor_input.clone()
        } else {
            cx.new(|cx| {
                EditorState::new(window, cx)
                    .language("text")
                    .soft_wrap(true)
            })
        };
        if !self.editor_inputs.is_empty() {
            let path = path.to_owned();
            self._subscriptions.push(cx.subscribe_in(
                &input,
                window,
                move |this, input, event: &InputEvent, _, cx| {
                    if matches!(event, InputEvent::Focus) {
                        this.activate_editor_path_on_focus(&path, cx);
                        return;
                    }
                    if !matches!(event, InputEvent::Change)
                        || this.editor_input_syncing
                        || this.editor_document.is_none()
                        || this.opened_file_path.as_deref() != Some(path.as_str())
                    {
                        return;
                    }
                    let content = input.read(cx).value().to_string();
                    this.editor_buffer_text
                        .insert(path.clone(), content.clone());
                    this.cache_markdown_preview_content(&path, &content);
                    this.editor_dirty_paths.insert(path.clone());
                    this.editor_dirty = true;
                    this.schedule_editor_autosave(cx);
                    cx.notify();
                },
            ));
        }
        self.editor_inputs.insert(path.to_owned(), input.clone());
        input
    }

    pub(super) fn activate_editor_path_on_focus(&mut self, path: &str, cx: &mut Context<Self>) {
        let tab_id = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| {
                matches!(tab.kind.as_str(), "editor" | "markdownViewer")
                    && tab.payload.get("filePath").and_then(Value::as_str) == Some(path)
            })
            .map(|tab| tab.id.clone());
        if let Some(tab_id) =
            tab_id.filter(|tab_id| self.selected_tab_id.as_deref() != Some(tab_id.as_str()))
        {
            self.activate_workspace_tab(tab_id, cx);
        }
    }

    pub(super) fn refresh_local_activity(&mut self, cx: &mut Context<Self>) {
        match self.context_panel {
            ContextPanel::Explorer => self.load_root_directory(cx),
            ContextPanel::SourceControl => self.refresh_git(cx),
            ContextPanel::PullRequest => self.refresh_forge(cx),
            ContextPanel::Search => {},
            ContextPanel::AgentCanvas => self.refresh_agent_canvas(cx),
        }
    }

    pub(super) fn ensure_explorer_watcher(&mut self, cx: &mut Context<Self>) {
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        let generation = self.explorer_watch_generation;
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        cx.spawn(async move |this, cx| loop {
            cx.background_executor().timer(Duration::from_secs(2)).await;
            let Some(this) = this.upgrade() else {
                break;
            };
            let should_continue = this.update(cx, |this, cx| {
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
            });
            if !should_continue {
                break;
            }
        })
        .detach();
    }

    pub(super) fn reset_local_workspace(&mut self, cx: &mut Context<Self>) {
        self.cancel_active_workspace_search(cx);
        self.search_generation += 1;
        self.git_generation += 1;
        self.explorer_generation += 1;
        self.editor_generation += 1;
        self.editor_autosave_generation = self.editor_autosave_generation.wrapping_add(1);
        self.search_busy = false;
        self.search_replacing = false;
        self.git_busy = false;
        self.explorer_busy = false;
        self.editor_busy = false;
        self.explorer_watch_generation = self.explorer_watch_generation.wrapping_add(1);
        self.explorer_scroll_handle
            .0
            .borrow()
            .base_handle
            .set_offset(gpui::point(gpui::px(0.0), gpui::px(0.0)));
        self.explorer_rows.clear();
        self.explorer_loaded_workspace_id = None;
        self.explorer_expanded_paths.clear();
        self.explorer_menu = None;
        self.explorer_selected_path = None;
        self.explorer_clipboard = None;
        self.explorer_drop_target = None;
        self.explorer_pointer_down = None;
        self.explorer_pointer_dragged = false;
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
        self.markdown_preview_content.clear();
        self.preview_transforms.clear();
        self.preview_drag = None;
        self.show_preview = false;
        self.editor_dirty = false;
        self.editor_conflict = false;
        self.search_results = Default::default();
        self.search_error = None;
        self.search_error_is_query_failure = false;
        self.git_snapshot = Default::default();
        self.explorer_git_status = ExplorerGitStatusSnapshot::default();
        self.git_snapshot_loading = false;
        self.git_snapshot_error = None;
        self.git_diff_loading_tab = None;
        self.git_diff_loaded_tab = None;
        self.git_diff_errors.clear();
        self.git_diff_image_sides.clear();
        self.git_diff_image_loading.clear();
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
        let explorer_scroll_offset = self.explorer_scroll_handle.0.borrow().base_handle.offset();
        self.explorer_generation += 1;
        let generation = self.explorer_generation;
        self.explorer_busy = true;
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
            let root_applied = this.update(cx, |this, cx| {
                if generation != this.explorer_generation {
                    return false;
                }
                match result {
                    Ok(entries) => {
                        this.explorer_loaded_workspace_id = Some(workspace_id.clone());
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
            });
            if !root_applied {
                return;
            }

            for relative_path in expanded_paths {
                let should_restore = this.update(cx, |this, _| {
                    generation == this.explorer_generation
                        && this.explorer_rows.iter().any(|row| {
                            row.entry.relative_path == relative_path && row.entry.is_directory
                        })
                });
                if !should_restore {
                    continue;
                }
                let result = service
                    .list(workspace_path.clone(), relative_path.clone(), hide_ignored)
                    .await;
                let Some(this) = weak_this.upgrade() else {
                    return;
                };
                let applied = this.update(cx, |this, cx| {
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
                        }
                        Err(error) => this.local_message = Some(error.into()),
                    }
                    cx.notify();
                    true
                });
                if !applied {
                    return;
                }
            }

            let Some(this) = weak_this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if generation != this.explorer_generation {
                    return;
                }
                this.explorer_busy = false;
                // File watchers refresh the rows every few seconds. Keep the
                // user's viewport stable across that rebuild; switching the
                // workspace explicitly resets it in `reset_local_workspace`.
                this.explorer_scroll_handle
                    .0
                    .borrow()
                    .base_handle
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
            this.update(cx, |this, cx| {
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
        if self.editor_loading_path.is_some() {
            // Only one request owns the shared editor generation at a time.
            // Cancelling a pane's restore from the next render leaves that
            // pane permanently empty, so let the current request settle and
            // continue with the next active pane on the following frame.
            return;
        }
        let selected_tab = self
            .selected_tab_id
            .as_ref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| &tab.id == selected))
            .cloned();
        let selected_file_path = selected_tab
            .as_ref()
            .and_then(|tab| tab.payload.get("filePath"))
            .and_then(Value::as_str)
            .map(str::to_owned);
        let mut candidates = Vec::new();

        if let Some(tab) = selected_tab.as_ref() {
            push_editor_tab_path(&mut candidates, tab);
        }
        if let Some(layout) = self.snapshot.layout.as_ref() {
            for group in layout
                .groups
                .values()
                .filter(|group| group.id != layout.active_group_id)
            {
                if let Some(active_tab_id) = group.active_tab_id.as_deref() {
                    if let Some(tab) = self
                        .snapshot
                        .tabs
                        .iter()
                        .find(|tab| tab.id == active_tab_id)
                    {
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
            let is_selected = selected_file_path.as_deref() == Some(path.as_str());
            // A failed read must not be retried on every render. Keep the
            // error visible until an explicit tab activation/open retries it.
            if self.editor_load_error_paths.contains(&path) {
                continue;
            }
            if !self.editor_documents.contains_key(&path)
                && !self.editor_preview_assets.contains_key(&path)
            {
                self.load_workspace_file(path, window, cx);
                return;
            }
            if is_selected && self.opened_file_path.as_deref() != Some(path.as_str()) {
                self.sync_selected_editor_from_cache();
            }
        }
    }

    pub(super) fn sync_selected_editor_from_cache(&mut self) {
        let Some((path, is_preview_kind)) = self
            .selected_tab_id
            .as_deref()
            .and_then(|selected| self.snapshot.tabs.iter().find(|tab| tab.id == selected))
            .and_then(|tab| {
                let path = tab.payload.get("filePath").and_then(Value::as_str)?;
                let is_preview_kind = tab.kind == "markdownViewer"
                    || tab.payload.get("fileRole").and_then(Value::as_str) == Some("mermanPreview");
                Some((path.to_owned(), is_preview_kind))
            })
        else {
            return;
        };
        let preview = self.editor_preview_assets.get(&path).cloned();
        let document = self.editor_documents.get(&path).cloned();
        if document.is_none() && preview.is_none() {
            return;
        }
        let is_preview_tab =
            is_preview_kind || matches!(preview.as_ref(), Some(PreviewAsset::Image(_)));
        let path_changed = self.opened_file_path.as_deref() != Some(path.as_str());
        self.opened_file_path = Some(path.clone());
        self.editor_document = document;
        self.preview_asset = preview;
        self.show_preview = is_preview_tab;
        self.editor_dirty = self.editor_dirty_paths.contains(&path);
        if path_changed {
            self.editor_conflict = false;
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
        self.editor_autosave_generation = self.editor_autosave_generation.wrapping_add(1);
        self.editor_generation += 1;
        let generation = self.editor_generation;
        self.editor_busy = true;
        self.editor_loading_path = Some(relative_path.clone());
        // Flutter keeps file-opening feedback inside the editor/image loading
        // surface. Do not leak an `Opening ...` global toast over a different
        // tab when the user switches panes before the read completes.
        self.local_message = None;
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
                        validate_workspace_image(&image.format, &image.bytes)?;
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
                        .mermaid(workspace_path.clone(), relative_path)
                        .await
                        .map(|svg| OpenFileResult::Text {
                            document,
                            preview: Some(PreviewAsset::Mermaid(Arc::new(Image::from_bytes(
                                ImageFormat::Svg,
                                prepare_merman_svg_for_gpui(&svg).into_bytes(),
                            )))),
                            markdown_content: None,
                        }),
                    Ok(document) => {
                        let is_markdown = extension == "md" || extension == "mdx";
                        let markdown_content = is_markdown.then(|| {
                            resolve_markdown_asset_urls(
                                &document.display_content,
                                &workspace_path,
                                &document.relative_path,
                            )
                        });
                        Ok(OpenFileResult::Text {
                            preview: is_markdown.then_some(PreviewAsset::Markdown),
                            document,
                            markdown_content,
                        })
                    }
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
                    Ok(OpenFileResult::Text {
                        document,
                        preview,
                        markdown_content,
                    }) => {
                        let language = language_for_path(&document.relative_path);
                        let cached_path = document.relative_path.clone();
                        this.editor_load_error_paths.remove(&cached_path);
                        this.editor_error_messages.remove(&cached_path);
                        let editor_input = this.ensure_editor_input(&cached_path, window, cx);
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
                        if let Some(content) = markdown_content {
                            this.markdown_preview_content
                                .insert(cached_path.clone(), content);
                        } else {
                            this.markdown_preview_content.remove(&cached_path);
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
                        this.sync_selected_editor_from_cache();
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
                        this.sync_selected_editor_from_cache();
                        this.local_message = None;
                    }
                    Err(error) => {
                        this.editor_load_error_paths.insert(requested_path.clone());
                        this.editor_loading_path = None;
                        let message: SharedString = if is_image_extension(&extension) {
                            image_preview_error_message(&error)
                        } else if is_mermaid_extension(&extension) {
                            merman_preview_error_message(&error)
                        } else {
                            editor_file_error_message(&error)
                        }
                        .into();
                        this.editor_error_messages
                            .insert(requested_path.clone(), message);
                    }
                }
                this.schedule_editor_autosave(cx);
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
        let saved_path = document.relative_path.clone();
        let saved_content = display_content.clone();
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
            this.update(cx, |this, cx| {
                if generation != this.editor_generation {
                    return;
                }
                this.editor_busy = false;
                match result {
                    Ok(document) => {
                        let path = saved_path.clone();
                        let current_content = this
                            .editor_input_for_path(&path)
                            .read(cx)
                            .value()
                            .to_string();
                        this.editor_documents.insert(path.clone(), document.clone());
                        this.editor_document = Some(document);
                        if current_content == saved_content {
                            this.editor_buffer_text.remove(&path);
                            this.editor_dirty_paths.remove(&path);
                            this.editor_dirty = false;
                        } else {
                            // Keep edits made while the write was in flight;
                            // only the content actually written becomes the
                            // new conflict baseline.
                            this.editor_buffer_text
                                .insert(path.clone(), current_content);
                            this.editor_dirty_paths.insert(path.clone());
                            this.editor_dirty = true;
                        }
                        this.editor_conflict = false;
                        this.local_message = Some(
                            if overwrite {
                                "File overwritten"
                            } else {
                                "File saved"
                            }
                            .into(),
                        );
                        this.schedule_editor_autosave(cx);
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

    fn render_explorer_row(&self, row: &ExplorerRow, cx: &mut Context<Self>) -> AnyElement {
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
        let pointer_path = path.clone();
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
            // Paths are the row identity. A watcher refresh can
            // insert/remove a sibling above this entry; an index id
            // would then make GPUI reuse the wrong row state and can
            // route the next click or drop to a different file.
            .id(SharedString::from(format!("explorer-row-{path}")))
            .focusable()
            .tab_stop(true)
            .role(Role::TreeItem)
            .aria_label(name.clone())
            .aria_selected(selected)
            .when(is_directory, |item| item.aria_expanded(expanded))
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
            .on_mouse_down(
                gpui::MouseButton::Left,
                cx.listener(move |this, _: &MouseDownEvent, _, _| {
                    this.explorer_pointer_down = Some(pointer_path.clone());
                    this.explorer_pointer_dragged = false;
                }),
            )
            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                // A drag ends with the same pointer-up event as a
                // click. Do not toggle/open the row after a
                // folder/file move, which is the behavior Flutter
                // gets from LongPressDraggable cancelling InkWell.
                let was_dragged = this.explorer_pointer_dragged || cx.has_active_drag();
                this.explorer_pointer_down = None;
                this.explorer_pointer_dragged = false;
                if was_dragged {
                    cx.stop_propagation();
                    return;
                }
                // The scrollbar is layered above the rows. GPUI's
                // pointer-up can still bubble to the row when a
                // thumb drag ends, so reserve the final 12 px of
                // the window for scrollbar interaction and never
                // open a file as a side effect of scrolling.
                if event.position().x >= window.bounds().right() - gpui::px(12.0) {
                    cx.stop_propagation();
                    return;
                }
                this.select_explorer_entry(click_path.clone());
                if is_directory {
                    this.toggle_directory(click_path.clone(), cx);
                } else {
                    this.open_file_tab(click_path.clone(), cx);
                }
            }))
            .on_aux_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                this.show_explorer_menu(
                    ExplorerMenuTarget::Entry(menu_path.clone()),
                    event.position(),
                    window,
                    cx,
                );
                cx.stop_propagation();
            }))
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
                        .id(SharedString::from(format!("explorer-source-root-{path}")))
                        .ml_2()
                        .tooltip(|_, cx| {
                            cx.new(|_| gpui_component::tooltip::Tooltip::new("Source Control Root"))
                                .into()
                        })
                        .child(icon(AleraIcon::GitBranch, 14.0, theme::text_muted())),
                )
            });
        if is_directory {
            let drag_target_path = drop_path.clone();
            let drop_target_path = drop_path.clone();
            item = item
                .drag_over::<ExplorerDragData>(|style, _, _, _| style.bg(theme::surface_selected()))
                .on_drag_move(cx.listener(
                    move |this, event: &DragMoveEvent<ExplorerDragData>, _, cx| {
                        let drag = event.drag(cx);
                        if this.can_drop_explorer_entry(&drag.relative_path, &drag_target_path) {
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
        item.into_any_element()
    }

    pub(super) fn render_explorer_panel(
        &self,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let row_count = self.explorer_rows.len();
        let entity = cx.entity();
        let rows = uniform_list("explorer-rows", row_count, move |range, _, app| {
            entity.update(app, |this, cx| {
                range
                    .filter_map(|index| {
                        this.explorer_rows
                            .get(index)
                            .cloned()
                            .map(|row| this.render_explorer_row(&row, cx))
                    })
                    .collect::<Vec<_>>()
            })
        })
        .size_full()
        .py_1()
        .track_scroll(&self.explorer_scroll_handle);
        let empty_state = if self.explorer_busy && row_count == 0 {
            Some(
                div()
                    .absolute()
                    .inset_0()
                    .flex()
                    .items_center()
                    .justify_center()
                    // Flutter's explorer loading state is only the centered
                    // animated progress indicator. A text label changes the
                    // optical center and makes the empty tree denser than the
                    // reference surface.
                    .child(loading_indicator(15.0, theme::text_muted()))
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
                    .bg(theme::surface())
                    .on_mouse_down(
                        MouseButton::Right,
                        cx.listener(|this, event: &MouseDownEvent, window, cx| {
                            this.show_explorer_menu(
                                ExplorerMenuTarget::Background,
                                event.position,
                                window,
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
                    .child(rows),
            )
            .child(
                Scrollbar::vertical(&self.explorer_scroll_handle)
                    .id("explorer-scrollbar")
                    .mode(ScrollbarMode::Always),
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
        "md" | "mdx" => crate::editor_theme::markdown_language_name(),
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

fn validate_workspace_image(format: &str, bytes: &[u8]) -> Result<(), String> {
    if format == "svg" {
        let source = std::str::from_utf8(bytes)
            .map_err(|error| format!("Workspace Image Decode Failed: {error}"))?;
        if source
            .chars()
            .take(2048)
            .collect::<String>()
            .contains("<svg")
        {
            return Ok(());
        }
        return Err("Workspace Image Decode Failed: SVG root is missing".to_owned());
    }
    let image_format = match format {
        "png" => image::ImageFormat::Png,
        "jpeg" => image::ImageFormat::Jpeg,
        "webp" => image::ImageFormat::WebP,
        "gif" => image::ImageFormat::Gif,
        "bmp" => image::ImageFormat::Bmp,
        "tiff" => image::ImageFormat::Tiff,
        _ => return Err(format!("Unsupported Workspace Image Format: {format}")),
    };
    image::ImageReader::with_format(Cursor::new(bytes), image_format)
        .into_dimensions()
        .map(|_| ())
        .map_err(|error| format!("Workspace Image Decode Failed: {error}"))
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
        .replace("fill:#333333;", "fill:#F5F5F5;")
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
        .replace("fill=\"#000000\"", "fill=\"#F5F5F5\"")
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
    if normalized.contains("decode failed") {
        "Image cannot be opened".to_owned()
    } else if normalized.contains("outside") {
        "Image is outside the workspace".to_owned()
    } else if normalized.contains("invalid") {
        "Image path is invalid".to_owned()
    } else if normalized.contains("not found") || normalized.contains("no such file") {
        "Image not found".to_owned()
    } else {
        "Image cannot be opened".to_owned()
    }
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

fn merman_preview_error_message(error: &str) -> String {
    let normalized = error.to_ascii_lowercase();
    if normalized.contains("not found") || normalized.contains("no such file") {
        "Diagram not found".to_owned()
    } else if normalized.contains("outside") {
        "Diagram is outside the workspace".to_owned()
    } else if normalized.contains("invalid") && normalized.contains("path") {
        "Diagram path is invalid".to_owned()
    } else if normalized.contains("unsupported")
        || normalized.contains("no mermaid")
        || normalized.contains("permission denied")
        || normalized.contains("i/o error")
    {
        "Diagram cannot be opened".to_owned()
    } else {
        "Diagram cannot be rendered".to_owned()
    }
}

#[cfg(test)]
mod merman_svg_tests {
    use super::{merman_preview_error_message, prepare_merman_svg_for_gpui};

    #[test]
    fn prepares_merman_svg_for_flutter_dark_theme() {
        let svg = r##"<svg><rect class="basic label-container" fill="#000000"/><path class="flowchart-link"/><path class="arrowMarkerPath" fill="#000000"/><text fill="#333333">Preview</text></svg>"##;
        let prepared = prepare_merman_svg_for_gpui(svg);
        assert!(prepared.contains("class=\"basic label-container\" fill=\"#242424\""));
        assert!(prepared.contains("class=\"flowchart-link\" fill=\"none\" stroke=\"#A1A1A1\""));
        assert!(prepared.contains("class=\"arrowMarkerPath\" fill=\"#A1A1A1\" stroke=\"#A1A1A1\""));
        assert!(prepared.contains("<text fill=\"#F5F5F5\">"));
    }

    #[test]
    fn maps_merman_errors_to_flutter_copy() {
        assert_eq!(
            merman_preview_error_message("diagram.mmd: No such file or directory"),
            "Diagram not found"
        );
        assert_eq!(
            merman_preview_error_message("path is outside workspace"),
            "Diagram is outside the workspace"
        );
        assert_eq!(
            merman_preview_error_message("unexpected token in flowchart"),
            "Diagram cannot be rendered"
        );
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
