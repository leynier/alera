use gpui::{Context, Entity};
use gpui_component::input::EditorState;

use super::{AleraApp, EditorDocument};
use super::editor_requests::{EditorKey, EditorWrite};
use super::editor_workspaces::WorkspaceEditors;

impl AleraApp {
    pub(super) fn selected_editor_key(&self) -> Option<EditorKey> {
        if self.snapshot.selected_workspace_id != self.selected_workspace_id { return None; }
        let tab = self.snapshot.tabs.iter().find(|tab| Some(tab.id.as_str()) == self.selected_tab_id.as_deref() && tab.kind == "editor")?;
        Some(EditorKey { workspace: tab.workspace_id.clone(), path: tab.payload.get("filePath")?.as_str()?.to_owned() })
    }

    pub(super) fn owned_editor_input(&self, key: &EditorKey) -> Option<Entity<EditorState>> {
        if self.editor_workspaces.owner.as_deref() == Some(key.workspace.as_str()) {
            self.editor_inputs.get(&key.path).cloned()
        } else {
            self.editor_workspaces.parked.get(&key.workspace)?.inputs.get(&key.path).cloned()
        }
    }

    pub(super) fn editor_is_visible(&self, key: &EditorKey) -> bool {
        if self.selected_workspace_id.as_deref() != Some(key.workspace.as_str()) || self.snapshot.selected_workspace_id != self.selected_workspace_id { return false; }
        self.snapshot.tabs.iter().any(|tab| {
            tab.kind == "editor" && tab.payload.get("filePath").and_then(serde_json::Value::as_str) == Some(key.path.as_str())
                && self.snapshot.layout.as_ref().map_or_else(
                    || self.selected_tab_id.as_deref() == Some(tab.id.as_str()),
                    |layout| layout.groups.values().any(|group| group.active_tab_id.as_deref() == Some(tab.id.as_str())),
                )
        })
    }

    pub(super) fn owned_editor_document(&self, key: &EditorKey) -> Option<&EditorDocument> {
        if self.editor_workspaces.owner.as_deref() == Some(key.workspace.as_str()) {
            if self.editor_load_error_paths.contains(&key.path) { return None; }
            self.editor_documents.get(&key.path)
        } else {
            self.editor_workspaces.parked.get(&key.workspace)?.document(&key.path)
        }
    }

    pub(super) fn owned_editor_is_dirty(&self, key: &EditorKey, cx: &gpui::App) -> bool {
        self.owned_editor_input(key).zip(self.owned_editor_document(key))
            .is_some_and(|(input, document)| input.read(cx).value().as_str() != document.display_content)
    }

    pub(super) fn sync_editor_busy(&mut self) {
        self.editor_busy = self.snapshot.tabs.iter().find(|tab| Some(tab.id.as_str()) == self.selected_tab_id.as_deref())
            .and_then(|tab| tab.payload.get("filePath").and_then(serde_json::Value::as_str))
            .is_some_and(|path| self.editor_path_busy(path));
    }

    pub(super) fn editor_path_busy(&self, path: &str) -> bool {
        if self.snapshot.selected_workspace_id != self.selected_workspace_id { return false; }
        self.editor_loading_path.as_deref() == Some(path) || self.editor_workspaces.owner.as_ref().is_some_and(|workspace| {
            self.editor_requests.is_writing(&EditorKey { workspace: workspace.clone(), path: path.to_owned() })
        })
    }

    pub(super) fn save_editor(&mut self, overwrite: bool, cx: &mut Context<Self>) {
        if let Some(key) = self.selected_editor_key() { self.save_editor_key(key, overwrite, cx); }
    }

    pub(super) fn save_editor_key(&mut self, key: EditorKey, overwrite: bool, cx: &mut Context<Self>) {
        let Some((request, document)) = self.begin_editor_write(key, overwrite, cx) else { return; };
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.write(request.workspace_path.clone(), document, request.content.clone(), request.overwrite).await;
            let Some(this) = this.upgrade() else { return; };
            this.update(cx, |this, cx| this.complete_editor_write(request, result, cx));
        }).detach();
        cx.notify();
    }

    pub(super) fn begin_editor_write(&mut self, key: EditorKey, overwrite: bool, cx: &mut Context<Self>) -> Option<(EditorWrite, EditorDocument)> {
        if self.editor_workspaces.owner.as_deref() == Some(key.workspace.as_str()) && self.editor_loading_path.as_deref() == Some(key.path.as_str()) { return None; }
        let workspace_path = self.snapshot.workspace(&key.workspace)?.path.clone();
        let document = self.owned_editor_document(&key)?.clone();
        let input = self.owned_editor_input(&key)?;
        let content = input.read(cx).value().to_string();
        let request = self.editor_requests.begin_write(key, input.entity_id(), workspace_path, content, overwrite)?;
        self.sync_editor_busy();
        cx.notify();
        Some((request, document))
    }

    pub(super) fn complete_editor_write(&mut self, request: EditorWrite, result: Result<EditorDocument, String>, cx: &mut Context<Self>) {
        if !self.editor_requests.finish_write(&request) { return; }
        let live = self.snapshot.workspace(&request.key.workspace).is_some_and(|workspace| workspace.path == request.workspace_path)
            && self.owned_editor_input(&request.key).is_some_and(|input| input.entity_id() == request.editor);
        if !live { self.sync_editor_busy(); cx.notify(); return; }
        let selected = self.selected_editor_key().as_ref() == Some(&request.key);
        match result {
            Ok(document) if document.relative_path == request.key.path => {
                let mut state = WorkspaceEditors::take(self);
                self.editor_workspaces.accept_saved(&mut state, &request, document, cx);
                state.restore(self);
                if selected {
                    self.editor_conflict = false;
                    self.sync_selected_editor_from_cache();
                    self.local_message = Some(if request.overwrite { "File overwritten" } else { "File saved" }.into());
                    self.local_message_started_at = Some(std::time::Instant::now());
                }
                self.sync_editor_busy();
                if self.editor_is_visible(&request.key) { self.schedule_editor_autosave_path(&request.key.path, cx); }
            }
            result => {
                let error = result.err().unwrap_or_else(|| "Save returned a different document.".into());
                self.editor_requests.fail(&request, error.clone());
                if selected {
                    if super::editor_actions::is_editor_conflict(&error) {
                        self.editor_conflict = true;
                        self.local_message = None;
                    } else {
                        self.local_message = Some(error.into());
                        self.local_message_started_at = Some(std::time::Instant::now());
                    }
                }
                self.sync_editor_busy();
            }
        }
        cx.notify();
    }
}
