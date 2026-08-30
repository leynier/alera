use std::collections::BTreeSet;

use gpui::Context;

use super::{AleraApp, editor_requests::EditorKey, editor_workspaces::WorkspaceEditors};

impl AleraApp {
    pub(super) fn replacement_blocker(&self, workspace: &str, paths: &BTreeSet<String>, cx: &Context<Self>) -> Option<String> {
        let dirty = paths.iter().filter(|path| {
            self.editor_dirty_paths.contains(*path) || self.editor_inputs.get(*path).is_some_and(|input| {
                self.editor_documents.get(*path).is_some_and(|document| input.read(cx).value().as_str() != document.display_content)
            })
        }).collect::<Vec<_>>();
        if dirty.len() == 1 {
            return Some(format!("Save or discard {} before replacing.", dirty[0]));
        }
        if !dirty.is_empty() {
            return Some(format!("Save or discard {} open files before replacing.", dirty.len()));
        }
        paths.iter().find(|path| self.editor_requests.is_writing(&EditorKey { workspace: workspace.to_owned(), path: (*path).clone() }))
            .map(|path| format!("Wait for {path} to finish saving before replacing."))
    }

    pub(super) fn reload_replaced_editors(&mut self, workspace: &str, workspace_path: &str, paths: &BTreeSet<String>, cx: &mut Context<Self>) {
        if self.snapshot.workspace(workspace).is_none_or(|value| value.path != workspace_path) { return; }
        let paths = paths.iter().filter(|path| !self.editor_requests.is_writing(&EditorKey { workspace: workspace.to_owned(), path: (*path).clone() })).cloned().collect();
        if self.editor_workspaces.owner.as_deref() == Some(workspace) {
            let mut state = WorkspaceEditors::take(self);
            let invalidated = state.invalidate_clean_paths(&paths, cx);
            state.restore(self);
            if self.editor_loading_path.as_ref().is_some_and(|path| invalidated.contains(path)) {
                self.editor_generation = self.editor_generation.wrapping_add(1);
                self.editor_loading_path = None;
            }
            if self.opened_file_path.as_ref().is_some_and(|path| invalidated.contains(path)) {
                self.opened_file_path = None;
                self.editor_document = None;
                self.preview_asset = None;
            }
            self.sync_editor_busy();
        } else if let Some(state) = self.editor_workspaces.parked.get_mut(workspace) {
            state.invalidate_clean_paths(&paths, cx);
        }
        cx.notify();
    }
}
