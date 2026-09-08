use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::{workflow_cleanup::require_cleanup_quiescent, RuntimeStore, WorkflowCleanupPreview};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupClaim {
    pub preview: WorkflowCleanupPreview,
    pub retired_workspace_ids: Vec<String>,
}

impl RuntimeStore {
    /// New runtime owners must stop at this fence. Cleanup's actor-side live
    /// owner check must follow its durable claim to cover in-flight spawns.
    pub async fn require_workspace_outside_cleanup(&self, workspace_id: &str) -> Result<()> {
        let claimed: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowCleanupResources WHERE workspace_id=?)",
        )
        .bind(workspace_id)
        .fetch_one(self.pool())
        .await?;
        if claimed {
            bail!("workspace is reserved for reviewed cleanup");
        }
        Ok(())
    }

    /// Reserves only the immutable selection. The host must still hold resource
    /// locks and recheck live processes and Git state before each removal.
    pub async fn claim_workflow_cleanup(
        &self,
        id: &str,
        digest: &str,
    ) -> Result<WorkflowCleanupClaim> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row =
            sqlx::query("SELECT document,digest,state,expires_at FROM workflowCleanup WHERE id=?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?;
        if row.try_get::<String, _>("digest")? != digest {
            bail!("cleanup confirmation does not match its preview");
        }
        let preview: WorkflowCleanupPreview =
            serde_json::from_str(&row.try_get::<String, _>("document")?)?;
        match row.try_get::<String, _>("state")?.as_str() {
            "preview" => {
                if row.try_get::<i64, _>("expires_at")? <= chrono::Utc::now().timestamp() {
                    bail!("cleanup preview expired; inspect the resources again");
                }
                if preview
                    .items
                    .iter()
                    .any(|item| item.git.dirty || item.git.locked || item.git.operation_in_progress)
                {
                    bail!("cleanup requires clean, unlocked worktrees with no Git operation");
                }
                require_cleanup_quiescent(&mut tx, &preview).await?;
                for item in &preview.items {
                    // The primary key also fences overlapping selections from
                    // different previews, including after a host restart.
                    sqlx::query(
                        "INSERT INTO workflowCleanupResources(workspace_id,cleanup_id) VALUES(?,?)",
                    )
                    .bind(&item.identity.workspace.id)
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
                }
                sqlx::query("UPDATE workflowCleanup SET state='applying' WHERE id=?")
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
            }
            "applying" | "retired" => {}
            _ => bail!("cleanup needs attention before it can continue"),
        }
        let retired_workspace_ids = sqlx::query_scalar(
            "SELECT workspace_id FROM workflowCleanupResources WHERE cleanup_id=? AND retired=1 ORDER BY workspace_id LIMIT 25",
        ).bind(id).fetch_all(&mut *tx).await?;
        tx.commit().await?;
        Ok(WorkflowCleanupClaim {
            preview,
            retired_workspace_ids,
        })
    }

    /// After host-verified Git retirement, atomically retires managed metadata
    /// and records settlement. This does not authorize filesystem removal.
    pub async fn record_workflow_cleanup_retirement(
        &self,
        id: &str,
        digest: &str,
        workspace_id: &str,
    ) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT c.document,r.retired FROM workflowCleanup c JOIN workflowCleanupResources r ON r.cleanup_id=c.id WHERE c.id=? AND c.digest=? AND c.state IN ('applying','retired') AND r.workspace_id=?")
            .bind(id).bind(digest).bind(workspace_id).fetch_optional(&mut *tx).await?
            .ok_or_else(|| anyhow::anyhow!("cleanup retirement does not match a claimed resource"))?;
        if row.try_get::<bool, _>("retired")? {
            return Ok(());
        }
        let preview: WorkflowCleanupPreview =
            serde_json::from_str(&row.try_get::<String, _>("document")?)?;
        let workspace = &preview
            .items
            .iter()
            .find(|item| item.identity.workspace.id == workspace_id)
            .ok_or_else(|| anyhow::anyhow!("cleanup resource is absent from its preview"))?
            .identity
            .workspace;
        let changed: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workspaces WHERE id=? AND (instanceId IS NOT ? OR projectId IS NOT ? OR hostId IS NOT ? OR path IS NOT ? OR branch IS NOT ? OR kind IS NOT ?))")
            .bind(workspace_id).bind(&workspace.instance_id).bind(&workspace.project_id).bind(&workspace.host_id)
            .bind(&workspace.path).bind(&workspace.branch).bind(workspace.kind.as_str()).fetch_one(&mut *tx).await?;
        if changed {
            bail!("cleanup workspace registration changed");
        }
        sqlx::query(
            "UPDATE workflowCleanupResources SET retired=1 WHERE cleanup_id=? AND workspace_id=?",
        )
        .bind(id)
        .bind(workspace_id)
        .execute(&mut *tx)
        .await?;
        super::workspace_retirement::remove_workspace_in_transaction(&mut tx, workspace_id, true)
            .await?;
        sqlx::query("UPDATE workflowCleanup SET state='retired' WHERE id=? AND NOT EXISTS(SELECT 1 FROM workflowCleanupResources WHERE cleanup_id=? AND retired=0)")
            .bind(id).bind(id).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}
