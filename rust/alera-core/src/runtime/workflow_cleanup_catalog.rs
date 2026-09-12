use anyhow::Result;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::{RuntimeStore, WorkflowWorkspaceIdentity};

#[cfg(test)]
mod tests;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowCleanupQuery {
    pub run_id: String,
    pub before_row: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupPage<T> {
    pub run_id: String,
    pub revision: i64,
    pub items: Vec<T>,
    pub next_before_row: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupResource {
    pub identity: WorkflowWorkspaceIdentity,
    pub phase: String,
    pub registered: bool,
    pub cleanup_id: Option<String>,
    pub cleanup_state: Option<String>,
    pub retired: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCleanupSummary {
    pub id: String,
    pub state: String,
    pub error: Option<String>,
    pub expires_at: i64,
    pub resource_count: i64,
    pub retired_count: i64,
}

impl RuntimeStore {
    /// A single bounded join supplies resource ownership and cleanup state.
    /// Git inspection remains explicit and occurs only when preparing a preview.
    pub async fn workflow_cleanup_resources(
        &self,
        query: &WorkflowCleanupQuery,
    ) -> Result<WorkflowCleanupPage<WorkflowCleanupResource>> {
        super::workflow_plan::workflow_text(&query.run_id, 160)?;
        let mut tx = self.pool().begin().await?;
        let revision =
            sqlx::query_scalar("SELECT revision FROM orchestrationBoardRevision WHERE id=1")
                .fetch_one(&mut *tx)
                .await?;
        let rows = sqlx::query(
            "SELECT x.sequence,x.identity,x.phase,w.id IS NOT NULL AS registered,
            r.cleanup_id,c.state AS cleanup_state,COALESCE(r.retired,0) AS retired
            FROM workflowWorkspaces x LEFT JOIN workspaces w ON w.id=x.id
            LEFT JOIN workflowCleanupResources r ON r.workspace_id=x.id
            LEFT JOIN workflowCleanup c ON c.id=r.cleanup_id
            WHERE x.run_id=? AND x.sequence<? ORDER BY x.sequence DESC LIMIT 26",
        )
        .bind(&query.run_id)
        .bind(query.before_row.unwrap_or(i64::MAX))
        .fetch_all(&mut *tx)
        .await?;
        let next_before_row = if rows.len() > 25 {
            Some(rows[24].try_get("sequence")?)
        } else {
            None
        };
        let items = rows
            .iter()
            .take(25)
            .map(|row| {
                Ok(WorkflowCleanupResource {
                    identity: serde_json::from_str(&row.try_get::<String, _>("identity")?)?,
                    phase: row.try_get("phase")?,
                    registered: row.try_get("registered")?,
                    cleanup_id: row.try_get("cleanup_id")?,
                    cleanup_state: row.try_get("cleanup_state")?,
                    retired: row.try_get("retired")?,
                })
            })
            .collect::<Result<_>>()?;
        tx.commit().await?;
        Ok(WorkflowCleanupPage {
            run_id: query.run_id.clone(),
            revision,
            items,
            next_before_row,
        })
    }

    pub async fn workflow_cleanups(
        &self,
        query: &WorkflowCleanupQuery,
    ) -> Result<WorkflowCleanupPage<WorkflowCleanupSummary>> {
        super::workflow_plan::workflow_text(&query.run_id, 160)?;
        let mut tx = self.pool().begin().await?;
        let revision =
            sqlx::query_scalar("SELECT revision FROM orchestrationBoardRevision WHERE id=1")
                .fetch_one(&mut *tx)
                .await?;
        let rows = sqlx::query("SELECT c.rowid AS sequence,c.id,c.state,c.error,c.expires_at,
            json_array_length(c.document,'$.items') AS resource_count,
            (SELECT COUNT(*) FROM workflowCleanupResources r WHERE r.cleanup_id=c.id AND r.retired=1) AS retired_count
            FROM workflowCleanup c WHERE c.run_id=? AND c.rowid<? ORDER BY c.rowid DESC LIMIT 26")
            .bind(&query.run_id).bind(query.before_row.unwrap_or(i64::MAX))
            .fetch_all(&mut *tx).await?;
        let next_before_row = if rows.len() > 25 {
            Some(rows[24].try_get("sequence")?)
        } else {
            None
        };
        let items = rows
            .iter()
            .take(25)
            .map(|row| {
                Ok(WorkflowCleanupSummary {
                    id: row.try_get("id")?,
                    state: row.try_get("state")?,
                    error: row.try_get("error")?,
                    expires_at: row.try_get("expires_at")?,
                    resource_count: row.try_get("resource_count")?,
                    retired_count: row.try_get("retired_count")?,
                })
            })
            .collect::<Result<_>>()?;
        tx.commit().await?;
        Ok(WorkflowCleanupPage {
            run_id: query.run_id.clone(),
            revision,
            items,
            next_before_row,
        })
    }
}
