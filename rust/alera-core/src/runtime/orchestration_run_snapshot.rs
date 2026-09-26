use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::orchestration_board_store::{summary_from_row, BOARD_REVISION_SQL};
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
            "SELECT id, substr(COALESCE(display_name, task_title, spec), 1, 256) AS title,
                status, stage_id, workspace_id
             FROM orchestrationTasks WHERE run_id = ? AND (? IS NULL OR id > ?)
             ORDER BY id LIMIT ?",
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
                Ok(OrchestrationTaskSummary {
                    id: row.try_get("id")?,
                    title: row.try_get("title")?,
                    status: row.try_get("status")?,
                    stage_id: row.try_get("stage_id")?,
                    workspace_id: row.try_get("workspace_id")?,
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
