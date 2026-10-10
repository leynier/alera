//! The deferred worktree setup of a From Prompt workspace, started by the
//! host in a tab named "Setup" as the app does after a launch.
//!
//! The setup runs at most once. Its tab id is saved before the tab is
//! created, so a launch retry after a lost answer or a restart finds the tab
//! it may already have started; when that tab is gone (a successful setup
//! closes it) the host cannot tell, so it leaves the command to the user
//! instead of running the project's setup a second time.

use serde_json::{json, Value};
use uuid::Uuid;

use super::prompt_workspace_pipeline::{PromptWorkspaceRun, Stop, SHORT_DEADLINE};

const UNCONFIRMED_WARNING: &str =
    "The worktree setup may not have run. Run it from the workspace's Setup action if it is missing.";

/// What the Setup step does with the record it finds.
#[derive(Debug, PartialEq, Eq)]
enum SetupStep {
    /// Nothing to start, already started, or left to the user.
    Skip,
    /// A first attempt.
    Start(String),
    /// An earlier attempt claimed this tab id; it may have started.
    Reconcile { command: String, tab_id: String },
}

fn setup_step(setup: Option<&Value>) -> SetupStep {
    let Some(setup) = setup else {
        return SetupStep::Skip;
    };
    if setup.get("tabId").is_some() || setup.get("unconfirmed").is_some() {
        return SetupStep::Skip;
    }
    let Some(command) = setup["command"].as_str().map(str::to_owned) else {
        return SetupStep::Skip;
    };
    match setup["pendingTabId"].as_str() {
        Some(tab_id) => SetupStep::Reconcile {
            command,
            tab_id: tab_id.to_owned(),
        },
        None => SetupStep::Start(command),
    }
}

fn unconfirmed(command: &str) -> Value {
    json!({ "command": command, "unconfirmed": true })
}

impl PromptWorkspaceRun {
    pub(super) async fn start_setup(&mut self, workspace_id: &str) {
        let command = match setup_step(self.operation.setup.as_ref()) {
            SetupStep::Skip => return,
            SetupStep::Reconcile { command, tab_id } => {
                let started = self
                    .store
                    .list_workspace_tabs(workspace_id)
                    .await
                    .is_ok_and(|tabs| tabs.iter().any(|tab| tab.id == tab_id));
                if started {
                    self.operation.setup = Some(json!({ "tabId": tab_id }));
                } else {
                    self.operation.setup = Some(unconfirmed(&command));
                    self.operation.warnings.push(UNCONFIRMED_WARNING.to_owned());
                }
                self.save().await;
                return;
            }
            SetupStep::Start(command) => command,
        };
        if self.set_phase("startingSetup").await.is_err() {
            return;
        }
        let tab_id = Uuid::new_v4().to_string();
        self.operation.setup = Some(json!({ "command": command, "pendingTabId": tab_id }));
        self.save().await;
        let now = chrono::Utc::now().to_rfc3339();
        let tab = json!({
            "id": tab_id,
            "workspaceId": workspace_id,
            "kind": "terminal",
            "title": "Setup",
            "createdAt": now,
            "updatedAt": now,
            "payload": {
                "terminalSessionId": tab_id,
                "manualTitle": true,
                "initialCommand": command,
                "initialCommandOnce": true,
                "spawnOnCreate": true,
                "autoCloseOnSuccess": true,
            },
        });
        match self
            .call_to_completion("tab.upsert", tab, SHORT_DEADLINE)
            .await
        {
            Ok(_) => self.operation.setup = Some(json!({ "tabId": tab_id })),
            Err(Stop::Failed(error)) => {
                // A timeout may still have started it, so it is not retried.
                self.operation.setup = Some(unconfirmed(&command));
                self.operation
                    .warnings
                    .push(format!("The worktree setup did not start: {error}"));
            }
            Err(Stop::Cancelled) => {}
        }
        self.save().await;
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{setup_step, SetupStep};

    #[test]
    fn a_first_attempt_starts_and_a_claimed_tab_is_reconciled() {
        assert_eq!(setup_step(None), SetupStep::Skip);
        assert_eq!(
            setup_step(Some(&json!({ "command": "make setup" }))),
            SetupStep::Start("make setup".into())
        );
        assert_eq!(
            setup_step(Some(
                &json!({ "command": "make setup", "pendingTabId": "t-1" })
            )),
            SetupStep::Reconcile {
                command: "make setup".into(),
                tab_id: "t-1".into()
            }
        );
    }

    #[test]
    fn a_started_or_unconfirmed_setup_is_never_run_again() {
        assert_eq!(
            setup_step(Some(&json!({ "tabId": "t-1" }))),
            SetupStep::Skip
        );
        assert_eq!(
            setup_step(Some(
                &json!({ "command": "make setup", "unconfirmed": true })
            )),
            SetupStep::Skip
        );
    }
}
