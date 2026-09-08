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
                })
            })
            .transpose()
    }
}
