//! Create task state on an existing project checkout without mutating Git.

use alera_core::runtime::{
    RuntimeStore, Workspace, WorkspaceCreationResult, WorkspaceKind, WorkspaceStatus,
    WorktreeSetupReport, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use serde::Deserialize;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedWorkspaceCreateRequest {
    pub project_id: String,
    pub id: Option<String>,
    pub name: Option<String>,
    pub host_id: Option<String>,
    pub parent_workspace_id: Option<String>,
}

pub async fn create_shared_workspace(
    store: &RuntimeStore,
    request: SharedWorkspaceCreateRequest,
) -> Result<WorkspaceCreationResult> {
    create_shared_workspace_with(store, request, &crate::ssh_remote::LiveSshRemoteHost).await
}

pub(crate) async fn create_shared_workspace_with<E: crate::ssh_remote::RemoteHostExecutor>(
    store: &RuntimeStore,
    request: SharedWorkspaceCreateRequest,
    executor: &E,
) -> Result<WorkspaceCreationResult> {
    let parent_id = request.parent_workspace_id.clone();
    let workspace = match prepare_shared_workspace_with(store, request, executor, false).await? {
        PreparedSharedWorkspace::Existing(workspace) => return Ok(created(workspace)),
        PreparedSharedWorkspace::New(workspace) => workspace,
    };
    let mut workspace = store.insert_workspace(workspace).await?;
    if let Some(parent_id) = parent_id {
        if let Err(error) = store.link_workspaces(&parent_id, &workspace.id).await {
            store.remove_workspace(&workspace.id, true).await?;
            return Err(error);
        }
        workspace = store
            .find_workspace(&workspace.id)
            .await?
            .ok_or_else(|| anyhow!("Workspace disappeared after creation"))?;
    }
    Ok(created(workspace))
}

enum PreparedSharedWorkspace {
    Existing(Workspace),
    New(Workspace),
}

pub(crate) async fn prepare_fresh_shared_workspace(
    store: &RuntimeStore,
    request: SharedWorkspaceCreateRequest,
) -> Result<Workspace> {
    match prepare_shared_workspace_with(store, request, &crate::ssh_remote::LiveSshRemoteHost, true)
        .await?
    {
        PreparedSharedWorkspace::New(workspace) => Ok(workspace),
        PreparedSharedWorkspace::Existing(_) => {
            bail!("Automation allocation cannot adopt an existing task")
        }
    }
}

async fn prepare_shared_workspace_with<E: crate::ssh_remote::RemoteHostExecutor>(
    store: &RuntimeStore,
    request: SharedWorkspaceCreateRequest,
    executor: &E,
    require_remote_automation_declaration: bool,
) -> Result<PreparedSharedWorkspace> {
    let project = store
        .find_project(&request.project_id)
        .await?
        .ok_or_else(|| anyhow!("Project not found: {}", request.project_id))?;
    let host_id =
        crate::project_hosts::workspace_host_id(store, &project, request.host_id.as_deref()).await;
    if let Some(parent_id) = request.parent_workspace_id.as_deref() {
        if store.find_workspace(parent_id).await?.is_none() {
            bail!("Parent workspace not found: {parent_id}");
        }
        if request.id.as_deref() == Some(parent_id) {
            bail!("Workspace cannot be related to itself");
        }
    }
    let inspection = if host_id == LOCAL_HOST_ID {
        crate::project_checkout_inspection::inspect(project.repo_path.clone(), project.kind).await?
    } else {
        let checkout = store.find_project_checkout(&project.id, &host_id).await?
            .ok_or_else(|| anyhow!("This project is not on that host yet. Add it first with `alera project hosts add --project-id {} --host-id {host_id}`, which clones it there, then create the workspace", project.id))?;
        let inspection = crate::remote_project_checkout::inspect_remote(
            store,
            &host_id,
            &checkout.path,
            project.kind,
            executor,
        )
        .await?;
        if !crate::windows_path_form::same_path(&inspection.path, &checkout.path) {
            bail!("The registered SSH checkout now resolves to a different directory; no task was created");
        }
        if require_remote_automation_declaration {
            match inspection.automation_declared {
                Some(true) => {}
                Some(false) => bail!(
                    "repository {} has no automation declaration in alera.toml",
                    project.id
                ),
                None => bail!(
                    "Update the SSH runtime to verify project checkout automation authorization"
                ),
            }
        }
        inspection
    };
    let path = inspection.path;
    let branch = inspection.branch;
    store
        .register_project_checkout(&project.id, &host_id, &path)
        .await?;
    let id = request
        .id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    if let Some(existing) = store.find_workspace(&id).await? {
        if existing.project_id != project.id
            || existing.host_id != host_id
            || !crate::windows_path_form::same_path(&existing.path, &path)
            || existing.kind != WorkspaceKind::Main
            || request
                .name
                .as_deref()
                .map(str::trim)
                .filter(|name| !name.is_empty())
                .is_some_and(|name| name != existing.name)
            || request.parent_workspace_id != existing.parent_workspace_id
        {
            bail!("Workspace ID is already used by a different task");
        }
        return Ok(PreparedSharedWorkspace::Existing(existing));
    }
    let name = match request
        .name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        Some(name) => name.to_string(),
        None => {
            let existing = store.list_workspaces(&project.id).await?;
            let mut index = 1;
            loop {
                let name = format!("Workspace {index}");
                if !existing.iter().any(|workspace| workspace.name == name) {
                    break name;
                }
                index += 1;
            }
        }
    };
    let now = Utc::now();
    let workspace = Workspace {
        id,
        instance_id: Uuid::new_v4().to_string(),
        project_id: project.id,
        host_id,
        name,
        path,
        branch,
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Main,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        is_archived: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    };
    Ok(PreparedSharedWorkspace::New(workspace))
}

fn created(workspace: Workspace) -> WorkspaceCreationResult {
    WorkspaceCreationResult {
        workspace,
        setup_report: WorktreeSetupReport::empty(),
        deferred_setup_command: None,
    }
}

#[cfg(test)]
#[path = "shared_workspace_tests.rs"]
mod tests;
