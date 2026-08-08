use gpui::{Context, Window};

use super::AleraApp;

pub(super) fn is_editor_conflict(error: &str) -> bool {
    let normalized = error.to_ascii_lowercase();
    normalized.contains("workspace file conflict")
        || normalized.contains("file changed on disk")
        || normalized.contains("content token")
}

impl AleraApp {
    pub(super) fn discard_editor_changes(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.local_busy {
            return;
        }
        let Some(document) = self.editor_document.clone() else {
            return;
        };
        self.editor_input.update(cx, |input, cx| {
            input.set_value(document.display_content.clone(), window, cx);
        });
        self.editor_dirty = false;
        self.editor_conflict = false;
        self.local_message = Some("Changes Discarded".into());
        cx.notify();
    }

    pub(super) fn open_editor_preview(&mut self, cx: &mut Context<Self>) {
        if self.preview_asset.is_none() {
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
            self.local_message = Some("No Git Diff For This File".into());
            cx.notify();
            return;
        };
        let Some(source_path) = scope.to_source_relative_path(&path) else {
            self.local_message = Some("No Git Diff For This File".into());
            cx.notify();
            return;
        };
        self.open_git_diff_tab(Some(source_path), None, cx);
    }

    pub(super) fn cancel_editor_conflict(&mut self, cx: &mut Context<Self>) {
        self.editor_conflict = false;
        cx.notify();
    }

    pub(super) fn confirm_editor_overwrite(&mut self, cx: &mut Context<Self>) {
        if self.local_busy {
            return;
        }
        self.editor_conflict = false;
        self.save_editor(true, cx);
    }
}
