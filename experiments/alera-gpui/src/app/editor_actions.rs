use std::path::Path;

use gpui::{Context, Window};

use super::AleraApp;

pub(super) fn is_editor_conflict(error: &str) -> bool {
    let normalized = error.to_ascii_lowercase();
    normalized.contains("workspace file conflict")
        || normalized.contains("file changed on disk")
        || normalized.contains("content token")
}

impl AleraApp {
    pub(super) fn schedule_editor_autosave(&mut self, cx: &mut Context<Self>) {
        for path in self.editor_inputs.keys().cloned().collect::<Vec<_>>() {
            self.schedule_editor_autosave_path(&path, cx);
        }
    }

    pub(super) fn schedule_editor_autosave_path(&mut self, path: &str, cx: &mut Context<Self>) {
        let Some(workspace) = self.editor_workspaces.owner.clone() else { return; };
        let key = super::editor_requests::EditorKey { workspace, path: path.to_owned() };
        self.editor_requests.cancel_auto(&key);
        if !self.settings_state.editor_autosave_enabled || !self.editor_dirty_paths.contains(path)
            || !self.editor_is_visible(&key) || self.editor_loading_path.as_deref() == Some(path)
            || self.editor_requests.is_writing(&key) || self.editor_requests.failure(&key).is_some() { return; }
        let Some(input) = self.owned_editor_input(&key) else { return; };
        let request = self.editor_requests.schedule_auto(key, input.entity_id());
        let owner_epoch = self.editor_autosave_generation;
        let delay = std::time::Duration::from_secs(self.settings_state.editor_autosave_delay_seconds.clamp(1, 60) as u64);
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(delay).await;
            let Some(this) = this.upgrade() else { return; };
            this.update(cx, |this, cx| {
                if !this.editor_requests.take_auto(&request) || owner_epoch != this.editor_autosave_generation
                    || !this.settings_state.editor_autosave_enabled || !this.editor_is_visible(&request.key)
                    || !this.editor_dirty_paths.contains(&request.key.path)
                    || this.owned_editor_input(&request.key).is_none_or(|input| input.entity_id() != request.editor) { return; }
                this.save_editor_key(request.key, false, cx);
            });
        }).detach();
    }

    pub(super) fn discard_editor_changes(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.sync_editor_busy();
        if self.editor_busy {
            return;
        }
        let Some(document) = self.editor_document.clone() else {
            return;
        };
        let editor_input = self.editor_input_for_path(&document.relative_path);
        self.editor_input_syncing = true;
        editor_input.update(cx, |input, cx| {
            input.set_value(document.display_content.clone(), window, cx);
        });
        self.editor_input_syncing = false;
        self.editor_buffer_text.remove(&document.relative_path);
        self.editor_dirty_paths.remove(&document.relative_path);
        self.editor_dirty = false;
        self.editor_conflict = false;
        if let Some(key) = self.selected_editor_key() {
            self.editor_requests.cancel_auto(&key);
            self.editor_requests.clear_failure(&key);
        }
        self.local_message = Some("Changes discarded".into());
        cx.notify();
    }

    pub(super) fn open_editor_preview(&mut self, cx: &mut Context<Self>) {
        if self.preview_asset.is_none() {
            return;
        }
        if self.opened_file_path.as_deref().is_some_and(|path| {
            matches!(
                Path::new(path)
                    .extension()
                    .and_then(|extension| extension.to_str()),
                Some("mmd" | "mermain" | "mermaid")
            )
        }) {
            if let Some(path) = self.opened_file_path.clone() {
                self.open_merman_preview_tab(path, cx);
            }
            return;
        }
        if self
            .opened_file_path
            .as_deref()
            .is_some_and(|path| path.ends_with(".md") || path.ends_with(".mdx"))
        {
            if let Some(path) = self.opened_file_path.clone() {
                self.open_markdown_viewer_tab(path, cx);
            }
            return;
        }
        self.show_preview = true;
        cx.notify();
    }

    pub(super) fn open_editor_diff(&mut self, cx: &mut Context<Self>) {
        let Some(path) = self.opened_file_path.clone() else {
            return;
        };
        let Some(scope) = self.selected_source_control_scope() else {
            self.local_message = Some("No Git diff for this file".into());
            cx.notify();
            return;
        };
        let Some(source_path) = scope.to_source_relative_path(&path) else {
            self.local_message = Some("No Git diff for this file".into());
            cx.notify();
            return;
        };
        self.open_git_diff_tab(Some(source_path), None, cx);
    }

    pub(super) fn cancel_editor_conflict(&mut self, target: &super::editor_requests::EditorConfirmation, cx: &mut Context<Self>) {
        if self.selected_editor_key().as_ref() != Some(&target.key)
            || self.editor_requests.confirmation(&target.key).as_ref() != Some(target) { return; }
        self.editor_conflict = false;
        cx.notify();
    }

    pub(super) fn confirm_editor_overwrite(&mut self, target: &super::editor_requests::EditorConfirmation, cx: &mut Context<Self>) {
        self.sync_editor_busy();
        if self.editor_busy || !self.editor_conflict
            || self.selected_editor_key().as_ref() != Some(&target.key)
            || self.editor_requests.confirmation(&target.key).as_ref() != Some(target)
            || self.owned_editor_input(&target.key).is_none_or(|input| input.entity_id() != target.editor) {
            return;
        }
        self.editor_conflict = false;
        self.save_editor(true, cx);
    }
}
