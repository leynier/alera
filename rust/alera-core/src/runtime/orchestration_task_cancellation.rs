//! Cancelling a task cascades to every task that still waits on it, and
//! settles their dispatches, queued messages and pending gates with them.

use anyhow::{anyhow, bail, Result};
use sqlx::Row;

use super::orchestration_task_store::parse_string_array;
use super::run_event_store::{record_task_run_event, RunEventKind};
use super::{OrchestrationTask, RuntimeStore};

impl RuntimeStore {
    pub async fn cancel_orchestration_task(
        &self,
        id: &str,
        reason: &str,
    ) -> Result<OrchestrationTask> {
        let mut tx = self.pool().begin().await?;
        let status: Option<String> =
            sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(id)
                .fetch_optional(&mut *tx)
                .await?
                .map(|row| row.try_get("status"))
                .transpose()?;
        match status.as_deref() {
            None => bail!("orchestration task not found: {id}"),
            Some("cancelled") => {
                tx.commit().await?;
                return self
                    .orchestration_task_by_id(id)
                    .await?
                    .ok_or_else(|| anyhow!("cancelled orchestration task not found: {id}"));
            }
            Some("completed" | "failed") => {
                bail!("cannot cancel terminal orchestration task {id}")
            }
            _ => {}
        }
        let mut cancelled = vec![id.to_string()];
        let mut cursor = 0;
        while cursor < cancelled.len() {
            let changed = cancelled[cursor].clone();
            cursor += 1;
            let rows = sqlx::query(
                "SELECT id, deps FROM orchestrationTasks \
                 WHERE status IN ('pending','ready','blocked','stalled')",
            )
            .fetch_all(&mut *tx)
            .await?;
            for row in rows {
                let candidate: String = row.try_get("id")?;
                let deps: String = row.try_get("deps")?;
                if parse_string_array(&deps).iter().any(|dep| dep == &changed)
                    && !cancelled.contains(&candidate)
                {
                    cancelled.push(candidate);
                }
            }
        }
        for task_id in &cancelled {
            let task_reason = if task_id == id {
                reason.to_string()
            } else {
                format!("dependency cancelled: {id}")
            };
            let changed = sqlx::query(
                "UPDATE orchestrationTasks SET status = 'cancelled', result = COALESCE(result, ?), \
                 cancelled_at = datetime('now'), completed_at = datetime('now') \
                 WHERE id = ? AND status NOT IN ('completed','failed','cancelled')",
            )
            .bind(&task_reason)
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            if changed.rows_affected() > 0 {
                record_task_run_event(
                    &mut tx,
                    task_id,
                    RunEventKind::TaskCancelled,
                    &task_reason,
                    None,
                )
                .await?;
            }
            sqlx::query(
                "UPDATE orchestrationDispatchContexts SET status = 'cancelled', completed_at = datetime('now') \
                 WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled')",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE orchestrationMessages SET state = 'obsolete', obsolete_at = datetime('now') \
                 WHERE task_id = ? AND state = 'queued'",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE runGates SET status = 'timeout', resolved_at = datetime('now') \
                 WHERE task_id = ? AND status = 'pending'",
            )
            .bind(task_id)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found after cancellation: {id}"))
    }
}
