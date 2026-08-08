use gpui::Context;

use super::context_source_control_dialog::SourceControlDialog;
use super::AleraApp;
use crate::workspace_service::GitAction;

impl AleraApp {
    pub(super) fn refresh_git(&mut self, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.git_snapshot(workspace_path).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(snapshot) => {
                        this.git_snapshot = snapshot;
                        this.local_message = None;
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn run_git_action(&mut self, action: GitAction, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.git_action(workspace_path.clone(), action).await;
            let snapshot = if result.is_ok() {
                service.git_snapshot(workspace_path).await.ok()
            } else {
                None
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn run_git_path_actions(&mut self, actions: Vec<GitAction>, cx: &mut Context<Self>) {
        if actions.is_empty() {
            return;
        }
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.local_generation += 1;
        let generation = self.local_generation;
        self.local_busy = true;
        self.git_discard_armed = false;
        self.git_discard_path_armed = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let mut result = Ok("Updated Changes".to_owned());
            for action in actions {
                if let Err(error) = service.git_action(workspace_path.clone(), action).await {
                    result = Err(error);
                    break;
                }
            }
            let snapshot = if result.is_ok() {
                service.git_snapshot(workspace_path).await.ok()
            } else {
                None
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.local_generation {
                    return;
                }
                this.local_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(error.into()),
                }
                cx.notify();
            });
        })
        .detach();
    }

    pub(super) fn commit(&mut self, amend: bool, cx: &mut Context<Self>) {
        let message = self.commit_input.read(cx).value().trim().to_string();
        if message.is_empty() {
            self.local_message = Some("Enter A Commit Message".into());
            cx.notify();
            return;
        }
        let action = if amend {
            GitAction::Amend(message)
        } else {
            GitAction::Commit(message)
        };
        self.run_git_action(action, cx);
    }

    pub(super) fn request_discard_all(&mut self, cx: &mut Context<Self>) {
        self.source_control_dialog = Some(SourceControlDialog::DiscardAll);
        cx.notify();
    }

    pub(super) fn request_discard_path(&mut self, path: String, cx: &mut Context<Self>) {
        self.source_control_dialog = Some(SourceControlDialog::DiscardPath { path });
        cx.notify();
    }

    pub(super) fn request_discard_paths(&mut self, paths: Vec<String>, cx: &mut Context<Self>) {
        let target = paths
            .first()
            .and_then(|path| path.split('/').next())
            .unwrap_or("This Change Group")
            .to_owned();
        self.source_control_dialog = Some(SourceControlDialog::DiscardPaths { paths, target });
        cx.notify();
    }
}
