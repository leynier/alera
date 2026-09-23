use anyhow::{bail, Result};
use sqlx::Row;

use super::workflow_plan::workflow_digest;
use super::RuntimeStore;

impl RuntimeStore {
    pub async fn complete_workflow_execution(
        &self,
        run: &str,
        revision: i64,
        sequence: i64,
    ) -> Result<bool> {
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE workflowRuns SET revision=revision WHERE run_id=?")
            .bind(run)
            .execute(&mut *tx)
            .await?;
        let current: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowExecution e JOIN workflowRuns w ON w.run_id=e.run_id
            WHERE e.run_id=? AND e.revision=? AND e.sequence=? AND e.status='running' AND w.status='approved' AND w.revision=e.revision)")
            .bind(run).bind(revision).bind(sequence).fetch_one(&mut *tx).await?;
        if !current {
            return Ok(false);
        }
        let (plan, _) =
            super::workflow_workspace_eligibility::approved_plan(&mut tx, run, revision).await?;
        let unsettled: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowIntegrations WHERE run_id=? AND cancelled=0 AND state IN ('pending','prepared','attention'))")
            .bind(run).fetch_one(&mut *tx).await?;
        if unsettled {
            bail!("workflow integration must settle before completion");
        }
        let rows=sqlx::query("SELECT t.status,t.result,e.result_digest,e.artifact_digest,e.integration_sha
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id=p.task_id
            LEFT JOIN workflowTaskEvidence e ON e.task_id=p.task_id WHERE p.run_id=? AND p.revision=? LIMIT 129")
            .bind(run).bind(revision).fetch_all(&mut *tx).await?;
        if rows.len() != plan.tasks.len() || rows.len() > 128 {
            bail!("workflow completion is missing tasks");
        }
        for row in rows {
            let result: Option<String> = row.try_get("result")?;
            let digest: Option<String> = row.try_get("result_digest")?;
            if row.try_get::<String, _>("status")? != "completed"
                || result.is_none()
                || digest.as_deref() != Some(workflow_digest(&result)?.as_str())
                || row
                    .try_get::<Option<String>, _>("artifact_digest")?
                    .is_none()
                || row
                    .try_get::<Option<String>, _>("integration_sha")?
                    .is_none()
            {
                bail!("workflow completion requires current integrated task evidence");
            }
        }
        let gates = sqlx::query(
            "SELECT stage_id,status FROM workflowStageGates WHERE run_id=? AND revision=?",
        )
        .bind(run)
        .bind(revision)
        .fetch_all(&mut *tx)
        .await?;
        for stage in plan
            .recipe
            .recipe
            .stages
            .iter()
            .filter(|stage| stage.gate.is_some())
        {
            if !gates.iter().any(|row| {
                row.get::<String, _>("stage_id") == stage.id
                    && row.get::<String, _>("status") == "approved"
            }) {
                bail!("workflow completion requires every human stage gate");
            }
        }
        sqlx::query("UPDATE workflowRuns SET status='completed' WHERE run_id=?")
            .bind(run)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET status='completed',completed_at=datetime('now') WHERE id=?")
            .bind(run).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(true)
    }
}
