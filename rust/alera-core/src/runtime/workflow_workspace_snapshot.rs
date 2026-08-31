use std::collections::HashSet;

use anyhow::Result;
use serde::Serialize;

use super::{RuntimeStore, Workspace};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowWorkspaceSnapshot {
    #[serde(flatten)]
    pub workspace: Workspace,
    pub workflow_owned: bool,
}

impl RuntimeStore {
    pub async fn list_workspace_snapshots(
        &self,
        project_id: &str,
    ) -> Result<Vec<WorkflowWorkspaceSnapshot>> {
        let workspaces = self.list_workspaces(project_id).await?;
        // Ownership is retained independently of run status and is never
        // inferred from a branch name or trusted from workspace.upsert.
        let owned: HashSet<String> = sqlx::query_scalar(
            "SELECT w.id FROM workspaces w JOIN workflowWorkspaces f ON f.id = w.id
             WHERE w.projectId = ?",
        )
        .bind(project_id)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .collect();
        Ok(workspaces
            .into_iter()
            .map(|workspace| WorkflowWorkspaceSnapshot {
                workflow_owned: owned.contains(&workspace.id),
                workspace,
            })
            .collect())
    }
}
