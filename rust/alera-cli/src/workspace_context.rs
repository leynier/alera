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

pub async fn resolve_requested_workspace_id(
    runtime: &RuntimeDirArgs,
    explicit: Option<&str>,
) -> Result<Option<String>> {
    if let Some(id) = explicit.map(str::trim).filter(|id| !id.is_empty()) {
        return Ok(Some(id.to_string()));
    }
    let tab_id = std::env::var("ALERA_TAB_ID").ok();
    let session_id = std::env::var("ALERA_TERMINAL_SESSION_ID").ok();
    if tab_id.is_none() && session_id.is_none() {
        return Ok(workspace_id_env());
    }
    let store = RuntimeStore::open(&crate::runtime_dir(runtime)).await?;
    resolve_tab_workspace(
        &store,
        tab_id.as_deref(),
        session_id.as_deref(),
        workspace_id_env().as_deref(),
    )
    .await
    .map(Some)
}

async fn resolve_tab_workspace(
    store: &RuntimeStore,
    tab_id: Option<&str>,
    session_id: Option<&str>,
    launched_workspace: Option<&str>,
) -> Result<String> {
    let (Some(tab_id), Some(session_id)) = (tab_id, session_id) else {
        bail!("Terminal identity is incomplete. Pass an explicit workspace ID.");
    };
    let tab = store
        .find_workspace_tab(tab_id)
        .await?
        .ok_or_else(|| anyhow!("Terminal tab no longer exists. Pass an explicit workspace ID."))?;
    if tab.payload["terminalSessionId"].as_str().unwrap_or(&tab.id) != session_id {
        bail!("Terminal session identity changed. Pass an explicit workspace ID.");
    }
    if launched_workspace.is_some_and(|id| {
        id != tab.workspace_id
            && !tab.payload["handoffSourceWorkspaceIds"]
                .as_array()
                .is_some_and(|ids| ids.iter().any(|value| value.as_str() == Some(id)))
    }) {
        bail!("Terminal workspace identity does not match the stored owner. Pass an explicit workspace ID.");
    }
    Ok(tab.workspace_id)
}

pub async fn resolve_workspace_context(
    runtime: &RuntimeDirArgs,
    workspace_id: Option<&str>,
) -> Result<WorkspaceContext> {
    let Some(workspace_id) = resolve_requested_workspace_id(runtime, workspace_id).await? else {
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
    if resolve_requested_workspace_id(runtime, workspace_id)
        .await?
        .is_none()
    {
        return Ok(None);
    }
    resolve_workspace_context(runtime, workspace_id)
        .await
        .map(Some)
}

#[cfg(test)]
#[path = "workspace_context_tests.rs"]
mod tests;
