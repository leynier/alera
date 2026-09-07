use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowProposalQuery {
    pub before_created_at: Option<String>,
    pub before_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowProposalSummary {
    pub id: String,
    pub objective: String,
    pub created_at: String,
    pub workspace_id: String,
    pub workspace_name: Option<String>,
    pub run_id: Option<String>,
    pub coordinator_status: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowProposalPage {
    pub entries: Vec<WorkflowProposalSummary>,
    pub has_more: bool,
}

impl super::RuntimeStore {
    pub async fn workflow_proposals(
        &self,
        query: WorkflowProposalQuery,
    ) -> Result<WorkflowProposalPage> {
        if query.before_created_at.is_some() != query.before_id.is_some() {
            bail!("proposal pagination requires both cursor fields");
        }
        for value in [&query.before_created_at, &query.before_id]
            .into_iter()
            .flatten()
        {
            super::workflow_plan::workflow_text(value, 160)?;
        }
        let rows = sqlx::query(
            "SELECT d.id,d.created_at,
            substr(json_extract(d.document,'$.request.proposal.objective'),1,256) AS objective,
            json_extract(d.document,'$.request.workspaceId') AS workspace_id,
            substr(w.name,1,256) AS workspace_name,p.run_id,c.status AS coordinator_status
            FROM workflowProposalDrafts d
            LEFT JOIN workspaces w ON w.id = json_extract(d.document,'$.request.workspaceId')
            LEFT JOIN workflowPlanRevisions p ON p.request_id = d.id
            LEFT JOIN workflowCoordinators c ON c.proposal_id = d.id
            WHERE ? IS NULL OR d.created_at < ? OR (d.created_at = ? AND d.id < ?)
            ORDER BY d.created_at DESC,d.id DESC LIMIT 26",
        )
        .bind(&query.before_created_at)
        .bind(&query.before_created_at)
        .bind(&query.before_created_at)
        .bind(&query.before_id)
        .fetch_all(self.pool())
        .await?;
        let has_more = rows.len() > 25;
        let entries = rows
            .into_iter()
            .take(25)
            .map(|row| {
                Ok(WorkflowProposalSummary {
                    id: row.try_get("id")?,
                    objective: row.try_get("objective")?,
                    created_at: row.try_get("created_at")?,
                    workspace_id: row.try_get("workspace_id")?,
                    workspace_name: row.try_get("workspace_name")?,
                    run_id: row.try_get("run_id")?,
                    coordinator_status: row.try_get("coordinator_status")?,
                })
            })
            .collect::<Result<_>>()?;
        Ok(WorkflowProposalPage { entries, has_more })
    }
}
