//! Materializes an accepted plan revision: its tasks and its stage gates,
//! which exist from the start but are only due once their stage is done.

use std::collections::BTreeMap;

use anyhow::Result;
use sqlx::{Sqlite, Transaction};

use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::run_plan_gate_store::{insert_run_gate, NewRunGate};
use super::run_plan_proposal::{CompiledPlan, RunRow};
use super::{RunGateKind, RunIsolation, SharedRunPlanSnapshot};

/// The stage-to-profile map dispatch reads for a shared run's workers.
pub(super) fn execution_policy(plan: &SharedRunPlanSnapshot) -> Result<String> {
    Ok(serde_json::to_string(&serde_json::json!({
        "version": 1,
        "stallPolicy": plan.stall_policy,
        "stages": plan.stages.iter().map(|stage| serde_json::json!({
            "id": stage.id,
            "title": stage.title,
            "profile": stage.profile,
            "fallbacks": stage.fallbacks,
        })).collect::<Vec<_>>(),
    }))?)
}

/// Writes the plan's tasks and its not-yet-due stage gates.
pub(super) async fn materialize(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
    run: &RunRow,
    revision: i64,
    plan: &CompiledPlan,
) -> Result<usize> {
    struct Row<'a> {
        logical: &'a str,
        title: &'a str,
        spec: &'a str,
        stage: &'a str,
        role: Option<&'a str>,
        depends_on: &'a [String],
        inputs: Option<String>,
        corrects: Option<&'a str>,
        contract: Option<String>,
    }
    let rows: Vec<Row<'_>> = match plan {
        CompiledPlan::Isolated(plan) => plan
            .tasks
            .iter()
            .map(|task| {
                Ok(Row {
                    logical: &task.task.id,
                    title: &task.task.title,
                    spec: &task.task.spec,
                    stage: &task.task.stage_id,
                    role: Some(&task.task.role_id),
                    depends_on: &task.task.depends_on,
                    inputs: Some(serde_json::to_string(&task.task.inputs)?),
                    corrects: task.task.corrects_task_id.as_deref(),
                    contract: Some(serde_json::to_string(&task.contract)?),
                })
            })
            .collect::<Result<_>>()?,
        CompiledPlan::Shared(plan) => plan
            .tasks
            .iter()
            .map(|task| {
                Ok(Row {
                    logical: &task.id,
                    title: &task.title,
                    spec: &task.spec,
                    stage: &task.stage_id,
                    role: task.role_id.as_deref(),
                    depends_on: &task.depends_on,
                    inputs: task
                        .inputs
                        .as_ref()
                        .map(serde_json::to_string)
                        .transpose()?,
                    corrects: task.corrects_task_id.as_deref(),
                    contract: None,
                })
            })
            .collect::<Result<_>>()?,
    };
    let ids = rows
        .iter()
        .map(|row| (row.logical, format!("task_{}", uuid::Uuid::new_v4())))
        .collect::<BTreeMap<_, _>>();
    let isolated = run.isolation == RunIsolation::Isolated;
    // Isolated tasks stay pending even at a root: only the attempt scheduler
    // makes them executable. Shared tasks follow their dependencies.
    let coordinator = if isolated {
        String::new()
    } else {
        run.coordinator_handle.clone().unwrap_or_default()
    };
    for row in &rows {
        let id = &ids[row.logical];
        let dependencies = row
            .depends_on
            .iter()
            .map(|logical| ids[logical.as_str()].clone())
            .collect::<Vec<_>>();
        let status = if isolated || !dependencies.is_empty() {
            "pending"
        } else {
            "ready"
        };
        sqlx::query(
            "INSERT INTO orchestrationTasks
            (id, task_title, display_name, spec, status, deps, run_id, workspace_id,
             coordinator_handle, stage_id, role_contract, plan_revision, logical_id, role_id,
             inputs, corrects_task_id, created_by_terminal_handle)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(row.title)
        .bind(row.title)
        .bind(row.spec)
        .bind(status)
        .bind(serde_json::to_string(&dependencies)?)
        .bind(run_id)
        .bind(&run.workspace_id)
        .bind(&coordinator)
        .bind(row.stage)
        .bind(&row.contract)
        .bind(revision)
        .bind(row.logical)
        .bind(row.role)
        .bind(&row.inputs)
        .bind(row.corrects)
        .bind(run.coordinator_handle.as_deref())
        .execute(&mut **tx)
        .await?;
        let mut created = NewRunEvent::new(run_id, RunEventKind::TaskCreated);
        created.task_id = Some(id);
        created.summary = row.title;
        created.payload =
            Some(serde_json::json!({ "logicalId": row.logical, "stageId": row.stage }));
        record_run_event(tx, &created).await?;
    }
    let gated: Vec<(String, String)> = match plan {
        CompiledPlan::Isolated(plan) => plan
            .recipe
            .recipe
            .stages
            .iter()
            .filter(|stage| stage.gate.is_some())
            .map(|stage| (stage.id.clone(), stage.name.clone()))
            .collect(),
        CompiledPlan::Shared(plan) => plan
            .stages
            .iter()
            .filter(|stage| stage.gate)
            .map(|stage| {
                (
                    stage.id.clone(),
                    stage.title.clone().unwrap_or_else(|| stage.id.clone()),
                )
            })
            .collect(),
    };
    for (stage, name) in gated {
        let question = format!("Approve stage {name}?");
        insert_run_gate(
            tx,
            &NewRunGate {
                run_id,
                kind: RunGateKind::Stage,
                scope: &stage,
                question: &question,
                plan_revision: Some(revision),
                evidence_digest: None,
                integration_sha: None,
            },
        )
        .await?;
    }
    Ok(rows.len())
}
