use anyhow::Result;
use sqlx::{Sqlite, Transaction};

use super::{format_timestamp, Workspace};

pub(super) async fn write_workspace_record(
    tx: &mut Transaction<'_, Sqlite>,
    workspace: &Workspace,
    allow_update: bool,
) -> Result<()> {
    let result = sqlx::query(
        "INSERT INTO workspaces \
         (id, instanceId, hostId, projectId, name, branch, path, createdAt, updatedAt, \
          kind, status, sourceBranch, reusesExistingBranch, isPinned) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(id) DO UPDATE SET \
         instanceId = excluded.instanceId, hostId = excluded.hostId, projectId = excluded.projectId, \
         name = excluded.name, branch = excluded.branch, path = excluded.path, \
         updatedAt = excluded.updatedAt, kind = excluded.kind, status = excluded.status, \
         sourceBranch = excluded.sourceBranch, reusesExistingBranch = excluded.reusesExistingBranch, \
         isPinned = excluded.isPinned WHERE ?",
    )
    .bind(&workspace.id)
    .bind(&workspace.instance_id)
    .bind(&workspace.host_id)
    .bind(&workspace.project_id)
    .bind(&workspace.name)
    .bind(&workspace.branch)
    .bind(&workspace.path)
    .bind(format_timestamp(workspace.created_at))
    .bind(format_timestamp(workspace.updated_at))
    .bind(workspace.kind.as_str())
    .bind(workspace.status.as_str())
    .bind(&workspace.source_branch)
    .bind(if workspace.reuses_existing_branch { 1_i64 } else { 0_i64 })
    .bind(if workspace.is_pinned { 1_i64 } else { 0_i64 })
    .bind(allow_update)
    .execute(&mut **tx)
    .await?;
    if result.rows_affected() == 0 {
        anyhow::bail!("Workspace ID already exists; retry without replacing its state");
    }
    Ok(())
}
