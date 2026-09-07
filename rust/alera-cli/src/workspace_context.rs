use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceStatus};
use anyhow::{anyhow, bail, Result};

use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::workspace_id_env;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceContext {
    pub workspace_id: String,
    pub project_id: String,
    pub name: String,
    pub branch: Option<String>,
    pub source_branch: Option<String>,
    pub path: String,
}

impl WorkspaceContext {
    pub fn from_workspace(workspace: Workspace) -> Result<Self> {
        if workspace.status != WorkspaceStatus::Active {
            bail!("Workspace is not active: {}", workspace.id);
        }
        Ok(Self {
            workspace_id: workspace.id,
            project_id: workspace.project_id,
            name: workspace.name,
            branch: workspace.branch,
            source_branch: workspace.source_branch,
            path: workspace.path,
        })
    }

    pub fn source_branch(&self) -> Option<&str> {
        self.branch
            .as_deref()
            .or(self.source_branch.as_deref())
            .map(str::trim)
            .filter(|value| !value.is_empty())
    }
}

pub fn requested_workspace_id(explicit: Option<&str>) -> Option<String> {
    explicit
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .or_else(workspace_id_env)
}

pub async fn resolve_workspace_context(
    runtime: &RuntimeDirArgs,
    workspace_id: Option<&str>,
) -> Result<WorkspaceContext> {
    let Some(workspace_id) = requested_workspace_id(workspace_id) else {
        bail!(
            "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        );
    };
    let store = RuntimeStore::open(&crate::runtime_dir(runtime)).await?;
    let workspace = store
        .find_workspace(&workspace_id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found: {workspace_id}"))?;
    WorkspaceContext::from_workspace(workspace)
}

pub async fn resolve_optional_workspace_context(
    runtime: &RuntimeDirArgs,
    workspace_id: Option<&str>,
) -> Result<Option<WorkspaceContext>> {
    if requested_workspace_id(workspace_id).is_none() {
        return Ok(None);
    }
    resolve_workspace_context(runtime, workspace_id)
        .await
        .map(Some)
}

#[cfg(test)]
#[path = "workspace_context_tests.rs"]
mod tests;
