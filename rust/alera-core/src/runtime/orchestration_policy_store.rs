use anyhow::Result;

use super::{OrchestrationCoordinatorRun, OrchestrationPolicyStatus, RuntimeStore};

impl RuntimeStore {
    /// Stores a proposed execution policy and parks the run at `draft` until the
    /// user resolves it. The policy JSON is validated by the caller, which owns
    /// the agent profile catalog the stages reference.
    pub async fn propose_orchestration_execution_policy(
        &self,
        run_id: &str,
        policy_json: &str,
    ) -> Result<OrchestrationCoordinatorRun> {
        let result = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET execution_policy = ?, execution_policy_status = 'draft', \
                 execution_policy_updated_at = datetime('now') \
             WHERE id = ? AND status NOT IN ('completed','failed','stopped')",
        )
        .bind(policy_json)
        .bind(run_id)
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            anyhow::bail!("run {run_id} is missing or already finished");
        }
        self.require_orchestration_run(run_id).await
    }

    /// Resolves a proposed policy. Only a `draft` can be resolved, so an
    /// approval cannot silently overwrite a decision already made.
    pub async fn resolve_orchestration_execution_policy(
        &self,
        run_id: &str,
        approved: bool,
    ) -> Result<OrchestrationCoordinatorRun> {
        let next = if approved {
            OrchestrationPolicyStatus::Approved
        } else {
            OrchestrationPolicyStatus::Rejected
        };
        let result = sqlx::query(
            "UPDATE orchestrationCoordinatorRuns \
             SET execution_policy_status = ?, execution_policy_updated_at = datetime('now') \
             WHERE id = ? AND execution_policy_status = 'draft'",
        )
        .bind(next.as_str())
        .bind(run_id)
        .execute(self.pool())
        .await?;
        if result.rows_affected() == 0 {
            anyhow::bail!("run {run_id} has no execution policy awaiting a decision");
        }
        self.require_orchestration_run(run_id).await
    }

    /// Binds a task to a stage of its run's policy, so dispatch can resolve the
    /// preferred profile and the fallback list.
    pub async fn set_orchestration_task_stage(
        &self,
        task_id: &str,
        stage_id: Option<&str>,
    ) -> Result<()> {
        let result = sqlx::query("UPDATE orchestrationTasks SET stage_id = ? WHERE id = ?")
            .bind(stage_id)
            .bind(task_id)
            .execute(self.pool())
            .await?;
        if result.rows_affected() == 0 {
            anyhow::bail!("orchestration task not found: {task_id}");
        }
        Ok(())
    }

    async fn require_orchestration_run(&self, run_id: &str) -> Result<OrchestrationCoordinatorRun> {
        self.orchestration_coordinator_run_by_id(run_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("coordinator run not found: {run_id}"))
    }
}
