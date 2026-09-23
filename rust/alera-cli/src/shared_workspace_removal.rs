//! Removing a task on shared storage must never invoke Git or delete files.

use alera_core::runtime::{CheckoutKind, RuntimeStore, Workspace, WorkspaceKind, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Result};

use crate::managed_workspace::{
    workspace_has_active_automation_owner, ManagedWorkspaceRemoveRequest,
};

pub async fn validate_shared_workspace_removal(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
) -> Result<Workspace> {
    store.require_workspace_process_closure(&request.id).await?;
    validate_shared_workspace_removal_target(store, request).await
}

pub(crate) async fn validate_shared_workspace_removal_target(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
) -> Result<Workspace> {
    let workspace = store
        .find_workspace(&request.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {}", request.id))?;
    if workspace.kind != WorkspaceKind::Main {
        bail!("Shared task removal cannot remove a linked worktree workspace");
    }
    if request.delete_branch == Some(true) {
        bail!("Removing a shared workspace cannot delete its branch");
    }
    if !request.close_sessions && request.active_workspace_id.as_deref() == Some(&workspace.id) {
        bail!("Confirm closing this workspace before removing it");
    }
    let checkout = store
        .find_workspace_checkout(&workspace.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace checkout ownership could not be verified"))?;
    if checkout.kind != CheckoutKind::Project
        || checkout.host_id != workspace.host_id
        || checkout.project_id != workspace.project_id
    {
        bail!("Workspace checkout ownership changed; refresh and retry");
    }
    if workspace_has_active_automation_owner(store, &workspace.id).await? {
        bail!("Pause dependent automations and cancel active runs before removing this workspace");
    }
    Ok(workspace)
}

pub async fn remove_shared_workspace(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
) -> Result<Workspace> {
    let workspace = validate_shared_workspace_removal(store, request).await?;
    if workspace.host_id != LOCAL_HOST_ID {
        bail!("The SSH host must verify task process shutdown before removal");
    }
    store.retire_verified_shared_workspace(&workspace).await?;
    Ok(workspace)
}

pub(crate) async fn remove_after_remote_retirement(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
    proof: &crate::remote_shared_retirement::RemoteRetirementProof,
) -> Result<Workspace> {
    let workspace = validate_shared_workspace_removal(store, request).await?;
    proof.verify(&workspace)?;
    store.retire_verified_shared_workspace(&workspace).await?;
    Ok(workspace)
}
