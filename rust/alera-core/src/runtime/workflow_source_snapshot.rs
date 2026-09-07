use anyhow::{anyhow, bail, Result};
use serde::Serialize;

use super::{ProjectKind, RuntimeStore, WorkflowSourceWorkspace, WorkspaceStatus, LOCAL_HOST_ID};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowSourceSnapshot {
    pub workspace: WorkflowSourceWorkspace,
    pub sha: String,
    pub has_uncommitted_changes: bool,
}

impl RuntimeStore {
    pub async fn workflow_source_snapshot(
        &self,
        workspace_id: &str,
    ) -> Result<WorkflowSourceSnapshot> {
        super::workflow_plan::workflow_text(workspace_id, 160)?;
        let workspace = self
            .find_workspace(workspace_id)
            .await?
            .ok_or_else(|| anyhow!("workflow workspace not found"))?;
        let project = self
            .find_project(&workspace.project_id)
            .await?
            .ok_or_else(|| anyhow!("workflow project not found"))?;
        if workspace.status != WorkspaceStatus::Active
            || workspace.host_id != LOCAL_HOST_ID
            || project.kind != ProjectKind::GitRepository
        {
            bail!("workflows require an active local Git workspace");
        }
        super::workflow_catalog::workflow_blocking(move || {
            let repo = git2::Repository::open(&workspace.path)
                .map_err(|_| anyhow!("workflow source repository is unavailable"))?;
            let commit = repo
                .head()
                .and_then(|head| head.peel_to_commit())
                .map_err(|_| anyhow!("workflow source requires an existing commit"))?;
            let mut options = git2::StatusOptions::new();
            options
                .include_untracked(true)
                .include_ignored(false)
                .update_index(false);
            let changed = !repo.statuses(Some(&mut options))?.is_empty();
            Ok(WorkflowSourceSnapshot {
                workspace: WorkflowSourceWorkspace {
                    workspace_id: workspace.id,
                    instance_id: workspace.instance_id,
                    project_id: workspace.project_id,
                    path: workspace.path,
                    project_repo_path: project.repo_path,
                },
                sha: commit.id().to_string(),
                has_uncommitted_changes: changed,
            })
        })
        .await
    }
}
