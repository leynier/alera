use anyhow::{anyhow, bail, Result};
use sqlx::Row;

use super::orchestration_message_store::orchestration_id;
use super::{OrchestrationDecisionGate, OrchestrationDispatchContext, RuntimeStore};

impl RuntimeStore {
    /// Opens a decision gate on a stalled task.
    ///
    /// Deliberately not `create_orchestration_gate`: that one requires a live
    /// task and closes the active dispatch. Here the worker may still be alive,
    /// so the dispatch is left exactly as it is and the task stays `stalled`.
    /// Reporting it any other way would misdescribe a worker that could still
    /// be working.
    pub async fn create_orchestration_stall_gate(
        &self,
        task_id: &str,
        question: &str,
        options: &[String],
    ) -> Result<OrchestrationDecisionGate> {
        let mut tx = self.pool().begin().await?;
        let task_status: Option<String> =
            sqlx::query("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(task_id)
                .fetch_optional(&mut *tx)
                .await?
                .map(|row| row.try_get("status"))
                .transpose()?;
        match task_status.as_deref() {
            None => bail!("orchestration task not found: {task_id}"),
            Some("stalled") => {}
            Some(other) => bail!("task {task_id} is not stalled (status: {other})"),
        }
        let existing: Option<String> = sqlx::query(
            "SELECT id FROM orchestrationDecisionGates \
             WHERE task_id = ? AND status = 'pending' LIMIT 1",
        )
        .bind(task_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(|row| row.try_get("id"))
        .transpose()?;
        if let Some(id) = existing {
            tx.commit().await?;
            return self
                .orchestration_gate_by_id(&id)
                .await?
                .ok_or_else(|| anyhow!("pending stall gate not found"));
        }
        let id = orchestration_id("gate");
        sqlx::query(
            "INSERT INTO orchestrationDecisionGates (id, task_id, question, options) \
             VALUES (?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(task_id)
        .bind(question)
        .bind(serde_json::to_string(options)?)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.orchestration_gate_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted stall gate not found"))
    }

    /// Resolved gates on tasks that are still stalled, i.e. decisions the
    /// coordinator has not acted on yet.
    pub async fn resolved_stall_gates(&self) -> Result<Vec<OrchestrationDecisionGate>> {
        let rows = sqlx::query(
            "SELECT g.id FROM orchestrationDecisionGates g \
             JOIN orchestrationTasks t ON t.id = g.task_id \
             WHERE g.status = 'resolved' AND t.status = 'stalled' \
             ORDER BY g.resolved_at ASC",
        )
        .fetch_all(self.pool())
        .await?;
        let mut gates = Vec::new();
        for row in rows {
            let id: String = row.try_get("id")?;
            if let Some(gate) = self.orchestration_gate_by_id(&id).await? {
                gates.push(gate);
            }
        }
        Ok(gates)
    }

    /// Returns a stalled dispatch to `dispatched` and refreshes its lease, so
    /// "keep waiting" restarts the clock instead of re-stalling on the next tick.
    pub async fn resume_stalled_orchestration_dispatch(&self, task_id: &str) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE orchestrationDispatchContexts \
             SET status = 'dispatched', last_activity_at = datetime('now') \
             WHERE task_id = ? AND status = 'stalled'",
        )
        .bind(task_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationTasks SET status = 'dispatched', stalled_at = NULL WHERE id = ? \
             AND status = 'stalled'",
        )
        .bind(task_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    /// The dispatch a stalled task is still holding, if any.
    pub async fn stalled_orchestration_dispatch_for_task(
        &self,
        task_id: &str,
    ) -> Result<Option<OrchestrationDispatchContext>> {
        Ok(self
            .active_orchestration_dispatch_for_task(task_id)
            .await?
            .filter(|dispatch| dispatch.status == super::OrchestrationDispatchStatus::Stalled))
    }
}
