//! Remote managed-workspace remove request adapter.

use alera_core::runtime::{RuntimeStore, Workspace};
use anyhow::{anyhow, Result};

use crate::managed_workspace::ManagedWorkspaceRemoveRequest;
use crate::remote_managed_workspace::remove_remote_managed_workspace;
use crate::ssh_remote::RemoteHostExecutor;

pub(crate) async fn remove_remote_managed_workspace_request<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
    workspace: &Workspace,
    executor: &E,
) -> Result<Workspace> {
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    let branch_to_delete = if request
        .delete_branch
        .unwrap_or(!workspace.reuses_existing_branch)
    {
        workspace.branch.clone()
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
