use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::run_plan::workflow_digest;
use super::{FrozenWorkflowTask, WorkflowPlanSnapshot};

pub(super) async fn approved_plan(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
) -> Result<(WorkflowPlanSnapshot, String)> {
    let row = sqlx::query(
        "SELECT p.snapshot, r.integration_sha FROM orchestrationCoordinatorRuns r
        JOIN runPlanRevisions p ON p.run_id = r.id AND p.revision = r.plan_revision
        WHERE r.id = ? AND r.plan_revision = ? AND r.isolation = 'isolated'
          AND r.status IN ('running','paused')",
    )
    .bind(run)
    .bind(revision)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow!("the run needs its current accepted plan and must be active"))?;
    let plan: WorkflowPlanSnapshot = serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?;
    if plan.digest != plan.content_digest()? {
        bail!("workflow plan snapshot is invalid");
    }
    super::run_source_identity::require_source_workspace(tx, &plan.source_workspace).await?;
    Ok((
        plan,
        row.try_get::<Option<String>, _>("integration_sha")?
            .unwrap_or_default(),
    ))
}

pub(super) async fn eligible_task(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
    task_id: &str,
    plan: &WorkflowPlanSnapshot,
) -> Result<()> {
    eligible_task_state(tx, run, revision, task_id, plan, &["pending", "ready"]).await
}

pub(super) async fn eligible_task_state(
    tx: &mut Transaction<'_, Sqlite>,
    run: &str,
    revision: i64,
    task_id: &str,
    plan: &WorkflowPlanSnapshot,
    allowed_states: &[&str],
) -> Result<()> {
    let row = sqlx::query(
        "SELECT t.logical_id, t.status FROM orchestrationTasks t
        WHERE t.run_id = ? AND t.plan_revision = ? AND t.id = ? AND t.workspace_id = ?",
    )
    .bind(run)
    .bind(revision)
    .bind(task_id)
    .bind(&plan.source_workspace.workspace_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow!("task does not belong to this workflow plan"))?;
    if !allowed_states.contains(&row.try_get::<String, _>("status")?.as_str()) {
        bail!("workflow task is not awaiting execution");
    }
    let frozen = planned_task(plan, &row.try_get::<String, _>("logical_id")?)?;
    for dependency in &frozen.task.depends_on {
        let evidence = sqlx::query(
            "SELECT t.status, t.result, e.result_digest FROM orchestrationTasks t
            JOIN runTaskEvidence e ON e.task_id = t.id
            WHERE t.run_id = ? AND t.plan_revision = ? AND t.logical_id = ?",
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
        if prior.gate.is_some()
            && !super::run_gate_evidence::stage_gate_approved(tx, run, revision, &id).await?
        {
            bail!("a prerequisite stage gate is not approved");
        }
    }
    Ok(())
}

/// The frozen definition of a planned task, read from its plan revision.
pub(super) fn planned_task<'a>(
    plan: &'a WorkflowPlanSnapshot,
    logical_id: &str,
) -> Result<&'a FrozenWorkflowTask> {
    plan.tasks
        .iter()
        .find(|task| task.task.id == logical_id)
        .ok_or_else(|| anyhow!("task is absent from its frozen plan"))
}

/// The frozen definition of a planned task, by task id.
pub(super) async fn frozen_task(
    tx: &mut Transaction<'_, Sqlite>,
    task_id: &str,
) -> Result<FrozenWorkflowTask> {
    let row = sqlx::query(
        "SELECT t.logical_id, p.snapshot FROM orchestrationTasks t
        JOIN runPlanRevisions p ON p.run_id = t.run_id AND p.revision = t.plan_revision
        WHERE t.id = ?",
    )
    .bind(task_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| anyhow!("task does not belong to a run plan"))?;
    let plan: WorkflowPlanSnapshot = serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?;
    Ok(planned_task(&plan, &row.try_get::<String, _>("logical_id")?)?.clone())
}
