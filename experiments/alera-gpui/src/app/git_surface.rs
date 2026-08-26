use gpui::Context;

use super::context_source_control_dialog::SourceControlDialog;
use super::AleraApp;
use crate::workspace_service::GitAction;

pub(super) fn friendly_git_error(error: &str) -> String {
    let lower = error.to_ascii_lowercase();
    if lower.contains("not a git repository")
        || lower.contains("not a repository")
        || lower.contains(".git/worktrees")
        || error.starts_with('/')
        || lower.contains("/workspaces/")
    {
        "This workspace is not a Git repository.".to_owned()
    } else if lower.contains("detached head") {
        "Cannot push from detached HEAD.".to_owned()
    } else if lower.contains("remote origin") && lower.contains("not found") {
        "Remote origin was not found.".to_owned()
    } else if lower.contains("nothing to commit") {
        "Nothing to commit.".to_owned()
    } else if lower.contains("conflict") {
        "Resolve conflicts before continuing.".to_owned()
    } else {
        error.to_owned()
    }
}

impl AleraApp {
    pub(super) fn refresh_git(&mut self, cx: &mut Context<Self>) {
        self.refresh_git_internal(false, cx);
    }

    /// Manual refreshes use the same success feedback as Flutter's source
    /// control toolbar. Background refreshes keep silent so opening a
    /// workspace does not create a toast.
    pub(super) fn refresh_git_with_feedback(&mut self, cx: &mut Context<Self>) {
        self.refresh_git_internal(true, cx);
    }

    fn refresh_git_internal(&mut self, show_feedback: bool, cx: &mut Context<Self>) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        self.git_generation += 1;
        let generation = self.git_generation;
        self.git_busy = true;
        self.git_snapshot_loading = true;
        self.git_snapshot_error = None;
        let service = self.workspace_service.clone();
        cx.spawn(async move |this, cx| {
            let result = service.git_snapshot(workspace_path).await;
            let Some(this) = this.upgrade() else {
                return;
            };
            let _ = this.update(cx, |this, cx| {
                if generation != this.git_generation {
                    return;
                }
                this.git_busy = false;
                this.git_snapshot_loading = false;
                match result {
                    Ok(snapshot) => {
                        this.git_snapshot = snapshot;
                        this.git_snapshot_error = None;
                        this.local_message = show_feedback.then_some("Source control refreshed".into());
                    }
                    Err(error) => {
                        let message = friendly_git_error(&error);
                        this.git_snapshot_error = Some(message.clone().into());
                        this.local_message = None;
                    }
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
        self.git_generation += 1;
        let generation = self.git_generation;
        self.git_busy = true;
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
                if generation != this.git_generation {
                    return;
                }
                this.git_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(friendly_git_error(&error).into()),
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
        self.git_generation += 1;
        let generation = self.git_generation;
        self.git_busy = true;
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
                if generation != this.git_generation {
                    return;
                }
                this.git_busy = false;
                match result {
                    Ok(message) => {
                        this.local_message = Some(message.into());
                        if let Some(snapshot) = snapshot {
                            this.git_snapshot = snapshot;
                        }
                    }
                    Err(error) => this.local_message = Some(friendly_git_error(&error).into()),
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

#[cfg(test)]
mod tests {
    use super::friendly_git_error;

    #[test]
    fn maps_broken_worktrees_to_the_flutter_repository_message() {
        assert_eq!(
            friendly_git_error(
                "fatal: not a git repository: /private/tmp/alera/.git/worktrees/example"
            ),
            "This workspace is not a Git repository."
        );
        assert_eq!(
            friendly_git_error("/Users/leynier/.alera/workspaces/example"),
            "This workspace is not a Git repository."
        );
    }

    #[test]
    fn preserves_actionable_git_errors() {
        assert_eq!(
            friendly_git_error("Remote origin was not found."),
            "Remote origin was not found."
        );
        assert_eq!(
            friendly_git_error("fatal: You are not currently on a branch. detached HEAD"),
            "Cannot push from detached HEAD."
        );
        assert_eq!(
            friendly_git_error("fatal: merge conflict in src/main.rs"),
            "Resolve conflicts before continuing."
        );
    }
}
