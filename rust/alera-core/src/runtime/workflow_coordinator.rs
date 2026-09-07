use anyhow::{bail, Result};
use serde::Serialize;
use sqlx::Row;

use super::{RuntimeStore, WorkflowProposalDraft};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCoordinatorReceipt {
    pub proposal_id: String,
    pub tab_id: String,
    pub workspace_id: String,
    pub status: String,
    pub error: Option<String>,
}

impl RuntimeStore {
    pub(super) async fn migrate_workflow_coordinators(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS workflowCoordinators (
            proposal_id TEXT PRIMARY KEY REFERENCES workflowProposalDrafts(id),
            tab_id TEXT NOT NULL UNIQUE, workspace_id TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('reserved','started','attention')),
            error TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn workflow_coordinator(
        &self,
        proposal_id: &str,
    ) -> Result<Option<WorkflowCoordinatorReceipt>> {
        let row = sqlx::query("SELECT * FROM workflowCoordinators WHERE proposal_id = ?")
            .bind(proposal_id)
            .fetch_optional(self.pool())
            .await?;
        row.map(|row| {
            Ok(WorkflowCoordinatorReceipt {
                proposal_id: row.try_get("proposal_id")?,
                tab_id: row.try_get("tab_id")?,
                workspace_id: row.try_get("workspace_id")?,
                status: row.try_get("status")?,
                error: row.try_get("error")?,
            })
        })
        .transpose()
    }

    /// Only the winner may spawn. A lost response or a host restart never
    /// grants another launch, even after ordinary profile receipts expire.
    pub async fn reserve_workflow_coordinator(
        &self,
        draft: &WorkflowProposalDraft,
    ) -> Result<(WorkflowCoordinatorReceipt, bool)> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        super::workflow_source_identity::require_source_workspace(
            &mut tx,
            &draft.selection.source_workspace,
        )
        .await?;
        let submitted: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowPlanRevisions WHERE request_id = ?)",
        )
        .bind(&draft.request.request_id)
        .fetch_one(&mut *tx)
        .await?;
        let existing: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowCoordinators WHERE proposal_id = ?)",
        )
        .bind(&draft.id)
        .fetch_one(&mut *tx)
        .await?;
        if submitted && !existing {
            bail!("workflow proposal already has a prepared plan");
        }
        let tab_id = uuid::Uuid::new_v4().to_string();
        let created = sqlx::query("INSERT INTO workflowCoordinators(proposal_id,tab_id,workspace_id,status) VALUES(?,?,?,'reserved') ON CONFLICT(proposal_id) DO NOTHING")
            .bind(&draft.id).bind(&tab_id).bind(&draft.request.workspace_id).execute(&mut *tx).await?.rows_affected() == 1;
        tx.commit().await?;
        Ok((
            self.workflow_coordinator(&draft.id)
                .await?
                .expect("coordinator reservation committed"),
            created,
        ))
    }

    pub async fn settle_workflow_coordinator(
        &self,
        proposal_id: &str,
        tab_id: &str,
        error: Option<&str>,
    ) -> Result<WorkflowCoordinatorReceipt> {
        let error = error.map(|value| value.chars().take(1024).collect::<String>());
        let status = if error.is_some() {
            "attention"
        } else {
            "started"
        };
        sqlx::query("UPDATE workflowCoordinators SET status = ?,error = ? WHERE proposal_id = ? AND tab_id = ? AND status = 'reserved'")
            .bind(status).bind(error).bind(proposal_id).bind(tab_id).execute(self.pool()).await?;
        let receipt = self
            .workflow_coordinator(proposal_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("coordinator reservation not found"))?;
        if receipt.tab_id != tab_id {
            bail!("coordinator terminal identity does not match");
        }
        Ok(receipt)
    }

    pub async fn recover_workflow_coordinators(&self) -> Result<()> {
        sqlx::query("UPDATE workflowCoordinators SET status = 'attention',error = 'Coordinator launch was interrupted. Inspect its terminal before preparing another proposal.' WHERE status = 'reserved'")
            .execute(self.pool()).await?;
        Ok(())
    }
}
