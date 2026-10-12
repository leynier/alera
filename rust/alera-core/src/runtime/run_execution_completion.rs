use anyhow::{bail, Result};
use sqlx::Row;

use super::run_plan::workflow_digest;
use super::RuntimeStore;

impl RuntimeStore {
    pub async fn complete_workflow_execution(
        &self,
        run: &str,
        revision: i64,
        sequence: i64,
    ) -> Result<bool> {
        let mut tx = self.pool().begin().await?;
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET control_sequence=control_sequence WHERE id=?",
        )
        .bind(run)
        .execute(&mut *tx)
        .await?;
        let current: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM orchestrationCoordinatorRuns
            WHERE id=? AND plan_revision=? AND control_sequence=? AND status='running' AND isolation='isolated')")
            .bind(run).bind(revision).bind(sequence).fetch_one(&mut *tx).await?;
        if !current {
            return Ok(false);
        }
        let (plan, _) =
            super::run_workspace_eligibility::approved_plan(&mut tx, run, revision).await?;
        let unsettled: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM runIntegrations WHERE run_id=? AND cancelled=0 AND state IN ('pending','prepared','attention'))")
            .bind(run).fetch_one(&mut *tx).await?;
        if unsettled {
            bail!("workflow integration must settle before completion");
        }
        let rows=sqlx::query("SELECT t.status,t.result,e.result_digest,e.artifact_digest,e.integration_sha
            FROM orchestrationTasks t
            LEFT JOIN runTaskEvidence e ON e.task_id=t.id WHERE t.run_id=? AND t.plan_revision=? LIMIT 129")
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
        let gates = super::run_execution_step::approved_stage_gates(&mut tx, run, revision).await?;
        for stage in plan
            .recipe
            .recipe
            .stages
            .iter()
            .filter(|stage| stage.gate.is_some())
        {
            if !gates.contains_key(&stage.id) {
                bail!("run completion requires every stage gate");
            }
        }
        sqlx::query("UPDATE orchestrationCoordinatorRuns SET status='completed',completed_at=datetime('now'),
            paused_by=NULL WHERE id=?")
            .bind(run).execute(&mut *tx).await?;
        let integration = sqlx::query(
            "SELECT COALESCE(r.integration_workspace_id,
                    (SELECT id FROM runWorkspaces WHERE run_id = r.id AND task_id IS NULL))
                    AS workspace_id,
                r.integration_sha, json_extract(r.source_snapshot, '$.sourceSha') AS source_sha
             FROM orchestrationCoordinatorRuns r WHERE r.id = ?",
        )
        .bind(run)
        .fetch_one(&mut *tx)
        .await?;
        let mut event = super::run_event_store::NewRunEvent::new(
            run,
            super::run_event_store::RunEventKind::Completed,
        );
        event.actor_kind = Some(super::RunActorKind::Runtime);
        event.payload = Some(serde_json::json!({
            "workspaceId": integration.try_get::<Option<String>, _>("workspace_id")?,
            "sha": integration.try_get::<Option<String>, _>("integration_sha")?,
            "baseSha": integration.try_get::<Option<String>, _>("source_sha")?,
        }));
        super::run_event_store::record_run_event(&mut tx, &event).await?;
        tx.commit().await?;
        Ok(true)
    }
}
