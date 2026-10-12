//! Keeps the links that should be up, up, and closes the ones nobody uses.
//!
//! A host is desired when its install finished and it has an active workspace,
//! or when the user pressed Connect. A desired host that is not paused gets a
//! link at startup and after every failure, on the backoff in
//! [`super::host_link_backoff`]. A host that is not desired, carries no hub
//! session and saw no request for [`HostLinkPolicy::idle_close`] is closed,
//! which leaves it `disconnected` rather than failed.
//!
//! The sweep is not a [`super::demand_driven_ticker::DemandDrivenTicker`]: the
//! link carries agent status relays and the reverse channel, which matter
//! while no client is watching.

use std::collections::HashSet;
use std::time::{Duration, Instant};

use alera_core::runtime::{SshBootstrapStatus, SshTarget, Workspace};
use tokio::task::JoinHandle;

use super::host_link_backoff::RetrySchedule;
use super::host_link_registry::HostLinkRegistry;
use super::server::ServerCommand;
use super::server::ServerInboxSendError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct HostLinkPolicy {
    pub(crate) retry: RetrySchedule,
    pub(crate) idle_close: Duration,
    pub(crate) sweep_interval: Duration,
    /// Spacing between connects started by one sweep, so a hub with many
    /// hosts does not open every ssh handshake at once.
    pub(crate) connect_stagger: Duration,
}

impl Default for HostLinkPolicy {
    fn default() -> Self {
        Self {
            retry: RetrySchedule::DEFAULT,
            idle_close: Duration::from_secs(10 * 60),
            sweep_interval: Duration::from_secs(30),
            connect_stagger: Duration::from_millis(250),
        }
    }
}

/// Hosts that should hold a link because of their workspaces: installed, and
/// home to at least one active workspace.
pub(crate) fn desired_hosts(targets: &[SshTarget], workspaces: &[Workspace]) -> HashSet<String> {
    let installed: HashSet<&str> = targets
        .iter()
        .filter(|target| target.bootstrap_status == SshBootstrapStatus::Installed)
        .map(|target| target.id.as_str())
        .collect();
    workspaces
        .iter()
        .filter(|workspace| crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)))
        .filter(|workspace| installed.contains(workspace.host_id.as_str()))
        .map(|workspace| workspace.host_id.clone())
        .collect()
}

impl HostLinkRegistry {
    /// Asks the supervisor to look again now instead of at the next sweep.
    pub(crate) fn reevaluate(&self) {
        self.wake.notify_one();
    }

    /// A failure that stopped retries (unknown or not installed target) no
    /// longer holds once the target is installed.
    pub(crate) fn clear_configuration_failure(&self, host_id: &str) {
        let Some(slot) = self.existing_slot(host_id) else {
            return;
        };
        {
            let mut state = slot.lock();
            if state.failure_kind.is_some_and(|kind| !kind.retries()) {
                state.failure_kind = None;
                state.last_error = None;
            }
        }
        self.publish(host_id, false);
        self.reevaluate();
    }

    /// Runs until the inbox closes: one tick right away, then one per sweep
    /// interval or [`Self::reevaluate`].
    pub(crate) fn spawn_supervisor(
        &self,
        inbox: crate::terminal_host::ServerInbox,
    ) -> JoinHandle<()> {
        let wake = self.wake.clone();
        let interval = self.policy.sweep_interval;
        tokio::spawn(async move {
            loop {
                if let Err(ServerInboxSendError::Closed) =
                    inbox.send_wait(ServerCommand::HostLinkSupervisorTick).await
                {
                    break;
                }
                tokio::select! {
                    _ = tokio::time::sleep(interval) => {}
                    _ = wake.notified() => {}
                }
            }
        })
    }

    /// Applies one sweep: records which hosts are desired and busy, starts
    /// connects for desired hosts without a link, drops retries nobody wants
    /// any more, and closes idle links.
    pub(crate) fn supervise(&self, desired: &HashSet<String>, busy: &HashSet<String>) {
        let mut ids = self.host_ids();
        for id in desired {
            if !ids.contains(id) {
                ids.push(id.clone());
            }
        }
        let now = Instant::now();
        let mut connect = Vec::new();
        let mut idle = Vec::new();
        for host_id in ids {
            let slot = self.slot(&host_id);
            let changed = {
                let mut state = slot.lock();
                let mut changed = state.desired != desired.contains(&host_id);
                state.desired = desired.contains(&host_id);
                state.busy = busy.contains(&host_id);
                if state.wants_link() {
                    let blocked = state
                        .failure_kind
                        .is_some_and(|kind| !kind.retries() && state.last_error.is_some());
                    if state.live_link().is_none()
                        && state.attempt.is_none()
                        && state.retry.is_none()
                        && !blocked
                    {
                        connect.push(host_id.clone());
                    }
                } else {
                    changed |= state.cancel_retry();
                    let expired = state.last_used.is_none_or(|used| {
                        now.saturating_duration_since(used) >= self.policy.idle_close
                    });
                    if !state.busy && expired {
                        if let Some(link) = state.live_link() {
                            state.take_link();
                            state.last_error = None;
                            state.failure_kind = None;
                            idle.push((host_id.clone(), link));
                            changed = true;
                        }
                    }
                }
                changed
            };
            if changed {
                self.publish(&host_id, false);
            }
        }
        for (host_id, link) in idle {
            tracing::info!(target: "host_link", host_id, "closing idle host link");
            tokio::spawn(async move { link.close().await });
        }
        if connect.is_empty() {
            return;
        }
        let registry = self.clone();
        let stagger = self.policy.connect_stagger;
        tokio::spawn(async move {
            for (index, host_id) in connect.into_iter().enumerate() {
                if index > 0 {
                    tokio::time::sleep(stagger).await;
                }
                registry.request_connect(&host_id);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::json;

    fn target(id: &str, status: SshBootstrapStatus) -> SshTarget {
        let mut target: SshTarget = serde_json::from_value(json!({
            "id": id, "alias": id, "host": "h", "port": 22, "username": "u", "authKind": "agent",
            "createdAt": Utc::now(), "updatedAt": Utc::now(),
        }))
        .unwrap();
        target.bootstrap_status = status;
        target
    }

    fn workspace(id: &str, host_id: &str) -> Workspace {
        serde_json::from_value(json!({
            "id": id, "instanceId": format!("{id}-instance"), "hostId": host_id,
            "projectId": "p", "name": id, "path": "/w", "createdAt": Utc::now(),
            "updatedAt": Utc::now(), "kind": "main", "status": "active",
            "reusesExistingBranch": false, "isPinned": false, "isArchived": false,
        }))
        .unwrap()
    }

    #[test]
    fn installed_hosts_with_a_workspace_are_desired() {
        let targets = [
            target("lab", SshBootstrapStatus::Installed),
            target("mac", SshBootstrapStatus::Installed),
            target("new", SshBootstrapStatus::NotInstalled),
            target("broken", SshBootstrapStatus::Failed),
        ];
        let workspaces = [
            workspace("a", "lab"),
            workspace("b", "lab"),
            workspace("c", "new"),
            workspace("d", "broken"),
            workspace("e", "local"),
            workspace("f", "ghost"),
        ];
        let desired = desired_hosts(&targets, &workspaces);
        assert_eq!(desired, HashSet::from(["lab".to_string()]));
        assert!(desired_hosts(&targets, &[]).is_empty());
    }

    #[test]
    fn the_default_policy_matches_the_documented_timings() {
        let policy = HostLinkPolicy::default();
        assert_eq!(policy.idle_close, Duration::from_secs(600));
        assert_eq!(policy.sweep_interval, Duration::from_secs(30));
        assert_eq!(policy.connect_stagger, Duration::from_millis(250));
        assert_eq!(policy.retry, RetrySchedule::DEFAULT);
    }
}
