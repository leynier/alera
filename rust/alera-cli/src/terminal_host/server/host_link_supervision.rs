//! The actor's half of the host link supervisor: it knows which hosts hold
//! active workspaces and which carry hub sessions, and hands both to
//! [`crate::terminal_host::host_link_supervisor`] on every tick.

use std::collections::HashSet;

use tokio::task::JoinHandle;

use crate::terminal_host::host_link_supervisor::desired_hosts;
use alera_core::runtime::SshBootstrapStatus;

use super::ServerActor;

impl ServerActor {
    /// Starts the sweep. Its first tick connects the desired hosts, staggered,
    /// from a spawned task.
    pub(super) fn start_host_link_supervisor(&self) -> JoinHandle<()> {
        self.host_links.spawn_supervisor(self.inbox.clone())
    }

    pub(super) async fn handle_host_link_supervisor_tick(&mut self) {
        let targets = match self.runtime_store.list_ssh_targets().await {
            Ok(targets) => targets,
            Err(error) => {
                tracing::warn!(target: "host_link", "host link sweep could not read SSH targets: {error}");
                return;
            }
        };
        let installed = targets
            .iter()
            .any(|target| target.bootstrap_status == SshBootstrapStatus::Installed);
        let desired = if installed {
            match self.runtime_store.list_all_workspaces().await {
                Ok(workspaces) => desired_hosts(&targets, &workspaces),
                Err(error) => {
                    tracing::warn!(target: "host_link", "host link sweep could not read workspaces: {error}");
                    return;
                }
            }
        } else {
            HashSet::new()
        };
        let mut busy = HashSet::new();
        for host_id in self.host_links.attached_host_ids() {
            if !self.sessions_on_host(&host_id).await.is_empty() {
                busy.insert(host_id);
            }
        }
        self.host_links.supervise(&desired, &busy);
    }
}
