//! `workspace.storageImpact` for a linked workspace on an SSH host.
//!
//! Its worktree lives on the satellite, so only the satellite can measure it
//! and check that it sits in Alera-managed storage there. Measuring it on the
//! hub always reported "Workspace is not owned by the local host", which made
//! the Remove action show Cleanup Unavailable for every remote worktree.

use alera_core::runtime::{RuntimeStore, WorkspaceKind};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

/// Measures a remote linked workspace on the host that owns it. `Ok(None)`
/// means the workspace is local (or a shared checkout) and the hub measures
/// it as before. `hub_blockers` are the checks only the hub can make, such as
/// its own sessions and automations; they come first in the answer.
pub(super) async fn measure_on_owner(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    workspace_id: &str,
    close_sessions: bool,
    hub_blockers: &[String],
) -> HostResult<Option<Value>> {
    let Some(workspace) = store
        .find_workspace(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
    else {
        return Ok(None);
    };
    if workspace.kind == WorkspaceKind::Main
        || !crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id))
    {
        return Ok(None);
    }
    let (link, _) = crate::terminal_host::server::host_link_routing::mirror_workspace(
        store,
        links,
        workspace_id,
    )
    .await?;
    let measured = link
        .request_with_timeout(
            "workspace.storageImpact",
            json!({ "id": workspace_id, "closeSessions": close_sessions }),
            crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
        )
        .await?;
    Ok(Some(merge_blockers(measured, workspace_id, hub_blockers)))
}

fn merge_blockers(mut measured: Value, workspace_id: &str, hub_blockers: &[String]) -> Value {
    let mut blockers: Vec<Value> = hub_blockers.iter().cloned().map(Value::String).collect();
    for blocker in measured["blockers"].as_array().into_iter().flatten() {
        if !blockers.contains(blocker) {
            blockers.push(blocker.clone());
        }
    }
    measured["workspaceId"] = json!(workspace_id);
    measured["safeToClean"] = json!(blockers.is_empty());
    measured["blockers"] = Value::Array(blockers);
    measured
}

#[cfg(all(test, unix))]
#[path = "remote_storage_impact_tests.rs"]
mod tests;
