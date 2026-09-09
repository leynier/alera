//! Validate branch deletion and worktree ownership before destructive cleanup.

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, WorkspaceKind, LOCAL_HOST_ID};
use anyhow::{anyhow, bail, Context, Result};

use super::{
    filesystem_entry_is_missing, path_equals, validate_workspace_storage_ownership,
    workspace_has_active_automation_owner, ManagedWorkspaceRemoval, ManagedWorkspaceRemoveRequest,
};

pub(super) async fn managed_workspace_removal(
    store: &RuntimeStore,
    request: &ManagedWorkspaceRemoveRequest,
) -> Result<ManagedWorkspaceRemoval> {
    let workspace = store
        .find_workspace(&request.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {}", request.id))?;
    if workspace.kind == WorkspaceKind::Main {
        bail!("The main workspace cannot be removed");
    }
    if workspace.host_id != LOCAL_HOST_ID {
        bail!("Workspace is not owned by the local host");
    }
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", workspace.project_id))?;
    let should_delete_branch = request.delete_branch.unwrap_or(false);
    if request.delete_branch.is_none() && !workspace.reuses_existing_branch {
        bail!("Branch deletion requires a choice: use --keep-branch (recommended) or --delete-branch. No worktree was removed.");
    }
    if should_delete_branch && workspace.reuses_existing_branch {
        bail!("This workspace reuses a branch it does not own. Keep the branch when removing the workspace.");
    }
    if should_delete_branch {
        let home = core_git::default_branch(&project.repo_path)?;
        if workspace.branch.as_deref() == Some(home.as_str()) {
            bail!("The default branch must be kept");
        }
        if filesystem_entry_is_missing(&workspace.path)? {
            bail!("Cannot verify the removed worktree's live branch. Retry with --keep-branch.");
        }
    }
    let branch_to_delete = if should_delete_branch {
        Some(
            workspace
                .branch
                .as_deref()
                .filter(|branch| !branch.is_empty())
                .ok_or_else(|| anyhow!("Workspace Branch Is Required"))?
                .to_string(),
        )
    } else {
        None
    };
    validate_workspace_storage_ownership(store, &workspace, &project).await?;
    if workspace_has_active_automation_owner(store, &workspace.id).await? {
        bail!("Workspace is owned by an active automation");
    }
    if !filesystem_entry_is_missing(&workspace.path)? {
        let registered = core_git::list_worktrees(&project.repo_path)?
            .into_iter()
            .find(|entry| path_equals(&entry.path, &workspace.path))
            .ok_or_else(|| anyhow!("Workspace path is not a registered Git worktree"))?;
        if let Some(expected_branch) = branch_to_delete.as_deref() {
            if registered.branch != expected_branch {
                bail!(
                    "Workspace branch does not match registered worktree: expected {expected_branch}, found {}",
                    registered.branch
                );
            }
        }
    }
    if let Some(branch) = branch_to_delete.as_deref() {
        core_git::validate_branch_deletion(&project.repo_path, branch, false, Some(&workspace.path))
            .context("Branch deletion is unsafe or could not be verified. Choose Keep Branch; no work was removed")?;
    }
    Ok(ManagedWorkspaceRemoval {
        workspace,
        project,
        branch_to_delete,
    })
}
