use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_plan::workflow_digest;
use super::workflow_workspace_eligibility::approved_plan;
use super::workflow_workspace_store::decode;
use super::{
    FrozenWorkflowTask, IntegrateWorkflowResult, WorkflowWorkspacePhase, WorkflowWorkspaceRecord,
};
use crate::git::{WorkflowGitResource, WorkflowIntegrationRequest};

pub(super) async fn capture(
    tx: &mut Transaction<'_, Sqlite>,
    input: &IntegrateWorkflowResult,
    source_sha: &str,
    id: String,
) -> Result<WorkflowIntegrationRequest> {
    let (plan, expected_sha) = approved_plan(tx, &input.run_id, input.revision).await?;
    let source = decode(
        &sqlx::query("SELECT * FROM workflowWorkspaces WHERE id = ?")
            .bind(&input.workspace_id)
            .fetch_one(&mut **tx)
            .await?,
    )?;
    let integration = decode(
        &sqlx::query("SELECT * FROM workflowWorkspaces WHERE run_id = ? AND task_id IS NULL")
            .bind(&input.run_id)
            .fetch_one(&mut **tx)
            .await?,
    )?;
    for record in [&source, &integration] {
        require_resource(tx, record).await?;
        if record.identity.run_id != input.run_id
            || record.identity.owner_workspace_id != plan.source_workspace.workspace_id
            || record.identity.repo_path != plan.source_workspace.project_repo_path
            || record.identity.workspace.project_id != plan.source_workspace.project_id
        {
            bail!("integration resource belongs to another workflow");
        }
    }
    if source.identity.task_id.as_deref() != Some(&input.task_id)
        || source.identity.revision != input.revision
    {
        bail!("integration attempt does not belong to this task revision");
    }
    let dispatch_id = source
        .dispatch_id
        .as_ref()
        .ok_or_else(|| anyhow!("workflow attempt has not been dispatched"))?;
    let row = sqlx::query(
        "SELECT t.result, p.frozen_task FROM workflowPlanTasks p
        JOIN orchestrationTasks t ON t.id = p.task_id
        JOIN orchestrationDispatchContexts d ON d.task_id = t.id
        WHERE p.run_id = ? AND p.revision = ? AND p.task_id = ?
          AND t.run_id = p.run_id AND t.workspace_id = ? AND t.status = 'completed'
          AND d.id = ? AND d.run_id = p.run_id AND d.workspace_id = ? AND d.status = 'completed'",
    )
    .bind(&input.run_id)
    .bind(input.revision)
    .bind(&input.task_id)
    .bind(&plan.source_workspace.workspace_id)
    .bind(dispatch_id)
    .bind(&input.workspace_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| {
        anyhow!("integration requires a completed result from this isolated dispatch")
    })?;
    let result: Option<String> = row.try_get("result")?;
    let raw = result
        .as_ref()
        .ok_or_else(|| anyhow!("workflow result is missing"))?;
    let frozen: FrozenWorkflowTask =
        serde_json::from_str(&row.try_get::<String, _>("frozen_task")?)?;
    frozen.contract.validate_success_result(raw)?;
    let result_json: serde_json::Value = serde_json::from_str(raw)?;
    let artifacts = result_json["artifacts"]
        .as_array()
        .ok_or_else(|| anyhow!("result artifacts are missing"))?
        .iter()
        .map(|p| {
            p.as_str()
                .map(str::to_owned)
                .ok_or_else(|| anyhow!("invalid result artifact"))
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(WorkflowIntegrationRequest {
        id,
        repo_path: source.identity.repo_path.clone(),
        run_id: input.run_id.clone(),
        revision: input.revision,
        task_id: input.task_id.clone(),
        dispatch_id: dispatch_id.clone(),
        integration: resource(&integration),
        source: resource(&source),
        expected_sha,
        source_sha: source_sha.into(),
        result_digest: workflow_digest(&result)?,
        artifacts,
    })
}

pub(super) async fn require_current(
    tx: &mut Transaction<'_, Sqlite>,
    request: &WorkflowIntegrationRequest,
) -> Result<()> {
    let current = capture(
        tx,
        &IntegrateWorkflowResult {
            request_id: request.id.clone(),
            run_id: request.run_id.clone(),
            revision: request.revision,
            task_id: request.task_id.clone(),
            workspace_id: request.source.id.clone(),
        },
        &request.source_sha,
        request.id.clone(),
    )
    .await?;
    if &current != request {
        bail!("integration result, resources or expected SHA changed after reservation");
    }
    Ok(())
}

fn resource(record: &WorkflowWorkspaceRecord) -> WorkflowGitResource {
    WorkflowGitResource {
        id: record.identity.workspace.id.clone(),
        path: record.identity.workspace.path.clone(),
        base_sha: record.identity.base_sha.clone(),
    }
}

pub(super) async fn require_resource(
    tx: &mut Transaction<'_, Sqlite>,
    record: &WorkflowWorkspaceRecord,
) -> Result<()> {
    let workspace = &record.identity.workspace;
    let valid: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM workspaces
        WHERE id = ? AND instanceId = ? AND projectId = ? AND hostId = 'local'
          AND path = ? AND branch = ? AND kind = 'linked' AND status = 'active')",
    )
    .bind(&workspace.id)
    .bind(&workspace.instance_id)
    .bind(&workspace.project_id)
    .bind(&workspace.path)
    .bind(&workspace.branch)
    .fetch_one(&mut **tx)
    .await?;
    if record.phase != WorkflowWorkspacePhase::Ready || !valid {
        bail!("integration requires ready, active, owned workflow workspaces");
    }
    Ok(())
}
