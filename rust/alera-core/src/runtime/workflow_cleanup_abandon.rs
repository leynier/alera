use anyhow::{bail, Result};
use sqlx::Row;

use super::{RuntimeStore, WorkflowCleanupPreview};

#[cfg(test)]
mod tests;

impl RuntimeStore {
    /// Authorizes inspection only, never Git removal. Attention retains its
    /// claim until an explicit retry or a host-verified abandonment settles.
    pub async fn require_retained_cleanup_resource(
        &self,
        id: &str,
        digest: &str,
        workspace: &str,
    ) -> Result<()> {
        let claimed: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowCleanup c
            JOIN workflowCleanupResources r ON r.cleanup_id=c.id WHERE c.id=? AND c.digest=?
            AND c.abandoned=0 AND c.state IN ('applying','attention') AND r.workspace_id=? AND r.retired=0)")
            .bind(id).bind(digest).bind(workspace).fetch_one(self.pool()).await?;
        if !claimed {
            bail!("cleanup resource has no retained matching claim");
        }
        Ok(())
    }

    /// Trusted host boundary: caller holds all cleanup locks and has verified
    /// every unretired checkout is intact, idle and has no Git removal receipt.
    /// This releases claims only; it never deletes filesystem or retired rows.
    pub async fn abandon_workflow_cleanup(&self, id: &str, digest: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row =
            sqlx::query("SELECT document,digest,state,abandoned FROM workflowCleanup WHERE id=?")
                .bind(id)
                .fetch_one(&mut *tx)
                .await?;
        if row.try_get::<String, _>("digest")? != digest {
            bail!("cleanup confirmation does not match its preview");
        }
        if row.try_get::<bool, _>("abandoned")? {
            return Ok(());
        }
        if row.try_get::<String, _>("state")? != "attention" {
            bail!("only a cleanup needing attention can be abandoned");
        }
        let preview: WorkflowCleanupPreview =
            serde_json::from_str(&row.try_get::<String, _>("document")?)?;
        super::workflow_cleanup::require_cleanup_quiescent(&mut tx, &preview).await?;
        let claims: Vec<(String, bool)> = sqlx::query_as(
            "SELECT workspace_id,retired FROM workflowCleanupResources WHERE cleanup_id=? LIMIT 26",
        )
        .bind(id)
        .fetch_all(&mut *tx)
        .await?;
        if claims.len() != preview.items.len() {
            bail!("cleanup claims changed");
        }
        for (workspace_id, retired) in claims {
            let item = preview
                .items
                .iter()
                .find(|item| item.identity.workspace.id == workspace_id)
                .ok_or_else(|| anyhow::anyhow!("cleanup claim has a foreign resource"))?;
            if retired {
                continue;
            }
            let workspace = &item.identity.workspace;
            let unchanged: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workspaces WHERE id=?
                AND instanceId IS ? AND projectId IS ? AND hostId IS ? AND path IS ? AND branch IS ? AND kind IS ?)")
                .bind(&workspace.id).bind(&workspace.instance_id).bind(&workspace.project_id)
                .bind(&workspace.host_id).bind(&workspace.path).bind(&workspace.branch).bind(workspace.kind.as_str())
                .fetch_one(&mut *tx).await?;
            if !unchanged {
                bail!("cleanup workspace registration changed");
            }
        }
        sqlx::query("DELETE FROM workflowCleanupResources WHERE cleanup_id=? AND retired=0")
            .bind(id)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE workflowCleanup SET abandoned=1 WHERE id=? AND digest=? AND state='attention' AND abandoned=0")
            .bind(id).bind(digest).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }
}
