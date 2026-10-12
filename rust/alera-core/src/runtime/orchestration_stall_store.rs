//! Stall handling in the store: stall gates and the dispatch a stalled task
//! still holds.

use anyhow::{anyhow, bail, Result};

use super::orchestration_gate_store::{
    gate_from_row, insert_task_gate, prefixed_gate_columns, STALL_GATE_OPTIONS, STALL_GATE_RESUMED,
};
use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::{OrchestrationDecisionGate, OrchestrationDispatchContext, RunGateKind, RuntimeStore};

impl RuntimeStore {
    /// Opens a stall gate on a stalled task.
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
    ) -> Result<OrchestrationDecisionGate> {
        let mut tx = self.pool().begin().await?;
        let task_status: Option<String> =
            sqlx::query_scalar("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(task_id)
                .fetch_optional(&mut *tx)
                .await?;
        match task_status.as_deref() {
            None => bail!("orchestration task not found: {task_id}"),
            Some("stalled") => {}
            Some(other) => bail!("task {task_id} is not stalled (status: {other})"),
        }
        let existing: Option<String> = sqlx::query_scalar(
            "SELECT id FROM runGates \
             WHERE task_id = ? AND kind IN ('decision','stall') AND status = 'pending' LIMIT 1",
        )
        .bind(task_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(id) = existing {
            tx.commit().await?;
            return self
                .orchestration_gate_by_id(&id)
                .await?
                .ok_or_else(|| anyhow!("pending stall gate not found"));
        }
        let options: Vec<String> = STALL_GATE_OPTIONS
            .iter()
            .map(|value| value.to_string())
            .collect();
        let id = insert_task_gate(&mut tx, RunGateKind::Stall, task_id, question, &options).await?;
        tx.commit().await?;
        self.orchestration_gate_by_id(&id)
            .await?
            .ok_or_else(|| anyhow!("inserted stall gate not found"))
    }

    /// Resolves a task's pending stall gate as [`STALL_GATE_RESUMED`] because
    /// its worker showed activity again. Returns the gate it resolved.
    pub async fn resolve_stall_gate_as_resumed(
        &self,
        task_id: &str,
    ) -> Result<Option<OrchestrationDecisionGate>> {
        let id: Option<String> = sqlx::query_scalar(
            "SELECT id FROM runGates WHERE task_id = ? AND kind = 'stall' AND status = 'pending' \
             ORDER BY rowid DESC LIMIT 1",
        )
        .bind(task_id)
        .fetch_optional(self.pool())
        .await?;
        let Some(id) = id else {
            return Ok(None);
        };
        let mut tx = self.pool().begin().await?;
        let run_id: Option<Option<String>> = sqlx::query_scalar(
            "UPDATE runGates SET status = 'resolved', resolution = ?, resolved_at = datetime('now') \
             WHERE id = ? AND status = 'pending' RETURNING run_id",
        )
        .bind(STALL_GATE_RESUMED)
        .bind(&id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(Some(run_id)) = run_id.as_ref() {
            let mut event = NewRunEvent::new(run_id, RunEventKind::GateResolved);
            event.task_id = Some(task_id);
            event.gate_id = Some(&id);
            event.summary = STALL_GATE_RESUMED;
            event.payload = Some(serde_json::json!({ "kind": "stall" }));
            record_run_event(&mut tx, &event).await?;
        }
        tx.commit().await?;
        if run_id.is_none() {
            return Ok(None);
        }
        self.orchestration_gate_by_id(&id).await
    }

    /// Stall gates a person resolved on tasks that are still stalled, i.e.
    /// decisions the runtime has not acted on yet. `resumed` gates are left
    /// out: their worker already recovered on its own.
    pub async fn resolved_stall_gates(&self) -> Result<Vec<OrchestrationDecisionGate>> {
        let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {} FROM runGates g \
             JOIN orchestrationTasks t ON t.id = g.task_id \
             WHERE g.kind = 'stall' AND g.status = 'resolved' AND t.status = 'stalled' \
               AND g.resolution <> ? \
             ORDER BY g.resolved_at ASC, g.rowid ASC",
            prefixed_gate_columns("g")
        )))
        .bind(STALL_GATE_RESUMED)
        .fetch_all(self.pool())
        .await?;
        rows.into_iter().map(gate_from_row).collect()
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
