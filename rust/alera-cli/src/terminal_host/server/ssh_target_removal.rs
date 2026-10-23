//! `sshTarget.remove`: forgetting a host the hub no longer uses.
//!
//! A host that still holds active workspaces or project checkouts is refused
//! with `sshTargetInUse`, because removing the target would strand records
//! that route through it. There is no force path: `project.hosts.remove` and
//! workspace removal already carry the rules for taking those away. Once the
//! host is free, its install job is cancelled, the satellite is told to stop
//! treating this hub as its source of truth (`hub.unlink`, best effort and
//! only over a link that is already up), and the registry forgets the host.

use std::time::Duration;

use alera_core::runtime::{SshTarget, SshTargetReferences};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;
use crate::terminal_host::protocol::RUNTIME_HOST_REMOTE_SATELLITE_UNLINK_CAPABILITY;

use super::requests::require_string_key;
use super::ServerActor;

const UNLINK_TIMEOUT: Duration = Duration::from_secs(10);

impl ServerActor {
    pub(super) async fn ssh_target_remove(&mut self, payload: &Value) -> HostResult<Value> {
        let id = require_string_key(payload, "id")?;
        let target = self
            .runtime_store
            .find_ssh_target(&id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?
            .ok_or_else(|| HostError::state(format!("ssh target not found: {id}")))?;
        let references = self
            .runtime_store
            .ssh_target_references(&id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?;
        if !references.is_empty() {
            let remote_only = self.remote_only_projects(&id, &references).await?;
            return Err(ssh_target_in_use(&target, &references, &remote_only));
        }
        self.cancel_ssh_bootstrap_job_before_remove(&id).await?;
        self.runtime_store
            .remove_ssh_target(&id)
            .await
            .map_err(|error| HostError::from_anyhow(&error))?;
        let links = self.host_links.clone();
        let host_id = id.clone();
        tokio::spawn(async move {
            unlink_satellite(&links, &host_id).await;
            links.drop_host(&host_id).await;
        });
        self.broadcast_ssh_targets_changed(Some(&id));
        Ok(json!({}))
    }

    /// Projects whose primary checkout is on this host: removing the host
    /// from them is not enough, the project itself has to go.
    async fn remote_only_projects(
        &self,
        host_id: &str,
        references: &SshTargetReferences,
    ) -> HostResult<Vec<String>> {
        let mut remote_only = Vec::new();
        for project_id in &references.project_ids {
            let project = self
                .runtime_store
                .find_project(project_id)
                .await
                .map_err(|error| HostError::from_anyhow(&error))?;
            let Some(project) = project else {
                continue;
            };
            let checkouts = self
                .runtime_store
                .list_project_checkouts(project_id)
                .await
                .map_err(|error| HostError::from_anyhow(&error))?;
            if crate::project_hosts::primary_host_id(&project.repo_path, &checkouts) == host_id {
                remote_only.push(project_id.clone());
            }
        }
        Ok(remote_only)
    }
}

pub(crate) fn ssh_target_in_use(
    target: &SshTarget,
    references: &SshTargetReferences,
    remote_only_project_ids: &[String],
) -> HostError {
    let projects = references.project_ids.len();
    let workspaces = references.workspace_count;
    HostError::conflict(
        "sshTargetInUse",
        format!(
            "{} still has {} and {}. Remove them first.",
            target.alias,
            counted(projects, "project"),
            counted(workspaces, "workspace"),
        ),
        json!({
            "hostId": target.id,
            "alias": target.alias,
            "workspaceCount": workspaces,
            "checkoutCount": references.checkout_count,
            "projectIds": references.project_ids,
            "remoteOnlyProjectIds": remote_only_project_ids,
        }),
    )
}

fn counted(count: usize, noun: &str) -> String {
    if count == 1 {
        format!("1 {noun}")
    } else {
        format!("{count} {noun}s")
    }
}

/// Clears `satelliteOfHub` on the host so its CLI stops asking a hub that
/// forgot it. Skipped when no link is up or the runtime there predates the
/// verb; the host then keeps answering "no desktop linked" until it is
/// linked again, which is the safe failure.
async fn unlink_satellite(links: &HostLinkRegistry, host_id: &str) {
    let Some(link) = links.peek_link(host_id) else {
        return;
    };
    let supported = link
        .attachment()
        .runtime_capabilities
        .iter()
        .any(|capability| capability == RUNTIME_HOST_REMOTE_SATELLITE_UNLINK_CAPABILITY);
    if !supported {
        return;
    }
    if let Err(error) = link
        .request_with_timeout("hub.unlink", json!({}), UNLINK_TIMEOUT)
        .await
    {
        tracing::warn!(target: "host_link", host_id, "could not unlink the removed host: {error}");
    }
}

#[cfg(test)]
#[path = "ssh_target_removal_tests.rs"]
mod tests;
