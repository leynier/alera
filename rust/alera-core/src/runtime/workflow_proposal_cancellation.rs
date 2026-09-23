use super::RuntimeStore;
use anyhow::{bail, Result};
use serde::Serialize;
use sqlx::{Row, Sqlite, Transaction};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowProposalCancellation {
    pub proposal_id: String,
    pub tab_id: Option<String>,
    pub workspace_id: String,
    pub status: String,
    pub error: Option<String>,
    pub sequence: i64,
}

pub(super) async fn require_open_proposal(
    tx: &mut Transaction<'_, Sqlite>,
    id: &str,
) -> Result<()> {
    let cancelled: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workflowProposalCancellations WHERE proposal_id=?)",
    )
    .bind(id)
    .fetch_one(&mut **tx)
    .await?;
    if cancelled {
        bail!("workflow proposal was cancelled");
    }
    Ok(())
}

impl RuntimeStore {
    pub async fn pending_workflow_proposal_cancellations(
        &self,
    ) -> Result<Vec<WorkflowProposalCancellation>> {
        sqlx::query("SELECT * FROM workflowProposalCancellations WHERE status='pending' ORDER BY proposal_id LIMIT 25")
            .fetch_all(self.pool()).await?.into_iter().map(|row| Ok(WorkflowProposalCancellation {
                proposal_id: row.try_get("proposal_id")?, tab_id: row.try_get("tab_id")?,
                workspace_id: row.try_get("workspace_id")?, status: row.try_get("status")?, error: row.try_get("error")?, sequence: row.try_get("sequence")?,
            })).collect()
    }

    pub async fn require_workflow_proposal_cancellation_target(
        &self,
        target: &WorkflowProposalCancellation,
    ) -> Result<()> {
        let valid: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowProposalCancellations p
            JOIN workflowCoordinators c ON c.proposal_id=p.proposal_id
            WHERE p.proposal_id=? AND p.status='pending' AND p.tab_id=? AND p.workspace_id=?
            AND c.tab_id=p.tab_id AND c.workspace_id=p.workspace_id AND p.sequence=?)",
        )
        .bind(&target.proposal_id)
        .bind(&target.tab_id)
        .bind(&target.workspace_id)
        .bind(target.sequence)
        .fetch_one(self.pool())
        .await?;
        if !valid {
            bail!("proposal cancellation target is no longer pending or its identity changed");
        }
        Ok(())
    }

    pub async fn settle_workflow_proposal_cancellation(
        &self,
        target: &WorkflowProposalCancellation,
        error: Option<&str>,
    ) -> Result<()> {
        self.require_workflow_proposal_cancellation_target(target)
            .await?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE workflowProposalCancellations SET status=?,error=? WHERE proposal_id=? AND status='pending' AND tab_id=? AND workspace_id=? AND sequence=?")
            .bind(if error.is_some() { "attention" } else { "settled" })
            .bind(error.map(|value| value.chars().take(1024).collect::<String>()))
            .bind(&target.proposal_id).bind(&target.tab_id).bind(&target.workspace_id).bind(target.sequence).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn cancel_workflow_proposal(&self, id: &str) -> Result<WorkflowProposalCancellation> {
        super::workflow_plan::workflow_text(id, 160)?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let submitted: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowPlanRevisions WHERE request_id=?)",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        if submitted {
            bail!("proposal already produced a plan; cancel its run instead");
        }
        let row = sqlx::query("SELECT json_extract(p.document,'$.request.workspaceId') AS workspace_id,c.tab_id
            FROM workflowProposalDrafts p LEFT JOIN workflowCoordinators c ON c.proposal_id=p.id WHERE p.id=?")
            .bind(id).fetch_one(&mut *tx).await?;
        let tab: Option<String> = row.try_get("tab_id")?;
        sqlx::query("INSERT INTO workflowProposalCancellations(proposal_id,tab_id,workspace_id,status) VALUES(?,?,?,?) ON CONFLICT(proposal_id) DO NOTHING")
            .bind(id).bind(&tab).bind(row.try_get::<String,_>("workspace_id")?)
            .bind(if tab.is_some() { "pending" } else { "settled" }).execute(&mut *tx).await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        self.workflow_proposal_cancellation(id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("proposal cancellation receipt unavailable"))
    }

    /// Explicit Attention retry; replaying the same observed sequence never
    /// restarts a later failed attempt.
    pub async fn retry_workflow_proposal_cancellation(
        &self,
        id: &str,
        expected_sequence: i64,
    ) -> Result<WorkflowProposalCancellation> {
        super::workflow_plan::workflow_text(id, 160)?;
        if expected_sequence < 0 || expected_sequence == i64::MAX {
            bail!("invalid proposal cancellation sequence");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query(
            "SELECT sequence,status FROM workflowProposalCancellations WHERE proposal_id=?",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        let sequence: i64 = row.try_get("sequence")?;
        if sequence < expected_sequence {
            bail!("proposal cancellation sequence is ahead of the runtime");
        }
        if sequence == expected_sequence {
            if row.try_get::<String, _>("status")? != "attention" {
                bail!("only proposal cancellation Attention can be retried");
            }
            sqlx::query("UPDATE workflowProposalCancellations SET status='pending',error=NULL,sequence=sequence+1 WHERE proposal_id=? AND sequence=?")
                .bind(id).bind(expected_sequence).execute(&mut *tx).await?;
            sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision+1 WHERE id=1")
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        self.workflow_proposal_cancellation(id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("proposal cancellation receipt unavailable"))
    }

    pub async fn workflow_proposal_cancellation(
        &self,
        id: &str,
    ) -> Result<Option<WorkflowProposalCancellation>> {
        sqlx::query("SELECT * FROM workflowProposalCancellations WHERE proposal_id=?")
            .bind(id)
            .fetch_optional(self.pool())
            .await?
            .map(|row| {
                Ok(WorkflowProposalCancellation {
                    proposal_id: row.try_get("proposal_id")?,
                    tab_id: row.try_get("tab_id")?,
                    workspace_id: row.try_get("workspace_id")?,
                    status: row.try_get("status")?,
                    error: row.try_get("error")?,
                    sequence: row.try_get("sequence")?,
                })
            })
            .transpose()
    }
}
