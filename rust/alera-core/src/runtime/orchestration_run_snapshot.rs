use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::orchestration_board_store::{summary_from_row, BOARD_REVISION_SQL};
use super::orchestration_task_inspection::bounded_dependencies;
use super::{OrchestrationRunSummary, RuntimeStore};

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OrchestrationRunSnapshotQuery {
    pub run_id: String,
    pub after_task_id: Option<String>,
    pub revision: Option<i64>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrchestrationTaskSummary {
    pub id: String,
    pub title: String,
    pub status: String,
    pub stage_id: Option<String>,
    pub workspace_id: String,
    pub dependencies: Vec<String>,
    pub dependencies_truncated: bool,
    pub workflow_state: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrchestrationRunSnapshot {
    pub revision: i64,
    pub run: OrchestrationRunSummary,
    pub objective: String,
    pub objective_truncated: bool,
    pub tasks: Vec<OrchestrationTaskSummary>,
    pub next_task_id: Option<String>,
}

impl RuntimeStore {
    pub async fn orchestration_run_snapshot(
        &self,
        query: &OrchestrationRunSnapshotQuery,
    ) -> Result<OrchestrationRunSnapshot> {
        let limit = query.limit.unwrap_or(100);
        if !(1..=200).contains(&limit)
            || query.run_id.is_empty()
            || query.run_id.len() > 256
            || query
                .after_task_id
                .as_ref()
                .is_some_and(|id| id.len() > 256)
        {
            bail!("invalid run snapshot query");
        }
        let mut tx = self.pool().begin().await?;
        let revision: i64 = sqlx::query(BOARD_REVISION_SQL)
            .fetch_one(&mut *tx)
            .await?
            .try_get("revision")?;
        if query.after_task_id.is_some() && query.revision != Some(revision) {
            bail!("board cursor is stale; refresh the first page");
        }
        let row = sqlx::query("SELECT * FROM orchestrationBoardRuns WHERE id = ?")
            .bind(&query.run_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or_else(|| anyhow!("run not found"))?;
        let run = summary_from_row(row)?;
        let row = sqlx::query(
            "SELECT substr(spec, 1, 16384) AS objective,
                length(spec) > 16384 AS truncated
             FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(&query.run_id)
        .fetch_one(&mut *tx)
        .await?;
        let objective = row.try_get("objective")?;
        let objective_truncated = row.try_get("truncated")?;
        let rows = sqlx::query(
            "SELECT t.id, substr(COALESCE(t.display_name, t.task_title, t.spec), 1, 256) AS title,
                t.status, t.stage_id, t.workspace_id,
                CASE WHEN length(deps) <= 16384 THEN deps END AS deps
                ,CASE WHEN p.task_id IS NULL THEN NULL
                  WHEN i.state = 'integrated' AND e.task_id IS NOT NULL THEN 'integrated'
                  WHEN i.state = 'integrated' THEN 'attention'
                  WHEN i.state = 'conflict' THEN 'conflict'
                  WHEN i.state = 'attention' OR l.status = 'attention' OR x.phase = 'attention' THEN 'attention'
                  WHEN t.status = 'completed' AND t.result IS NOT NULL THEN 'result_ready'
                  WHEN l.status IN ('reserved','starting','started') THEN l.status
                  WHEN x.phase = 'ready' THEN 'ready'
                  WHEN x.phase IN ('reserved','creating','created','setupRunning') THEN 'reserved'
                 END AS workflow_state
             FROM orchestrationTasks t
             LEFT JOIN workflowPlanTasks p ON p.task_id = t.id
             LEFT JOIN workflowWorkspaces x ON x.sequence = (SELECT MAX(sequence) FROM workflowWorkspaces WHERE task_id = t.id)
             LEFT JOIN workflowLaunches l ON l.workspace_id = x.id
             LEFT JOIN workflowIntegrations i ON i.sequence = (SELECT MAX(sequence) FROM workflowIntegrations WHERE task_id = t.id)
             LEFT JOIN workflowTaskEvidence e ON e.task_id = t.id
             WHERE t.run_id = ? AND (? IS NULL OR t.id > ?)
             ORDER BY t.id LIMIT ?",
        )
        .bind(&query.run_id)
        .bind(&query.after_task_id)
        .bind(&query.after_task_id)
        .bind(i64::from(limit) + 1)
        .fetch_all(&mut *tx)
        .await?;
        let mut tasks = rows
            .into_iter()
            .map(|row| {
                let deps: Option<String> = row.try_get("deps")?;
                let (mut dependencies, mut dependencies_truncated) =
                    bounded_dependencies(deps.as_deref());
                // The ledger needs a preview; the on-demand inspector owns the
                // larger list, keeping a 100-task page cheap for the UI.
                dependencies_truncated |= dependencies.len() > 8;
                dependencies.truncate(8);
                Ok(OrchestrationTaskSummary {
                    id: row.try_get("id")?,
                    title: row.try_get("title")?,
                    status: row.try_get("status")?,
                    stage_id: row.try_get("stage_id")?,
                    workspace_id: row.try_get("workspace_id")?,
                    dependencies,
                    dependencies_truncated,
                    workflow_state: row.try_get("workflow_state")?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let has_more = tasks.len() > limit as usize;
        tasks.truncate(limit as usize);
        let next_task_id = tasks
            .last()
            .filter(|_| has_more)
            .map(|task| task.id.clone());
        tx.commit().await?;
        Ok(OrchestrationRunSnapshot {
            revision,
            run,
            objective,
            objective_truncated,
            tasks,
            next_task_id,
        })
    }
}
