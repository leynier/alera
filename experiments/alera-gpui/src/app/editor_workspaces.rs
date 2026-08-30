use std::collections::{BTreeMap, BTreeSet};

use gpui::{Context, Entity, SharedString, Subscription};
use gpui_component::input::EditorState;

use super::{AleraApp, EditorDocument, PreviewAsset};
use crate::model::WorkspaceTab;

#[derive(Default)]
pub(super) struct WorkspaceEditors {
    pub inputs: BTreeMap<String, Entity<EditorState>>,
    subscriptions: BTreeMap<String, Subscription>,
    documents: BTreeMap<String, EditorDocument>,
    load_errors: BTreeSet<String>,
    errors: BTreeMap<String, SharedString>,
    pub buffers: BTreeMap<String, String>,
    pub dirty: BTreeSet<String>,
    cursors: BTreeMap<String, (u32, u32)>,
    previews: BTreeMap<String, PreviewAsset>,
    markdown: BTreeMap<String, String>,
}

impl WorkspaceEditors {
    pub(super) fn accept_saved(&mut self, request: &super::editor_requests::EditorWrite, document: EditorDocument, cx: &gpui::App) -> bool {
        let Some(input) = self.inputs.get(&request.key.path).filter(|input| input.entity_id() == request.editor) else { return false; };
        if document.relative_path != request.key.path { return false; }
        let current = input.read(cx).value().to_string();
        self.documents.insert(request.key.path.clone(), document);
        if current == request.content {
            self.buffers.remove(&request.key.path);
            self.dirty.remove(&request.key.path);
        } else {
            self.buffers.insert(request.key.path.clone(), current);
            self.dirty.insert(request.key.path.clone());
        }
        true
    }

    pub(super) fn take(app: &mut AleraApp) -> Self {
        Self {
            inputs: std::mem::take(&mut app.editor_inputs),
            subscriptions: std::mem::take(&mut app.editor_input_subscriptions),
            documents: std::mem::take(&mut app.editor_documents),
            load_errors: std::mem::take(&mut app.editor_load_error_paths),
            errors: std::mem::take(&mut app.editor_error_messages),
            buffers: std::mem::take(&mut app.editor_buffer_text),
            dirty: std::mem::take(&mut app.editor_dirty_paths),
            cursors: std::mem::take(&mut app.editor_cursor_positions),
            previews: std::mem::take(&mut app.editor_preview_assets),
            markdown: std::mem::take(&mut app.markdown_preview_content),
        }
    }

    pub(super) fn restore(self, app: &mut AleraApp) {
        app.editor_inputs = self.inputs;
        app.editor_input_subscriptions = self.subscriptions;
        app.editor_documents = self.documents;
        app.editor_load_error_paths = self.load_errors;
        app.editor_error_messages = self.errors;
        app.editor_buffer_text = self.buffers;
        app.editor_dirty_paths = self.dirty;
        app.editor_cursor_positions = self.cursors;
        app.editor_preview_assets = self.previews;
        app.markdown_preview_content = self.markdown;
    }

    pub(super) fn record_change(&mut self, path: &str, input: &Entity<EditorState>, content: String) {
        if self.inputs.get(path) != Some(input) { return; }
        if self.documents.get(path).is_some_and(|doc| doc.display_content == content) {
            self.buffers.remove(path);
            self.dirty.remove(path);
        } else {
            self.buffers.insert(path.to_owned(), content);
            self.dirty.insert(path.to_owned());
        }
    }

    fn retain_paths(&mut self, paths: &BTreeSet<String>) {
        self.inputs.retain(|path, _| paths.contains(path));
        self.subscriptions.retain(|path, _| paths.contains(path));
        self.documents.retain(|path, _| paths.contains(path));
        self.load_errors.retain(|path| paths.contains(path));
        self.errors.retain(|path, _| paths.contains(path));
        self.buffers.retain(|path, _| paths.contains(path));
        self.dirty.retain(|path| paths.contains(path));
        self.cursors.retain(|path, _| paths.contains(path));
        self.previews.retain(|path, _| paths.contains(path));
        self.markdown.retain(|path, _| paths.contains(path));
    }
}

#[derive(Default)]
pub(super) struct EditorWorkspaces {
    pub owner: Option<String>,
    pub parked: BTreeMap<String, WorkspaceEditors>,
}

impl EditorWorkspaces {
    pub(super) fn accept_saved(&mut self, active: &mut WorkspaceEditors, request: &super::editor_requests::EditorWrite, document: EditorDocument, cx: &gpui::App) -> bool {
        if self.owner.as_deref() == Some(request.key.workspace.as_str()) {
            active.accept_saved(request, document, cx)
        } else {
            self.parked.get_mut(&request.key.workspace).is_some_and(|state| state.accept_saved(request, document, cx))
        }
    }

    fn switch(&mut self, next: Option<String>, current: WorkspaceEditors) -> WorkspaceEditors {
        if self.owner == next { return current; }
        if let Some(owner) = self.owner.take() {
            if !current.inputs.is_empty() || !current.previews.is_empty() {
                self.parked.insert(owner, current);
            }
        }
        self.owner = next.clone();
        next.and_then(|owner| self.parked.remove(&owner)).unwrap_or_default()
    }

    pub fn retain_live_tabs(&mut self, tabs: &[WorkspaceTab]) {
        let mut paths = BTreeMap::<String, BTreeSet<String>>::new();
        for tab in tabs.iter().filter(|tab| matches!(tab.kind.as_str(), "editor" | "markdownViewer" | "pdf")) {
            if let Some(path) = tab.payload.get("filePath").and_then(serde_json::Value::as_str) {
                paths.entry(tab.workspace_id.clone()).or_default().insert(path.to_owned());
            }
        }
        self.parked.retain(|owner, state| {
            let Some(paths) = paths.get(owner) else { return false; };
            state.retain_paths(paths);
            !state.inputs.is_empty() || !state.previews.is_empty()
        });
    }
}

impl AleraApp {
    pub(super) fn switch_editor_workspace(&mut self) {
        if self.editor_workspaces.owner == self.selected_workspace_id { return; }
        let current = WorkspaceEditors::take(self);
        let next = self.editor_workspaces.switch(self.selected_workspace_id.clone(), current);
        next.restore(self);
        self.editor_generation = self.editor_generation.wrapping_add(1);
        self.editor_autosave_generation = self.editor_autosave_generation.wrapping_add(1);
        self.editor_loading_path = None;
        self.editor_busy = false;
        self.editor_document = None;
        self.opened_file_path = None;
        self.preview_asset = None;
        self.editor_dirty = false;
        self.editor_conflict = false;
        self.pending_editor_cursor = None;
        self.editor_input_syncing = false;
        self.show_preview = false;
    }

    pub(super) fn record_editor_change(&mut self, owner: &str, path: &str, input: &Entity<EditorState>, cx: &mut Context<Self>) {
        let content = input.read(cx).value().to_string();
        if self.editor_workspaces.owner.as_deref() != Some(owner) {
            if let Some(state) = self.editor_workspaces.parked.get_mut(owner) {
                state.record_change(path, input, content);
            }
            return;
        }
        if self.editor_input_syncing || self.editor_inputs.get(path) != Some(input) { return; }
        let visible = self.selected_workspace_id.as_deref() == Some(owner);
        let dirty = self.editor_documents.get(path).is_some_and(|doc| doc.display_content != content);
        if dirty {
            if visible { self.keep_preview_tab_for_path(path, cx); }
            self.editor_buffer_text.insert(path.to_owned(), content.clone());
            self.editor_dirty_paths.insert(path.to_owned());
        } else {
            self.editor_buffer_text.remove(path);
            self.editor_dirty_paths.remove(path);
        }
        if visible { self.cache_markdown_preview_content(path, &content); }
        if visible && self.opened_file_path.as_deref() == Some(path) {
            self.editor_dirty = dirty;
        }
        if visible { self.schedule_editor_autosave_path(path, cx); }
        cx.notify();
    }
}

#[cfg(all(test, feature = "gpui-tests"))]
#[path = "editor_workspaces_tests.rs"]
mod tests;
