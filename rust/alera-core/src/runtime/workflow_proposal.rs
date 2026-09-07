use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::{PrepareWorkflowPlan, WorkflowPlanSnapshot};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowProposalDraft {
    pub id: String,
    pub request: PrepareWorkflowPlan,
    pub selection: WorkflowPlanSnapshot,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowProposalStatus {
    pub id: String,
    pub run_id: Option<String>,
    pub revision: Option<i64>,
    pub coordinator: Option<super::WorkflowCoordinatorReceipt>,
}

impl super::RuntimeStore {
    pub async fn workflow_proposal_status(&self, id: &str) -> Result<WorkflowProposalStatus> {
        super::workflow_plan::workflow_text(id, 160)?;
        let row = sqlx::query(
            "SELECT p.run_id,p.revision FROM workflowProposalDrafts d
            LEFT JOIN workflowPlanRevisions p ON p.request_id = d.id WHERE d.id = ?",
        )
        .bind(id)
        .fetch_one(self.pool())
        .await?;
        Ok(WorkflowProposalStatus {
            id: id.to_owned(),
            run_id: row.try_get("run_id")?,
            revision: row.try_get("revision")?,
            coordinator: self.workflow_coordinator(id).await?,
        })
    }
    pub(super) async fn migrate_workflow_proposals(&self) -> Result<()> {
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS workflowProposalDrafts (
            id TEXT PRIMARY KEY, request_digest TEXT NOT NULL, document TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )",
        )
        .execute(self.pool())
        .await?;
        sqlx::query(
            "CREATE TRIGGER IF NOT EXISTS workflowProposalImmutable
            BEFORE UPDATE ON workflowProposalDrafts
            BEGIN SELECT RAISE(ABORT, 'workflow proposals are immutable'); END",
        )
        .execute(self.pool())
        .await?;
        Ok(())
    }

    pub async fn workflow_proposal(&self, id: &str) -> Result<WorkflowProposalDraft> {
        super::workflow_plan::workflow_text(id, 160)?;
        let document: String =
            sqlx::query_scalar("SELECT document FROM workflowProposalDrafts WHERE id = ?")
                .bind(id)
                .fetch_one(self.pool())
                .await?;
        super::workflow_catalog::workflow_blocking(move || Ok(serde_json::from_str(&document)?))
            .await
    }

    pub async fn submit_workflow_proposal(
        &self,
        id: &str,
        tasks: Vec<super::WorkflowPlanTask>,
    ) -> Result<super::WorkflowPlanRevision> {
        let draft = self.workflow_proposal(id).await?;
        if !draft.request.proposal.tasks.is_empty() {
            bail!("workflow proposal selection is invalid");
        }
        let (request, digest, plan) = super::workflow_catalog::workflow_blocking(move || {
            let mut request = draft.request;
            request.proposal.tasks = tasks;
            let digest = super::workflow_plan::workflow_digest(&request)?;
            let plan = super::workflow_plan_compilation::compile_plan(
                request.proposal.clone(),
                draft.selection.recipe,
                draft.selection.profiles,
                draft.selection.source_workspace,
            )?;
            Ok((request, digest, plan))
        })
        .await?;
        self.persist_workflow_plan(&request, &digest, &plan).await
    }
}
