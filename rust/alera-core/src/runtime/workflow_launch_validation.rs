use anyhow::{anyhow, bail, Result};
use sqlx::{Sqlite, Transaction};

use super::workflow_integration_validation::require_resource;
use super::workflow_workspace_eligibility::{approved_plan, eligible_task_state};
use super::workflow_workspace_store::decode;
use super::{FrozenWorkflowTask, LaunchWorkflowTask, WorkflowLaunchInputs};

pub(super) async fn inputs(
    tx: &mut Transaction<'_, Sqlite>,
    request: &LaunchWorkflowTask,
    dispatched: bool,
) -> Result<WorkflowLaunchInputs> {
    let (plan, _) = approved_plan(tx, &request.run_id, request.revision).await?;
    let unsettled: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workflowIntegrations
        WHERE run_id = ? AND state IN ('pending','prepared','attention'))",
    )
    .bind(&request.run_id)
    .fetch_one(&mut **tx)
    .await?;
    if unsettled {
        bail!("reconcile the pending integration before launching a worker");
    }
    eligible_task_state(
        tx,
        &request.run_id,
        request.revision,
        &request.task_id,
        &plan,
        if dispatched {
            &["dispatched"]
        } else {
            &["pending", "ready"]
        },
    )
    .await?;
    let source = decode(
        &sqlx::query("SELECT * FROM workflowWorkspaces WHERE id = ?")
            .bind(&request.workspace_id)
            .fetch_one(&mut **tx)
            .await?,
    )?;
    require_resource(tx, &source).await?;
    if source.identity.run_id != request.run_id
        || source.identity.revision != request.revision
        || source.identity.task_id.as_deref() != Some(&request.task_id)
        || source.identity.owner_workspace_id != plan.source_workspace.workspace_id
        || source.identity.repo_path != plan.source_workspace.project_repo_path
        || source.identity.workspace.project_id != plan.source_workspace.project_id
    {
        bail!("worker attempt does not belong to this approved plan");
    }
    let latest: String = sqlx::query_scalar(
        "SELECT id FROM workflowWorkspaces WHERE task_id = ? ORDER BY attempt DESC LIMIT 1",
    )
    .bind(&request.task_id)
    .fetch_one(&mut **tx)
    .await?;
    if latest != request.workspace_id {
        bail!("worker requires the latest task attempt");
    }
    let raw: String =
        sqlx::query_scalar("SELECT frozen_task FROM workflowPlanTasks WHERE task_id = ?")
            .bind(&request.task_id)
            .fetch_one(&mut **tx)
            .await?;
    let task: FrozenWorkflowTask = serde_json::from_str(&raw)?;
    let profile = plan
        .profiles
        .get(&task.profile_id)
        .cloned()
        .ok_or_else(|| anyhow!("frozen worker profile is missing"))?;
    if !dispatched && source.dispatch_id.is_some() {
        bail!("workflow attempt was already dispatched");
    }
    let active: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workflowWorkspaces x
        WHERE x.run_id = ? AND x.revision = ? AND x.task_id IS NOT NULL AND x.phase <> 'attention'
          AND NOT (x.dispatch_id IS NULL AND EXISTS(SELECT 1 FROM orchestrationTasks t
            WHERE t.id = x.task_id AND t.status = 'cancelled'))
          AND NOT EXISTS(SELECT 1 FROM orchestrationDispatchContexts d WHERE d.id = x.dispatch_id
            AND d.status IN ('completed','failed','startup_failed','superseded','circuit_broken'))",
    )
    .bind(&request.run_id)
    .bind(request.revision)
    .fetch_one(&mut **tx)
    .await?;
    if active > i64::from(plan.max_concurrent) {
        bail!("workflow concurrency limit reached");
    }
    Ok(WorkflowLaunchInputs {
        workspace: source.identity,
        task,
        profile,
        plan_digest: plan.digest,
    })
}

pub(super) fn validate_request(request: &LaunchWorkflowTask) -> Result<()> {
    for value in [
        &request.request_id,
        &request.run_id,
        &request.task_id,
        &request.workspace_id,
    ] {
        super::workflow_plan::workflow_text(value, 160)?;
    }
    if request.revision < 1 {
        bail!("workflow revision must be positive");
    }
    Ok(())
}
