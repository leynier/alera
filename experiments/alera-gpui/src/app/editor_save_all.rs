use gpui::{Context, EntityId};

use super::{AleraApp, editor_requests::EditorKey, editor_workspaces::WorkspaceEditors};

pub(super) struct EditorSaveTarget {
    pub key: EditorKey,
    pub editor: EntityId,
}

impl AleraApp {
    pub(super) fn save_all_editors(&mut self, cx: &mut Context<Self>) {
        if self.editor_save_all_busy { return; }
        let current = WorkspaceEditors::take(self);
        let targets = self.editor_workspaces.save_targets(&current, cx);
        current.restore(self);
        if targets.is_empty() {
            self.local_message = Some(save_all_message(0).into());
            self.local_message_started_at = Some(std::time::Instant::now());
            cx.notify();
            return;
        }
        self.editor_save_all_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let mut saved = 0;
            let mut failure = None;
            for target in targets {
                let next = {
                    let Some(app) = this.upgrade() else { return; };
                    app.update(cx, |app, cx| {
                        if app.owned_editor_input(&target.key).is_none_or(|input| input.entity_id() != target.editor)
                            || !app.owned_editor_is_dirty(&target.key, cx) { return None; }
                        app.begin_editor_write(target.key.clone(), false, cx)
                    })
                };
                let Some((request, document)) = next else { continue; };
                let result = service.write(request.workspace_path.clone(), document, request.content.clone(), false).await;
                let error = match &result {
                    Ok(document) if document.relative_path == request.key.path => None,
                    Ok(_) => Some("Save returned a different document.".to_owned()),
                    Err(error) => Some(error.clone()),
                };
                let Some(app) = this.upgrade() else { return; };
                let clean = app.update(cx, |app, cx| {
                    app.complete_editor_write(request, result, cx);
                    !app.owned_editor_is_dirty(&target.key, cx)
                });
                if let Some(error) = error {
                    failure = Some(format!("{}: {error}", target.key.path));
                    break;
                }
                if clean { saved += 1; }
            }
            let Some(app) = this.upgrade() else { return; };
            app.update(cx, |app, cx| {
                app.editor_save_all_busy = false;
                if !app.editor_conflict {
                    app.local_message = Some(failure.unwrap_or_else(|| save_all_message(saved)).into());
                    app.local_message_started_at = Some(std::time::Instant::now());
                }
                cx.notify();
            });
        }).detach();
        cx.notify();
    }
}

fn save_all_message(count: usize) -> String {
    match count {
        0 => "No unsaved editor files".into(),
        1 => "Saved 1 editor file".into(),
        count => format!("Saved {count} editor files"),
    }
}
