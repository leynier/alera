use std::collections::BTreeMap;
use std::path::Path;
use std::time::Duration;

use gpui::{Context, Focusable as _, Window};
use serde_json::json;

use super::AleraApp;
use crate::model::{
    WorkbenchDropZone, WorkbenchLayout, WorkbenchLayoutNode, WorkbenchPaneGroup,
    WorkbenchSplitDirection,
};

impl AleraApp {
    /// Open a file from a navigation surface using Flutter's default tab kind.
    /// Markdown files open in the rendered viewer; search and explicit source
    /// actions continue to call `open_editor_tab` directly.
    pub(super) fn open_file_tab(&mut self, relative_path: String, cx: &mut Context<Self>) {
        let is_markdown = matches!(
            Path::new(&relative_path)
                .extension()
                .and_then(|extension| extension.to_str()),
            Some("md" | "mdx")
        );
        if is_markdown {
            self.open_markdown_viewer_tab(relative_path, cx);
        } else {
            self.open_editor_tab(relative_path, cx);
        }
    }

    pub(super) fn open_editor_tab(&mut self, relative_path: String, cx: &mut Context<Self>) {
        if let Some(tab) = self.snapshot.tabs.iter().find(|tab| {
            tab.kind == "editor"
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == Some(relative_path.as_str())
                && tab.payload.get("fileRole").and_then(|value| value.as_str())
                    != Some("mermanPreview")
        }) {
            self.activate_workspace_tab(tab.id.clone(), cx);
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-editor-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let title = Path::new(&relative_path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("Editor")
            .to_string();
        let bridge = self.bridge.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "editor",
                        "title": title,
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {"filePath": relative_path},
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, layout).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id =
                            tab.get("id").and_then(|id| id.as_str()).map(str::to_string);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn open_markdown_viewer_tab(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        if !matches!(
            Path::new(&relative_path)
                .extension()
                .and_then(|extension| extension.to_str()),
            Some("md" | "mdx")
        ) {
            return;
        }
        if let Some(tab) = self.snapshot.tabs.iter().find(|tab| {
            tab.kind == "markdownViewer"
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == Some(relative_path.as_str())
        }) {
            self.activate_workspace_tab(tab.id.clone(), cx);
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-markdown-viewer-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let title = Path::new(&relative_path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("Markdown Preview")
            .to_string();
        let bridge = self.bridge.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "markdownViewer",
                        "title": title,
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {"filePath": relative_path},
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, layout).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id =
                            tab.get("id").and_then(|id| id.as_str()).map(str::to_string);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn open_merman_preview_tab(
        &mut self,
        relative_path: String,
        cx: &mut Context<Self>,
    ) {
        if !matches!(
            Path::new(&relative_path)
                .extension()
                .and_then(|extension| extension.to_str()),
            Some("mmd" | "mermain" | "mermaid")
        ) {
            return;
        }
        if let Some(tab) = self.snapshot.tabs.iter().find(|tab| {
            tab.kind == "editor"
                && tab.payload.get("fileRole").and_then(|value| value.as_str())
                    == Some("mermanPreview")
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == Some(relative_path.as_str())
        }) {
            self.activate_workspace_tab(tab.id.clone(), cx);
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-merman-preview-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let title = Path::new(&relative_path)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("Diagram Preview")
            .to_string();
        let bridge = self.bridge.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "editor",
                        "title": title,
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {
                            "filePath": relative_path,
                            "fileRole": "mermanPreview",
                        },
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, layout).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id =
                            tab.get("id").and_then(|id| id.as_str()).map(str::to_string);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn open_git_diff_tab(
        &mut self,
        relative_path: Option<String>,
        area: Option<String>,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(source_scope) = self.selected_source_control_scope() else {
            return;
        };
        let source_relative_path = relative_path;
        let workspace_relative_path = source_relative_path
            .as_deref()
            .and_then(|path| source_scope.to_workspace_relative_path(path));
        let source_root = source_scope.relative_root.clone();
        if let Some(tab) = self.snapshot.tabs.iter().find(|tab| {
            tab.kind == "gitDiff"
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == workspace_relative_path.as_deref()
                && tab
                    .payload
                    .get("gitDiffArea")
                    .and_then(|value| value.as_str())
                    == area.as_deref()
                && tab
                    .payload
                    .get("gitDiffRoot")
                    .and_then(|value| value.as_str())
                    == source_root.as_deref()
        }) {
            self.activate_workspace_tab(tab.id.clone(), cx);
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let workspace_path = source_scope.path;
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-git-diff-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let scope = if source_relative_path.is_some() {
            "file"
        } else {
            "all"
        };
        let title = match (&source_relative_path, &area) {
            (Some(path), Some(area)) => format!(
                "{} {}",
                Path::new(path)
                    .file_name()
                    .and_then(|name| name.to_str())
                    .unwrap_or(path),
                title_case_git_area(area),
            ),
            _ => "All Changes".to_owned(),
        };
        let payload = json!({
            "gitDiffScope": scope,
            "filePath": workspace_relative_path,
            "gitDiffArea": area,
            "gitDiffRoot": source_root,
        });
        let bridge = self.bridge.clone();
        let service = self.workspace_service.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        self.git_diff_loading_tab = Some(tab_id.clone());
        self.git_diff_errors.remove(&tab_id);
        let preload_payload = payload.clone();
        let result_tab_id = tab_id.clone();
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "gitDiff",
                        "title": title,
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": payload,
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, layout).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let diff = if result.is_ok() {
                service
                    .git_diff(workspace_path, source_relative_path, area, None, None, None)
                    .await
            } else {
                Err("Git Diff Tab Could Not Be Created.".to_owned())
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                this.git_diff_loading_tab = None;
                match (result, diff) {
                    (Ok(_), Ok(diff)) => {
                        this.selected_tab_id = Some(result_tab_id.clone());
                        let diff_for_images = diff.clone();
                        this.git_diff = diff;
                        this.git_diff_loaded_tab = Some(result_tab_id.clone());
                        this.preload_git_diff_images(
                            result_tab_id.clone(),
                            preload_payload.clone(),
                            &diff_for_images,
                            cx,
                        );
                        this.refresh(cx);
                    }
                    (Err(error), _) | (_, Err(error)) => {
                        this.git_diff_errors
                            .insert(result_tab_id.clone(), "Could not load diff.".into());
                        let _ = error;
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn create_terminal_tab(&mut self, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let ordinal =
            next_terminal_ordinal(self.snapshot.tabs.iter().map(|tab| tab.title.as_str()));
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-tab-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let bridge = self.bridge.clone();
        let mut layout = self.snapshot.layout.clone();
        if let Some(layout) = layout.as_mut() {
            layout.add_tab_to_active_group(tab_id.clone());
        }
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "terminal",
                        "title": format!("Terminal {ordinal}"),
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {
                            "terminalSessionId": tab_id,
                        },
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, layout).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id =
                            tab.get("id").and_then(|id| id.as_str()).map(str::to_string);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn split_pane_with_terminal(
        &mut self,
        group_id: String,
        direction: WorkbenchSplitDirection,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let mut layout = self.snapshot.layout.clone().unwrap_or_else(|| {
            let tab_ids = self
                .snapshot
                .tabs
                .iter()
                .map(|tab| tab.id.clone())
                .collect::<Vec<_>>();
            let active_tab_id = self
                .selected_tab_id
                .clone()
                .or_else(|| tab_ids.first().cloned());
            let group = WorkbenchPaneGroup {
                id: group_id.clone(),
                tab_ids,
                active_tab_id,
            };
            let mut groups = BTreeMap::new();
            groups.insert(group_id.clone(), group);
            WorkbenchLayout {
                workspace_id: workspace_id.clone(),
                root: WorkbenchLayoutNode::Leaf {
                    group_id: group_id.clone(),
                },
                groups,
                active_group_id: group_id.clone(),
            }
        });
        let timestamp = chrono::Utc::now();
        let tab_id = format!(
            "gpui-tab-{}-{}",
            std::process::id(),
            timestamp.timestamp_millis()
        );
        let new_group_id = format!(
            "gpui-pane-{}-{}",
            std::process::id(),
            timestamp.timestamp_micros()
        );
        let ordinal =
            next_terminal_ordinal(self.snapshot.tabs.iter().map(|tab| tab.title.as_str()));
        layout.split_group(
            &group_id,
            direction,
            WorkbenchPaneGroup {
                id: new_group_id,
                tab_ids: vec![tab_id.clone()],
                active_tab_id: Some(tab_id.clone()),
            },
        );
        let bridge = self.bridge.clone();
        self.workbench_menu = None;
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request(
                    "tab.upsert",
                    json!({
                        "id": tab_id,
                        "workspaceId": workspace_id,
                        "kind": "terminal",
                        "title": format!("Terminal {ordinal}"),
                        "createdAt": timestamp.to_rfc3339(),
                        "updatedAt": timestamp.to_rfc3339(),
                        "payload": {"terminalSessionId": tab_id},
                    }),
                )
                .await;
            let result = match result {
                Ok(tab) => persist_layout(&bridge, Some(layout)).await.map(|_| tab),
                Err(error) => Err(error),
            };
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(tab) => {
                        this.selected_tab_id =
                            tab.get("id").and_then(|id| id.as_str()).map(str::to_string);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn merge_pane_group(&mut self, group_id: String, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(mut layout) = self.snapshot.layout.clone() else {
            return;
        };
        if layout.groups.len() <= 1 {
            self.workbench_menu = None;
            cx.notify();
            return;
        }
        layout.merge_group_into_sibling(&group_id);
        let bridge = self.bridge.clone();
        self.workbench_menu = None;
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = persist_layout(&bridge, Some(layout)).await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(()) => this.refresh(cx),
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn request_close_tab(&mut self, tab_id: String, cx: &mut Context<Self>) {
        self.request_close_tabs(vec![tab_id], cx);
    }

    pub(super) fn request_close_tabs(&mut self, tab_ids: Vec<String>, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let tab_ids = tab_ids
            .into_iter()
            .filter(|tab_id| self.snapshot.tabs.iter().any(|tab| &tab.id == tab_id))
            .collect::<Vec<_>>();
        if tab_ids.is_empty() {
            return;
        }
        if self
            .tab_pointer_drag
            .as_ref()
            .is_some_and(|(_, tab_id)| tab_ids.contains(tab_id))
        {
            self.clear_pointer_tab_drag_state(cx);
        }
        let closing_open_editor = self.snapshot.tabs.iter().any(|tab| {
            tab_ids.contains(&tab.id)
                && matches!(tab.kind.as_str(), "editor" | "markdownViewer")
                && tab.payload.get("filePath").and_then(|value| value.as_str())
                    == self.opened_file_path.as_deref()
        });
        if closing_open_editor
            && self.editor_dirty
            && self.tab_close_armed.as_ref() != Some(&tab_ids)
        {
            self.tab_close_armed = Some(tab_ids);
            cx.notify();
            return;
        }
        // Presence is projected independently from the workbench snapshot.
        // Remove the rows optimistically, then refresh after the host has
        // terminated the matching terminal sessions so the sidebar cannot
        // retain a closed agent until the next presence notification.
        self.prune_presence_for_tabs(&tab_ids);
        for tab_id in &tab_ids {
            self.git_diff_errors.remove(tab_id);
            self.preview_transforms.remove(tab_id);
            if self
                .preview_drag
                .as_ref()
                .is_some_and(|drag| &drag.tab_id == tab_id)
            {
                self.preview_drag = None;
            }
            self.git_diff_image_sides
                .retain(|(owner, _), _| owner != tab_id);
            self.git_diff_image_loading
                .retain(|(owner, _)| owner != tab_id);
        }
        for tab in self
            .snapshot
            .tabs
            .iter()
            .filter(|tab| tab_ids.iter().any(|id| id == &tab.id))
        {
            let session_id = tab
                .payload
                .get("terminalSessionId")
                .and_then(|value| value.as_str())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or(tab.id.as_str());
            self.tab_completion_acknowledged.remove(session_id);
        }
        self.tab_close_armed = None;
        self.tab_mutation_busy = true;
        let bridge = self.bridge.clone();
        let previous_layout = self.snapshot.layout.clone();
        let mut layout = previous_layout.clone();
        if let Some(layout) = layout.as_mut() {
            for tab_id in &tab_ids {
                layout.remove_tab(tab_id);
            }
        }
        // Apply the same optimistic snapshot contract used by drag/drop. The
        // sidebar derives presence from `all_tabs`, so waiting for the host
        // round-trip leaves a just-closed workspace green and keeps its agent
        // row mounted for the duration of the request.
        self.snapshot.tabs.retain(|tab| !tab_ids.contains(&tab.id));
        self.snapshot
            .all_tabs
            .retain(|tab| !tab_ids.contains(&tab.id));
        self.snapshot.layout = layout.clone();
        if self.snapshot.tabs.is_empty() {
            self.selected_workspace_id = None;
            self.pending_workspace_terminal_id = None;
            self.pending_workspace_tab_id = None;
        }
        let next_selected_tab_id = layout
            .as_ref()
            .and_then(|layout| layout.groups.get(&layout.active_group_id))
            .and_then(|group| group.active_tab_id.clone());
        self.selected_tab_id = next_selected_tab_id.clone();
        cx.notify();
        cx.spawn(async move |this, cx| {
            let result = async {
                for tab_id in &tab_ids {
                    remove_tab_with_retry(&bridge, tab_id).await?;
                }
                persist_layout(&bridge, layout).await
            }
            .await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(()) => {
                        this.selected_tab_id = next_selected_tab_id;
                        if closing_open_editor {
                            this.editor_document = None;
                            this.editor_documents.clear();
                            this.editor_buffer_text.clear();
                            this.editor_dirty_paths.clear();
                            this.editor_cursor_positions.clear();
                            this.opened_file_path = None;
                            this.editor_preview_assets.clear();
                            this.markdown_preview_content.clear();
                            this.editor_dirty = false;
                        }
                        this.refresh_presence_status(cx);
                        this.refresh(cx);
                    }
                    Err(error) => {
                        // A partial host mutation or a failed layout write is
                        // reconciled from the durable snapshot. Restore the
                        // optimistic layout immediately as well so a failed
                        // close cannot leave the client with an empty pane.
                        this.snapshot.layout = previous_layout;
                        this.local_message = Some(error.into());
                        this.refresh_presence_status(cx);
                        this.refresh(cx);
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn cancel_close_dirty_tab(&mut self, cx: &mut Context<Self>) {
        self.tab_close_armed = None;
        cx.notify();
    }

    pub(super) fn confirm_close_dirty_tab(&mut self, cx: &mut Context<Self>) {
        let Some(tab_ids) = self.tab_close_armed.clone() else {
            return;
        };
        self.request_close_tabs(tab_ids, cx);
    }

    pub(super) fn move_workspace_tab(
        &mut self,
        tab_id: String,
        target_group_id: String,
        index: usize,
        cx: &mut Context<Self>,
    ) {
        self.move_workspace_tab_to_drop(
            tab_id,
            target_group_id,
            WorkbenchDropZone::Center,
            Some(index),
            cx,
        );
    }

    pub(super) fn move_workspace_tab_to_drop(
        &mut self,
        tab_id: String,
        target_group_id: String,
        zone: WorkbenchDropZone,
        index: Option<usize>,
        cx: &mut Context<Self>,
    ) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(mut layout) = self.snapshot.layout.clone() else {
            return;
        };
        let new_group_id = format!("gpui-group-{}", uuid::Uuid::new_v4());
        if !layout.move_tab_to_drop(&tab_id, &target_group_id, zone, &new_group_id, index) {
            return;
        }
        let previous_layout = self.snapshot.layout.clone();
        let optimistic_layout = layout.clone();
        // Keep the layout responsive while the host persists the mutation.
        // Waiting for a refresh here makes a successful drop look lost when a
        // runtime change notification races the persistence request.
        self.snapshot.layout = Some(optimistic_layout.clone());
        self.selected_tab_id = Some(tab_id);
        self.tab_drop_target = None;
        self.pane_drop_target = None;
        self.tab_mutation_busy = true;
        let bridge = self.bridge.clone();
        cx.spawn(async move |this, cx| {
            let result = persist_layout(&bridge, Some(optimistic_layout)).await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(()) => cx.notify(),
                    Err(error) => {
                        this.snapshot.layout = previous_layout;
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    pub(super) fn open_tab_rename_dialog(
        &mut self,
        tab_id: String,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let title = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .map(|tab| tab.title.clone())
            .unwrap_or_default();
        self.selected_tab_id = Some(tab_id);
        self.tab_rename_input
            .update(cx, |input, cx| input.set_value(title.clone(), window, cx));
        self.tab_rename_replace_pending = Some(title);
        self.show_tab_rename_dialog = true;
        self.tab_rename_input.focus_handle(cx).focus(window, cx);
        cx.notify();
    }

    pub(super) fn close_tab_rename_dialog(&mut self, cx: &mut Context<Self>) {
        if !self.tab_mutation_busy {
            self.show_tab_rename_dialog = false;
            self.tab_rename_replace_pending = None;
            cx.notify();
        }
    }

    pub(super) fn activate_workspace_tab(&mut self, tab_id: String, cx: &mut Context<Self>) {
        if let Some(previous_tab_id) = self
            .selected_tab_id
            .as_deref()
            .filter(|previous_tab_id| *previous_tab_id != tab_id)
            .map(str::to_owned)
        {
            self.preview_transforms.remove(&previous_tab_id);
            if self
                .preview_drag
                .as_ref()
                .is_some_and(|drag| drag.tab_id == previous_tab_id)
            {
                self.preview_drag = None;
            }
        }
        if let Some(path) = self
            .opened_file_path
            .clone()
            .filter(|_| self.editor_document.is_some())
        {
            let editor_input = self.editor_input_for_path(&path);
            let text = editor_input.read(cx).value().to_string();
            self.editor_buffer_text.insert(path.clone(), text);
            let cursor = editor_input.read(cx).cursor_position();
            self.editor_cursor_positions
                .insert(path.clone(), (cursor.line, cursor.character));
            if self.editor_dirty {
                self.editor_dirty_paths.insert(path.clone());
            } else {
                self.editor_dirty_paths.remove(&path);
            }
        }
        if let Some(path) = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .and_then(|tab| tab.payload.get("filePath"))
            .and_then(|value| value.as_str())
        {
            // Retrying a failed file load is an explicit user action. This
            // also prevents the render loop from repeatedly hitting a bad
            // path while preserving a retry path from the tab itself.
            self.editor_load_error_paths.remove(path);
            self.editor_error_messages.remove(path);
        }
        let completion_acknowledgement =
            self.snapshot
                .tabs
                .iter()
                .find(|tab| tab.id == tab_id)
                .and_then(|tab| {
                    let session_id = tab
                        .payload
                        .get("terminalSessionId")
                        .and_then(|value| value.as_str())
                        .filter(|value| !value.trim().is_empty())
                        .unwrap_or(tab.id.as_str());
                    self.matching_presence_for_tab(tab).and_then(|entry| {
                        (entry.get("agentState").and_then(|value| value.as_str()) == Some("done"))
                            .then(|| {
                                (
                                    session_id.to_owned(),
                                    entry
                                        .get("stateStartedAt")
                                        .and_then(|value| value.as_str())
                                        .unwrap_or_default()
                                        .to_owned(),
                                )
                            })
                    })
                });
        if let Some((session_id, state_started_at)) = completion_acknowledgement {
            self.tab_completion_acknowledged
                .insert(session_id, state_started_at);
        }
        let selected_kind = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .map(|tab| tab.kind.clone());
        let cached_visual_preview = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id)
            .and_then(|tab| {
                let path = tab
                    .payload
                    .get("filePath")
                    .and_then(|value| value.as_str())?;
                let file_role = tab.payload.get("fileRole").and_then(|value| value.as_str());
                let is_merman_preview = file_role == Some("mermanPreview");
                let is_cached_visual = self.editor_preview_assets.get(path).is_some_and(|asset| {
                    matches!(
                        asset,
                        super::workspace_surface::PreviewAsset::Image(_)
                            | super::workspace_surface::PreviewAsset::Mermaid(_)
                    )
                });
                Some(is_merman_preview || is_cached_visual)
            })
            .unwrap_or(false);
        let diff_payload = self
            .snapshot
            .tabs
            .iter()
            .find(|tab| tab.id == tab_id && tab.kind == "gitDiff")
            .map(|tab| tab.payload.clone());
        self.selected_tab_id = Some(tab_id.clone());
        let tab_scroll_target = self.snapshot.layout.as_ref().and_then(|layout| {
            layout.groups.iter().find_map(|(group_id, group)| {
                group
                    .tab_ids
                    .iter()
                    .position(|candidate| candidate == &tab_id)
                    .map(|index| (group_id.clone(), index))
            })
        });
        if let Some((group_id, index)) = tab_scroll_target {
            if let Some(handle) = self
                .tab_strip_scroll_handles
                .borrow()
                .get(&group_id)
                .cloned()
            {
                handle.scroll_to_item(index);
            }
        }
        self.sync_selected_editor_from_cache();
        if selected_kind.as_deref() == Some("editor") {
            // Image/Mermaid editor tabs are viewers in Flutter. Restore the
            // cached visual mode when revisiting an existing tab instead of
            // leaving the previous source document underneath its new title.
            self.show_preview = cached_visual_preview;
        } else if selected_kind.as_deref() == Some("markdownViewer") {
            self.show_preview = true;
        }
        self.ensure_selected_terminal(cx);
        if let Some(payload) = diff_payload {
            self.load_git_diff_tab(tab_id.clone(), payload, cx);
        }
        let mut layout = self.snapshot.layout.clone();
        let Some(layout) = layout.as_mut() else {
            cx.notify();
            return;
        };
        layout.activate_tab(&tab_id);
        let bridge = self.bridge.clone();
        let layout = layout.clone();
        cx.spawn(async move |_, _| {
            let _ = persist_layout(&bridge, Some(layout)).await;
        })
        .detach();
        cx.notify();
    }

    pub(super) fn load_git_diff_tab(
        &mut self,
        tab_id: String,
        payload: serde_json::Value,
        cx: &mut Context<Self>,
    ) {
        if self.git_diff_loading_tab.as_deref() == Some(&tab_id) {
            return;
        }
        let source_root = payload
            .get("gitDiffRoot")
            .and_then(serde_json::Value::as_str);
        let Some(source_scope) = self.source_control_scope_for_root(source_root) else {
            return;
        };
        let workspace_file_path = payload
            .get("filePath")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let file_path = workspace_file_path
            .as_deref()
            .and_then(|path| source_scope.to_source_relative_path(path));
        let area = payload
            .get("gitDiffArea")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let commit_id = payload
            .get("gitDiffCommitOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let parent_id = payload
            .get("gitDiffParentOid")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned);
        let old_path = payload
            .get("gitDiffOldPath")
            .and_then(serde_json::Value::as_str)
            .and_then(|path| source_scope.to_source_relative_path(path));
        let workspace_path = source_scope.path;
        self.git_diff_loading_tab = Some(tab_id.clone());
        self.git_diff_errors.remove(&tab_id);
        let preload_payload = payload.clone();
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service
                .git_diff(
                    workspace_path,
                    file_path,
                    area,
                    commit_id,
                    parent_id,
                    old_path,
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                if this.git_diff_loading_tab.as_deref() != Some(&tab_id) {
                    return;
                }
                this.git_diff_loading_tab = None;
                match result {
                    Ok(diff) => {
                        let diff_for_images = diff.clone();
                        this.git_diff = diff;
                        this.git_diff_loaded_tab = Some(tab_id.clone());
                        this.preload_git_diff_images(
                            tab_id.clone(),
                            preload_payload.clone(),
                            &diff_for_images,
                            cx,
                        );
                    }
                    Err(error) => {
                        this.git_diff_errors
                            .insert(tab_id.clone(), "Could not load diff.".into());
                        let _ = error;
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn rename_selected_tab(&mut self, cx: &mut Context<Self>) {
        if self.tab_mutation_busy {
            return;
        }
        let Some(tab_id) = self.selected_tab_id.clone() else {
            return;
        };
        let title = self.tab_rename_input.read(cx).value().trim().to_string();
        if title.is_empty() {
            self.local_message = Some("Terminal Title Is Required".into());
            cx.notify();
            return;
        }
        let bridge = self.bridge.clone();
        self.tab_mutation_busy = true;
        cx.spawn(async move |this, cx| {
            let result = bridge
                .request_with_timeout(
                    "tab.rename",
                    json!({"id": tab_id, "title": title}),
                    Duration::from_secs(5),
                )
                .await;
            let _ = this.update(cx, |this, cx| {
                this.tab_mutation_busy = false;
                match result {
                    Ok(_) => {
                        this.show_tab_rename_dialog = false;
                        this.tab_rename_replace_pending = None;
                        this.refresh(cx);
                    }
                    Err(error) => {
                        this.local_message = Some(error.into());
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }
}

async fn remove_tab_with_retry(
    bridge: &crate::runtime_bridge::RuntimeBridge,
    tab_id: &str,
) -> Result<(), String> {
    let payload = json!({"id": tab_id});
    match bridge.request("tab.remove", payload.clone()).await {
        Ok(_) => Ok(()),
        Err(error) if ambiguous_tab_removal_error(&error) => {
            bridge.request("tab.remove", payload).await.map(|_| ())
        }
        Err(error) => Err(error),
    }
}

fn ambiguous_tab_removal_error(error: &str) -> bool {
    let error = error.to_ascii_lowercase();
    error.contains("timed out")
        || error.contains("closed before replying")
        || error.contains("connection closed")
        || error.contains("broken pipe")
}

fn next_terminal_ordinal<'a>(titles: impl Iterator<Item = &'a str>) -> usize {
    let used = titles
        .filter_map(|title| title.strip_prefix("Terminal "))
        .filter_map(|ordinal| ordinal.parse::<usize>().ok())
        .collect::<std::collections::HashSet<_>>();
    (1..).find(|ordinal| !used.contains(ordinal)).unwrap()
}

fn title_case_git_area(area: &str) -> &'static str {
    match area.to_ascii_lowercase().as_str() {
        "staged" => "Staged",
        "untracked" => "Untracked",
        _ => "Unstaged",
    }
}

pub(super) async fn persist_layout(
    bridge: &crate::runtime_bridge::RuntimeBridge,
    layout: Option<crate::model::WorkbenchLayout>,
) -> Result<(), String> {
    let Some(layout) = layout else {
        return Ok(());
    };
    let payload = json!({
        "workspaceId": layout.workspace_id,
        "data": layout.to_value(),
    });
    bridge.request("layout.upsert", payload.clone()).await?;
    // Flutter and GPUI can observe the same runtime while parity is tested side by side.
    // Reassert the explicit user mutation after both clients have processed the tab event.
    async_io::Timer::after(Duration::from_millis(250)).await;
    bridge.request("layout.upsert", payload).await.map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::{ambiguous_tab_removal_error, next_terminal_ordinal};

    #[test]
    fn terminal_ordinal_reuses_the_first_available_number() {
        let titles = ["Terminal 1", "README.md", "Terminal 3", "Terminal 4"];
        assert_eq!(next_terminal_ordinal(titles.into_iter()), 2);
    }

    #[test]
    fn terminal_ordinal_ignores_noncanonical_titles() {
        let titles = ["Terminal", "Terminal Custom", "terminal 1"];
        assert_eq!(next_terminal_ordinal(titles.into_iter()), 1);
    }

    #[test]
    fn tab_removal_retries_only_ambiguous_transport_failures() {
        assert!(ambiguous_tab_removal_error(
            "Runtime request tab.remove timed out."
        ));
        assert!(ambiguous_tab_removal_error(
            "Runtime bridge closed before replying."
        ));
        assert!(!ambiguous_tab_removal_error(
            "Tab removal was rejected by policy."
        ));
    }
}
