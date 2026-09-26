use anyhow::Result;
use sqlx::Row;

use super::workflow_plan::workflow_text;
use super::{
    RuntimeStore, WorkflowIntegrationPage, WorkflowIntegrationQuery, WorkflowIntegrationSummary,
};

impl RuntimeStore {
    pub async fn workflow_integration_summaries(
        &self,
        query: &WorkflowIntegrationQuery,
    ) -> Result<WorkflowIntegrationPage> {
        workflow_text(&query.run_id, 160)?;
        let rows = sqlx::query(
            "SELECT sequence,id,task_id,workspace_id,state,error,
            json_extract(request,'$.expected_sha') AS expected_sha,
            json_extract(receipt,'$.integrated_sha') AS integrated_sha
            FROM workflowIntegrations WHERE run_id = ? AND sequence > ? ORDER BY sequence LIMIT 26",
        )
        .bind(&query.run_id)
        .bind(query.after_row.unwrap_or(0))
        .fetch_all(self.pool())
        .await?;
        let next_after_row = if rows.len() > 25 {
            Some(rows[24].try_get("sequence")?)
        } else {
            None
        };
        let items = rows
            .iter()
            .take(25)
            .map(|row| {
                Ok(WorkflowIntegrationSummary {
                    id: row.try_get("id")?,
                    task_id: row.try_get("task_id")?,
                    workspace_id: row.try_get("workspace_id")?,
                    state: serde_json::from_value(serde_json::Value::String(
                        row.try_get("state")?,
                    ))?,
                    expected_sha: row.try_get("expected_sha")?,
                    integrated_sha: row.try_get("integrated_sha")?,
                    error: row.try_get("error")?,
                })
            })
            .collect::<Result<_>>()?;
        Ok(WorkflowIntegrationPage {
            items,
            next_after_row,
        })
    }
}
