use alera_core::runtime::{RuntimeStore, WorkspaceRelocation, WorkspaceRelocationIntent};
use anyhow::{anyhow, bail, Result};

use crate::managed_workspace::{resolve_workspace_path, ManagedWorkspaceCreateRequest};
use crate::managed_workspace_handoff::ManagedWorkspaceHandOffRequest;

pub(super) async fn prepare_hand_off(
    store: &RuntimeStore,
    request: &ManagedWorkspaceHandOffRequest,
    move_changes: bool,
    replacement_branch: Option<String>,
) -> Result<WorkspaceRelocation> {
    if request.reuse_existing_branch != replacement_branch.is_some() {
        bail!(
            "Moving the current branch requires an explicit replacement branch; a new branch must not specify one"
        );
    }
    let workspace = store
        .find_workspace(&request.id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {}", request.id))?;
    if request
        .name
        .as_deref()
        .map(str::trim)
        .is_some_and(|name| !name.is_empty() && name != workspace.name)
    {
        bail!("Hand Off preserves the task name. Rename the task separately before relocating it.");
    }
    let project = store
        .find_project(&workspace.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project no longer exists"))?;
    let destination_path = resolve_workspace_path(
        store,
        &project,
        &request.branch,
        &ManagedWorkspaceCreateRequest {
            id: None,
            project_id: project.id.clone(),
            name: None,
            branch: request.branch.clone(),
            source_branch: None,
            reuse_existing_branch: request.reuse_existing_branch,
            workspace_root: request.workspace_root.clone(),
            path: request.path.clone(),
            parent_workspace_id: None,
            host_id: Some(workspace.host_id.clone()),
            defer_setup: request.defer_setup,
            skip_setup: false,
            setup_script_directory: request.setup_script_directory.clone(),
        },
    )
    .await?;
    store
        .prepare_local_workspace_relocation_with_id(
            WorkspaceRelocationIntent {
                workspace_id: workspace.id,
                to_project_checkout: false,
                destination_path: Some(destination_path),
                branch: Some(request.branch.clone()),
                replacement_branch,
                move_changes,
                shared_impact_confirmed: true,
            },
            request.relocation_id.clone(),
        )
        .await
}
