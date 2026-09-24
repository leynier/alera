use alera_core::runtime::{RuntimeStore, WorkspaceRelocation};
use anyhow::{anyhow, Result};

use super::OwnerRelocationRequest;

pub(super) async fn prepare(
    store: &RuntimeStore,
    request: &OwnerRelocationRequest,
    previous: Option<&WorkspaceRelocation>,
) -> Result<WorkspaceRelocation> {
    let mut intent = request.intent.clone();
    if !intent.to_project_checkout {
        let destination = if intent.destination_path.is_none() && request.workspace_root.is_none() {
            previous.map(|journal| journal.destination.path.clone())
        } else {
            None
        };
        intent.destination_path = Some(match destination {
            Some(path) => path,
            None => {
                let project = store
                    .find_project(&request.workspace.project_id)
                    .await?
                    .ok_or_else(|| anyhow!("Owner project is unavailable"))?;
                let branch = intent
                    .branch
                    .as_deref()
                    .ok_or_else(|| anyhow!("A branch is required"))?;
                crate::managed_workspace::resolve_workspace_path(
                    store,
                    &project,
                    branch,
                    &crate::managed_workspace::ManagedWorkspaceCreateRequest {
                        id: None,
                        project_id: project.id.clone(),
                        name: None,
                        branch: branch.into(),
                        source_branch: None,
                        reuse_existing_branch: intent.replacement_branch.is_some(),
                        workspace_root: request.workspace_root.clone(),
                        path: intent.destination_path.clone(),
                        parent_workspace_id: None,
                        host_id: None,
                        defer_setup: false,
                        skip_setup: false,
                        setup_script_directory: None,
                    },
                )
                .await?
            }
        });
    }
    let journal = store
        .prepare_local_workspace_relocation_with_id(intent, Some(request.relocation_id.to_string()))
        .await?;
    if !request.intent.to_project_checkout {
        let mut project = store
            .find_project(&request.workspace.project_id)
            .await?
            .ok_or_else(|| anyhow!("Owner project is unavailable"))?;
        project.repo_path = journal.repository_path.clone();
        if let Some(config) = &request.setup_config {
            crate::workspace_relocation_setup::prepare_with_config(
                store,
                &project,
                &journal.id,
                config.clone(),
            )
            .await?;
        } else {
            crate::workspace_relocation_setup::prepare(store, &project, &journal.id).await?;
        }
    }
    Ok(journal)
}
