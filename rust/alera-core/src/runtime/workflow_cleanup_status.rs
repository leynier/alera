use super::{RuntimeStore, WorkflowCleanupPreview};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowCleanupState {
    Preview,
    Applying,
    Retired,
    Attention,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupStatus {
    pub preview: WorkflowCleanupPreview,
    pub state: WorkflowCleanupState,
    pub error: Option<String>,
    pub retired_workspace_ids: Vec<String>,
}

impl RuntimeStore {
    pub async fn pending_workflow_cleanup_page(
        &self,
        after: &str,
    ) -> Result<Vec<(String, String)>> {
        Ok(sqlx::query_as("SELECT id,digest FROM workflowCleanup WHERE state='applying' AND id>? ORDER BY id LIMIT 25")
            .bind(after).fetch_all(self.pool()).await?)
    }

    pub async fn workflow_cleanup_status(&self, id: &str) -> Result<WorkflowCleanupStatus> {
        let mut tx = self.pool().begin().await?;
        let row = sqlx::query("SELECT document,state,error FROM workflowCleanup WHERE id=?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        let state = match row.try_get::<String, _>("state")?.as_str() {
            "preview" => WorkflowCleanupState::Preview,
            "applying" => WorkflowCleanupState::Applying,
            "retired" => WorkflowCleanupState::Retired,
            "attention" => WorkflowCleanupState::Attention,
            _ => bail!("invalid cleanup state"),
        };
        let retired_workspace_ids = sqlx::query_scalar("SELECT workspace_id FROM workflowCleanupResources WHERE cleanup_id=? AND retired=1 ORDER BY workspace_id LIMIT 25")
            .bind(id).fetch_all(&mut *tx).await?;
        let status = WorkflowCleanupStatus {
            preview: serde_json::from_str(&row.try_get::<String, _>("document")?)?,
            state,
            error: row.try_get("error")?,
            retired_workspace_ids,
        };
        tx.commit().await?;
        Ok(status)
    }

    /// Call while holding the operation's resource locks. A stale failure may
    /// not overwrite completion, and repeated failures preserve the first cause.
    pub async fn mark_workflow_cleanup_attention(
        &self,
        id: &str,
        digest: &str,
        error: &str,
    ) -> Result<()> {
        let mut end = error.len().min(4096);
        while !error.is_char_boundary(end) {
            end -= 1;
        }
        let mut tx = self.pool().begin().await?;
        let changed = sqlx::query("UPDATE workflowCleanup SET state='attention',error=? WHERE id=? AND digest=? AND state='applying'")
            .bind(&error[..end]).bind(id).bind(digest).execute(&mut *tx).await?.rows_affected();
        if changed != 0 {
            sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// Explicit retry only, with the original selection and the resource locks
    /// held. Recovery must not automatically retry Attention operations.
    pub async fn resume_workflow_cleanup(&self, id: &str, digest: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query("SELECT document,state,digest FROM workflowCleanup WHERE id=?")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        if row.try_get::<String, _>("digest")? != digest {
            bail!("cleanup confirmation does not match its preview");
        }
        if row.try_get::<String, _>("state")? == "attention" {
            let preview = serde_json::from_str(&row.try_get::<String, _>("document")?)?;
            super::workflow_cleanup::require_cleanup_quiescent(&mut tx, &preview).await?;
            sqlx::query("UPDATE workflowCleanup SET state='applying',error=NULL WHERE id=?")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(())
    }
}
