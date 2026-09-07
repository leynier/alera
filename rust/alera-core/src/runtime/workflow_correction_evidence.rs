use anyhow::{bail, Result};
use serde_json::json;
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_plan::workflow_digest;

pub(super) async fn correction_evidence(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    revision: i64,
) -> Result<String> {
    super::workflow_plan_store::ensure_no_active_work(tx, run_id).await?;
    let running: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workflowExecution WHERE run_id=? AND status='running')",
    )
    .bind(run_id)
    .fetch_one(&mut **tx)
    .await?;
    if running {
        bail!("pause workflow execution before reviewing a correction");
    }
    let rows = sqlx::query(
        "SELECT p.task_id,t.status,t.result,e.result_digest,e.artifact_digest,e.integration_sha,
        i.id AS integration_id,i.state AS integration_state,i.conflict_paths,i.conflicts_truncated,i.error
        FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id=p.task_id
        LEFT JOIN workflowTaskEvidence e ON e.task_id=p.task_id
        LEFT JOIN workflowIntegrations i ON i.sequence=(SELECT MAX(sequence) FROM workflowIntegrations WHERE task_id=p.task_id)
        WHERE p.run_id=? AND p.revision=? ORDER BY p.logical_id LIMIT 129",
    )
    .bind(run_id)
    .bind(revision)
    .fetch_all(&mut **tx)
    .await?;
    if rows.len() > super::WORKFLOW_PLAN_MAX_TASKS {
        bail!("workflow correction evidence exceeds the task limit");
    }
    let evidence = rows
        .into_iter()
        .map(|row| {
            Ok(json!({
                "taskId": row.try_get::<String,_>("task_id")?,
                "status": row.try_get::<String,_>("status")?,
                "actualResultDigest": workflow_digest(&row.try_get::<Option<String>,_>("result")?)?,
                "resultDigest": row.try_get::<Option<String>,_>("result_digest")?,
                "artifactDigest": row.try_get::<Option<String>,_>("artifact_digest")?,
                "integrationSha": row.try_get::<Option<String>,_>("integration_sha")?,
                "integrationId": row.try_get::<Option<String>,_>("integration_id")?,
                "integrationState": row.try_get::<Option<String>,_>("integration_state")?,
                "conflictPaths": row.try_get::<Option<String>,_>("conflict_paths")?,
                "conflictsTruncated": row.try_get::<Option<bool>,_>("conflicts_truncated")?,
                "error": row.try_get::<Option<String>,_>("error")?,
            }))
        })
        .collect::<Result<Vec<_>>>()?;
    workflow_digest(&evidence)
}
