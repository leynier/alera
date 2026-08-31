use std::collections::BTreeMap;

use anyhow::Result;
use sqlx::{Sqlite, Transaction};

use super::workflow_gate_evidence::ApprovalState;
use crate::workflow_approval::WorkflowApprovalChallenge;

pub(super) async fn materialize(
    tx: &mut Transaction<'_, Sqlite>,
    challenge: &WorkflowApprovalChallenge,
    state: &ApprovalState,
) -> Result<()> {
    let ids = state
        .plan
        .tasks
        .iter()
        .map(|task| {
            (
                task.task.id.clone(),
                format!("task_{}", uuid::Uuid::new_v4()),
            )
        })
        .collect::<BTreeMap<_, _>>();
    for task in &state.plan.tasks {
        let id = &ids[&task.task.id];
        sqlx::query("INSERT INTO workflowPlanTasks(task_id, run_id, revision, logical_id, frozen_task) VALUES (?, ?, ?, ?, ?)")
            .bind(id).bind(&challenge.run_id).bind(challenge.revision).bind(&task.task.id)
            .bind(serde_json::to_string(task)?).execute(&mut **tx).await?;
        let dependencies = task
            .task
            .depends_on
            .iter()
            .map(|id| &ids[id])
            .collect::<Vec<_>>();
        // Remain pending even at an approved root: only the managed worktree
        // scheduler may make a workflow task executable.
        sqlx::query("INSERT INTO orchestrationTasks
            (id, task_title, display_name, spec, status, deps, run_id, workspace_id, coordinator_handle, stage_id, role_contract)
            VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, '', ?, ?)")
            .bind(id).bind(&task.task.title).bind(&task.task.title).bind(&task.task.spec)
            .bind(serde_json::to_string(&dependencies)?).bind(&challenge.run_id)
            .bind(&state.workspace_id).bind(&task.task.stage_id).bind(serde_json::to_string(&task.contract)?)
            .execute(&mut **tx).await?;
    }
    for stage in &state.plan.recipe.recipe.stages {
        if stage.gate.is_some() {
            sqlx::query(
                "INSERT INTO workflowStageGates(run_id, revision, stage_id) VALUES (?, ?, ?)",
            )
            .bind(&challenge.run_id)
            .bind(challenge.revision)
            .bind(&stage.id)
            .execute(&mut **tx)
            .await?;
        }
    }
    sqlx::query("UPDATE workflowRuns SET status = 'approved' WHERE run_id = ?")
        .bind(&challenge.run_id)
        .execute(&mut **tx)
        .await?;
    sqlx::query(
        "UPDATE orchestrationCoordinatorRuns SET execution_policy_status = 'approved',
        last_activity_at = datetime('now') WHERE id = ?",
    )
    .bind(&challenge.run_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
