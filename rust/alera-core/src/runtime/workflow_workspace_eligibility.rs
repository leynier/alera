use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_plan::workflow_digest;
use super::{FrozenWorkflowTask, WorkflowPlanSnapshot};

pub(super) async fn approved_plan(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
) -> Result<(WorkflowPlanSnapshot, String)> {
    let row = sqlx::query(
        "SELECT p.snapshot, w.integration_sha FROM workflowRuns w
        JOIN workflowPlanRevisions p ON p.run_id = w.run_id AND p.revision = w.revision
        JOIN orchestrationCoordinatorRuns c ON c.id = w.run_id
        WHERE w.run_id = ? AND w.revision = ? AND w.status = 'approved'
          AND c.status IN ('idle','running')",
    )
    .bind(run)
    .bind(revision)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow!("workflow requires its current approved plan and an active run"))?;
    let plan: WorkflowPlanSnapshot = serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?;
    if plan.digest != plan.content_digest()? {
        bail!("workflow plan snapshot is invalid");
    }
    super::workflow_source_identity::require_source_workspace(tx, &plan.source_workspace).await?;
    Ok((plan, row.try_get("integration_sha")?))
}

pub(super) async fn eligible_task(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
    task_id: &str,
    plan: &WorkflowPlanSnapshot,
) -> Result<()> {
    let row = sqlx::query(
        "SELECT p.frozen_task, t.status FROM workflowPlanTasks p
        JOIN orchestrationTasks t ON t.id = p.task_id
        WHERE p.run_id = ? AND p.revision = ? AND p.task_id = ?
          AND t.run_id = p.run_id AND t.workspace_id = ?",
    )
    .bind(run)
    .bind(revision)
    .bind(task_id)
    .bind(&plan.source_workspace.workspace_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow!("task does not belong to this workflow plan"))?;
    if !matches!(
        row.try_get::<String, _>("status")?.as_str(),
        "pending" | "ready"
    ) {
        bail!("workflow task is not awaiting execution");
    }
    let frozen: FrozenWorkflowTask =
        serde_json::from_str(&row.try_get::<String, _>("frozen_task")?)?;
    for dependency in &frozen.task.depends_on {
        let evidence = sqlx::query(
            "SELECT t.status, t.result, e.result_digest FROM workflowPlanTasks p
            JOIN orchestrationTasks t ON t.id = p.task_id
            JOIN workflowTaskEvidence e ON e.task_id = p.task_id
            WHERE p.run_id = ? AND p.revision = ? AND p.logical_id = ?",
        )
        .bind(run)
        .bind(revision)
        .bind(dependency)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| anyhow!("workflow prerequisite has not been integrated"))?;
        let result: Option<String> = evidence.try_get("result")?;
        if evidence.try_get::<String, _>("status")? != "completed"
            || result.is_none()
            || evidence.try_get::<String, _>("result_digest")? != workflow_digest(&result)?
        {
            bail!("workflow prerequisite integration evidence is stale");
        }
    }
    let stage = plan
        .recipe
        .recipe
        .stages
        .iter()
        .find(|s| s.id == frozen.task.stage_id)
        .ok_or_else(|| anyhow!("workflow task stage is missing"))?;
    let mut remaining = stage.depends_on.clone();
    let mut visited = BTreeSet::new();
    while let Some(id) = remaining.pop() {
        if !visited.insert(id.clone()) {
            continue;
        }
        let prior = plan
            .recipe
            .recipe
            .stages
            .iter()
            .find(|s| s.id == id)
            .ok_or_else(|| anyhow!("workflow prerequisite stage is missing"))?;
        remaining.extend(prior.depends_on.clone());
        if prior.gate.is_some() {
            let approved: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM workflowStageGates
                WHERE run_id = ? AND revision = ? AND stage_id = ? AND status = 'approved')",
            )
            .bind(run)
            .bind(revision)
            .bind(id)
            .fetch_one(&mut **tx)
            .await?;
            if !approved {
                bail!("workflow prerequisite human gate is not approved");
            }
        }
    }
    Ok(())
}
