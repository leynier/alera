use anyhow::{anyhow, bail, Result};

use super::{OrchestrationTask, OrchestrationTaskStatus, RuntimeStore};

impl RuntimeStore {
    pub async fn reset_orchestration_tasks(&self) -> Result<()> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("DELETE FROM orchestrationTasks")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationDispatchContexts")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationDecisionGates")
            .execute(&mut *tx)
            .await?;
        sqlx::query("DELETE FROM orchestrationCoordinatorRuns")
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn recover_stalled_orchestration_task(
        &self,
        id: &str,
        status: OrchestrationTaskStatus,
        actor_handle: Option<&str>,
        reason: &str,
        force: bool,
    ) -> Result<OrchestrationTask> {
        if !matches!(
            status,
            OrchestrationTaskStatus::Ready
                | OrchestrationTaskStatus::Failed
                | OrchestrationTaskStatus::Cancelled
        ) {
            bail!("recovery status must be ready, failed, or cancelled");
        }
        let task = self
            .orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("orchestration task not found: {id}"))?;
        if task.status != OrchestrationTaskStatus::Stalled {
            bail!("task {id} is not stalled");
        }
        if matches!(
            status,
            OrchestrationTaskStatus::Ready | OrchestrationTaskStatus::Failed
        ) {
            let workflow_task: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM workflowPlanTasks WHERE task_id = ?)",
            )
            .bind(id)
            .fetch_one(self.pool())
            .await?;
            if workflow_task {
                bail!("stalled workflow recovery requires terminal settlement and a fresh attempt");
            }
        }
        let result = if status == OrchestrationTaskStatus::Cancelled {
            self.cancel_orchestration_task(id, reason).await?
        } else {
            self.update_orchestration_task_status(id, status, Some(reason))
                .await?
        };
        self.insert_orchestration_audit_event(
            actor_handle,
            if force {
                "task.recover.force"
            } else {
                "task.recover"
            },
            id,
            reason,
        )
        .await?;
        Ok(result)
    }

    pub async fn record_orchestration_task_startup_failure(
        &self,
        id: &str,
        error: &str,
    ) -> Result<OrchestrationTask> {
        let result = sqlx::query(
            "UPDATE orchestrationTasks SET startup_failure_count = startup_failure_count + 1, \
             status = CASE WHEN startup_failure_count + 1 >= 3 THEN 'stalled' ELSE 'ready' END, \
             result = ?, stalled_at = CASE WHEN startup_failure_count + 1 >= 3 THEN datetime('now') ELSE NULL END \
             WHERE id = ? AND status = 'ready' \
             AND NOT EXISTS (SELECT 1 FROM orchestrationDispatchContexts \
                 WHERE task_id = ? AND status IN ('pending','dispatched','awaiting_acceptance','stalled'))",
        )
        .bind(error)
        .bind(id)
        .bind(id)
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            bail!("task startup failure rejected: task is missing or terminal");
        }
        self.orchestration_task_by_id(id)
            .await?
            .ok_or_else(|| anyhow!("task not found after startup failure"))
    }
}
