//! Remote managed-workspace remove request adapter.

use alera_core::runtime::{RuntimeStore, Workspace};
use anyhow::{anyhow, bail, Result};

use crate::managed_workspace::{
    filesystem_entry_is_missing, workspace_has_active_automation_owner,
    ManagedWorkspaceRemoveRequest,
};
use crate::remote_managed_workspace::remove_remote_managed_workspace;
use crate::ssh_remote::{is_remote_host_id, RemoteHostExecutor};

/// If this workspace is a true remote managed worktree, remove it over SSH.
/// Returns `Ok(Some(removed))` when handled, `Ok(None)` when the caller should
/// use the local remove path.
///
/// Metadata-only rows that stamp a foreign `hostId` on a path that still exists
/// locally are refused (never remote-destroyed).
pub(crate) async fn try_remove_remote_managed_workspace<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
    workspace: &Workspace,
    executor: &E,
) -> Result<Option<Workspace>> {
    if !is_remote_host_id(Some(&workspace.host_id)) {
        return Ok(None);
    }
    if !filesystem_entry_is_missing(&workspace.path)? {
        bail!("Workspace is not owned by the local host");
    }
    if workspace_has_active_automation_owner(store, &workspace.id).await? {
        bail!("Workspace is owned by an active automation");
    }
    Ok(Some(
        remove_remote_managed_workspace_request(store, request, workspace, executor).await?,
    ))
}

pub(crate) async fn remove_remote_managed_workspace_request<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
    workspace: &Workspace,
    executor: &E,
) -> Result<Workspace> {
    let delete_branch = request.delete_branch.ok_or_else(|| {
        anyhow!("Choose --keep-branch (recommended) or --delete-branch before remote cleanup")
    })?;
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    let branch_to_delete = if delete_branch && !workspace.reuses_existing_branch {
        workspace
            .branch
            .as_deref()
            .filter(|branch| !branch.is_empty())
            .map(str::to_string)
    } else {
        None
    };
    remove_remote_managed_workspace(
        store,
        workspace,
        &project,
        branch_to_delete.as_deref(),
        executor,
    )
    .await?;
    store.remove_workspace(&workspace.id, true).await?;
    Ok(workspace.clone())
}
