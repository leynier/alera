//! What a satellite last said about the owner of a remote automation run.
//!
//! Reconciliation runs on the actor, so it must not wait on a host link: it
//! reads the answer cached here, asks again on a spawned task when the link is
//! attached, and treats a host without a link as unreachable for this tick
//! while the supervisor connects it. The answer comes back as
//! [`ServerCommand::AutomationRemoteOwnerStatus`], and a changed answer runs
//! reconciliation again so it does not wait for the next tick.

use std::time::Duration;

use alera_core::runtime::AutomationRun;
use serde_json::{json, Value};

use super::{ServerActor, ServerCommand};

/// How long a satellite gets to answer one owner question.
const OWNER_STATUS_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, Default)]
pub(super) struct RemoteOwnerState {
    host_id: String,
    state: Option<String>,
    asking: bool,
}

impl ServerActor {
    /// The cached owner state of `run` on `host`, refreshed in the
    /// background. `None` until a satellite has answered over a live link.
    pub(super) fn remote_owner_state(&mut self, run: &AutomationRun, host: &str) -> Option<String> {
        let Some(link) = self.host_links.attached_link(host) else {
            self.automation_remote_owner_states.remove(&run.id);
            self.host_links.request_connect(host);
            return None;
        };
        let entry = self
            .automation_remote_owner_states
            .entry(run.id.clone())
            .or_default();
        if entry.host_id != host {
            *entry = RemoteOwnerState {
                host_id: host.to_string(),
                ..RemoteOwnerState::default()
            };
        }
        let cached = entry.state.clone();
        if entry.asking {
            return cached;
        }
        entry.asking = true;
        let owner = json!({"sessionId": run.session_id, "workspaceId": run.workspace_id, "tabId": run.tab_id});
        let inbox = self.inbox.clone();
        let run_id = run.id.clone();
        let host_id = host.to_string();
        tokio::spawn(async move {
            let state = link
                .request_with_timeout("automation.ownerStatus", owner, OWNER_STATUS_TIMEOUT)
                .await
                .ok()
                .and_then(|value| {
                    value
                        .get("state")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                });
            let _ = inbox.send(ServerCommand::AutomationRemoteOwnerStatus {
                run_id,
                host_id,
                state,
            });
        });
        cached
    }

    /// Asks the satellite to end a run's terminal. Fire and forget: the next
    /// owner answer is what proves the terminal closed.
    pub(super) fn terminate_remote_owner(&self, host: &str, session_id: Option<&str>) {
        let Some(link) = self.host_links.attached_link(host) else {
            self.host_links.request_connect(host);
            return;
        };
        let payload = json!({"sessionId": session_id});
        tokio::spawn(async move {
            let _ = link
                .request_with_timeout("terminate", payload, OWNER_STATUS_TIMEOUT)
                .await;
        });
    }

    pub(super) async fn finish_automation_remote_owner_status(
        &mut self,
        run_id: String,
        host_id: String,
        state: Option<String>,
    ) {
        let Some(entry) = self.automation_remote_owner_states.get_mut(&run_id) else {
            return;
        };
        if entry.host_id != host_id {
            return;
        }
        entry.asking = false;
        if entry.state == state {
            return;
        }
        entry.state = state;
        self.reconcile_automation_runs().await;
    }
}
