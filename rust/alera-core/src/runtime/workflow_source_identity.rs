use anyhow::{bail, Result};
use sqlx::{Sqlite, Transaction};

use super::WorkflowSourceWorkspace;

pub(super) async fn require_source_workspace(
    tx: &mut Transaction<'_, Sqlite>,
    source: &WorkflowSourceWorkspace,
) -> Result<()> {
    let current: bool = sqlx::query_scalar("SELECT EXISTS(
        SELECT 1 FROM workspaces w JOIN projects p ON p.id = w.projectId
        WHERE w.id = ? AND w.instanceId = ? AND w.projectId = ? AND w.path = ?
          AND p.repoPath = ? AND w.status = 'active' AND w.hostId = 'local' AND p.kind = 'gitRepository')")
        .bind(&source.workspace_id).bind(&source.instance_id).bind(&source.project_id)
        .bind(&source.path).bind(&source.project_repo_path).fetch_one(&mut **tx).await?;
    if !current {
        bail!("workflow source workspace changed or is no longer active");
    }
    Ok(())
}
