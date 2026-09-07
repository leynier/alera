use std::collections::{BTreeMap, BTreeSet};

use anyhow::{anyhow, Result};
use serde::Serialize;
use sqlx::Row;

use super::workflow_plan::workflow_digest;
use super::{
    IntegrateWorkflowResult, LaunchWorkflowTask, PrepareWorkflowWorkspace, RuntimeStore,
    WorkflowPlanSnapshot,
};

#[cfg(test)]
#[path = "workflow_execution_step_logic_tests.rs"]
mod tests;

#[derive(Debug, Serialize)]
#[serde(tag = "kind", content = "request", rename_all = "camelCase")]
pub enum WorkflowExecutionStep {
    PrepareWorkspace(PrepareWorkflowWorkspace),
    LaunchTask(LaunchWorkflowTask),
    IntegrateResult(IntegrateWorkflowResult),
    Waiting,
    Attention { reason: String },
    Complete,
}

struct TaskState {
    id: String,
    logical_id: String,
    status: String,
    integrated: bool,
    workspace: Option<String>,
    phase: Option<String>,
    integration: Option<String>,
    integration_request: Option<String>,
}

impl RuntimeStore {
    /// Called on the host's blocking lane: one bounded task projection and gate
    /// projection, not one database read for each dependency or rendered task.
    pub async fn workflow_execution_step(
        &self,
        run_id: &str,
        revision: i64,
    ) -> Result<WorkflowExecutionStep> {
        let mut tx = self.pool().begin().await?;
        let running: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM workflowExecution e JOIN workflowRuns w ON w.run_id=e.run_id
            WHERE e.run_id=? AND e.revision=? AND e.status='running'
              AND w.revision=e.revision AND w.status='approved')",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_one(&mut *tx)
        .await?;
        if !running {
            return Ok(WorkflowExecutionStep::Waiting);
        }
        let (plan, _) =
            super::workflow_workspace_eligibility::approved_plan(&mut tx, run_id, revision).await?;
        let integration: Option<String> = sqlx::query_scalar(
            "SELECT phase FROM workflowWorkspaces WHERE run_id=? AND task_id IS NULL",
        )
        .bind(run_id)
        .fetch_optional(&mut *tx)
        .await?;
        match integration.as_deref() {
            None => return prepare(run_id, revision, None),
            Some("attention") => {
                return attention("Inspect the integration workspace before continuing.")
            }
            Some("ready") => {}
            _ => return Ok(WorkflowExecutionStep::Waiting),
        }
        let rows = sqlx::query(
            "SELECT p.task_id,p.logical_id,t.status,t.result,e.result_digest,
              x.id AS workspace,x.phase,i.state AS integration,i.request_id AS integration_request
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id=p.task_id
            LEFT JOIN workflowTaskEvidence e ON e.task_id=p.task_id
            LEFT JOIN workflowWorkspaces x ON x.task_id=p.task_id
              AND x.attempt=(SELECT MAX(attempt) FROM workflowWorkspaces WHERE task_id=p.task_id)
            LEFT JOIN workflowIntegrations i ON i.workspace_id=x.id
              AND i.sequence=(SELECT MAX(sequence) FROM workflowIntegrations WHERE workspace_id=x.id)
            WHERE p.run_id=? AND p.revision=? ORDER BY p.logical_id LIMIT 129",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_all(&mut *tx)
        .await?;
        if rows.len() != plan.tasks.len() || rows.len() > 128 {
            return attention("The executable tasks do not match the approved plan.");
        }
        let tasks = rows
            .into_iter()
            .map(|row| {
                let result: Option<String> = row.try_get("result")?;
                let digest: Option<String> = row.try_get("result_digest")?;
                let status: String = row.try_get("status")?;
                Ok(TaskState {
                    id: row.try_get("task_id")?,
                    logical_id: row.try_get("logical_id")?,
                    integrated: status == "completed"
                        && result.is_some()
                        && digest.as_deref() == Some(workflow_digest(&result)?.as_str()),
                    status,
                    workspace: row.try_get("workspace")?,
                    phase: row.try_get("phase")?,
                    integration: row.try_get("integration")?,
                    integration_request: row.try_get("integration_request")?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let gates = sqlx::query(
            "SELECT stage_id,status FROM workflowStageGates WHERE run_id=? AND revision=?",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .map(|row| {
            Ok((
                row.try_get::<String, _>("stage_id")?,
                row.try_get::<String, _>("status")?,
            ))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
        tx.commit().await?;
        choose(run_id, revision, &plan, &tasks, &gates)
    }
}

fn choose(
    run: &str,
    revision: i64,
    plan: &WorkflowPlanSnapshot,
    tasks: &[TaskState],
    gates: &BTreeMap<String, String>,
) -> Result<WorkflowExecutionStep> {
    if tasks.iter().any(|task| {
        task.phase.as_deref() == Some("attention")
            || matches!(task.status.as_str(), "failed" | "stalled" | "cancelled")
            || matches!(task.integration.as_deref(), Some("conflict" | "attention"))
    }) {
        return attention("Inspect the failed task, workspace or integration before continuing.");
    }
    // Integration is serial and precedes scheduling dependents. Completion
    // alone is never treated as satisfied dependency evidence.
    if let Some(task) = tasks
        .iter()
        .find(|task| task.status == "completed" && !task.integrated)
    {
        if task.integration.as_deref() == Some("integrated") {
            return attention(
                "The integrated task evidence changed; prepare a correction revision.",
            );
        }
        let Some(workspace) = &task.workspace else {
            return attention("The completed task has no managed execution workspace.");
        };
        return Ok(WorkflowExecutionStep::IntegrateResult(
            IntegrateWorkflowResult {
                request_id: task
                    .integration_request
                    .clone()
                    .unwrap_or(workflow_digest(&(
                        "integrate",
                        run,
                        revision,
                        &task.id,
                        workspace,
                    ))?),
                run_id: run.into(),
                revision,
                task_id: task.id.clone(),
                workspace_id: workspace.clone(),
            },
        ));
    }
    if tasks.iter().all(|task| task.integrated) {
        let all_gates = plan
            .recipe
            .recipe
            .stages
            .iter()
            .filter(|stage| stage.gate.is_some())
            .all(|stage| {
                gates
                    .get(&stage.id)
                    .is_some_and(|status| status == "approved")
            });
        return Ok(if all_gates {
            WorkflowExecutionStep::Complete
        } else {
            WorkflowExecutionStep::Waiting
        });
    }
    let active = tasks
        .iter()
        .filter(|task| !task.integrated && task.status != "completed" && task.workspace.is_some())
        .count();
    let integrated = tasks
        .iter()
        .filter(|task| task.integrated)
        .map(|task| task.logical_id.as_str())
        .collect::<BTreeSet<_>>();
    for task in tasks
        .iter()
        .filter(|task| matches!(task.status.as_str(), "pending" | "ready"))
    {
        let frozen = plan
            .tasks
            .iter()
            .find(|item| item.task.id == task.logical_id)
            .ok_or_else(|| anyhow!("task is absent from frozen plan"))?;
        if !frozen
            .task
            .depends_on
            .iter()
            .all(|id| integrated.contains(id.as_str()))
            || !gates_allow(plan, &frozen.task.stage_id, gates)?
        {
            continue;
        }
        match (&task.workspace, task.phase.as_deref()) {
            (None, _) if active < plan.max_concurrent as usize => {
                return prepare(run, revision, Some(task.id.clone()))
            }
            (Some(workspace), Some("ready")) => {
                return Ok(WorkflowExecutionStep::LaunchTask(LaunchWorkflowTask {
                    request_id: workflow_digest(&("launch", run, revision, &task.id, workspace))?,
                    run_id: run.into(),
                    revision,
                    task_id: task.id.clone(),
                    workspace_id: workspace.clone(),
                }))
            }
            _ => {}
        }
    }
    Ok(WorkflowExecutionStep::Waiting)
}

fn gates_allow(
    plan: &WorkflowPlanSnapshot,
    stage: &str,
    gates: &BTreeMap<String, String>,
) -> Result<bool> {
    let first = plan
        .recipe
        .recipe
        .stages
        .iter()
        .find(|item| item.id == stage)
        .ok_or_else(|| anyhow!("task stage is absent from frozen plan"))?;
    let mut remaining = first.depends_on.clone();
    let mut seen = BTreeSet::new();
    while let Some(id) = remaining.pop() {
        if !seen.insert(id.clone()) {
            continue;
        }
        let prior = plan
            .recipe
            .recipe
            .stages
            .iter()
            .find(|item| item.id == id)
            .ok_or_else(|| anyhow!("prerequisite stage is absent from frozen plan"))?;
        if prior.gate.is_some() && gates.get(&id).is_none_or(|status| status != "approved") {
            return Ok(false);
        }
        remaining.extend(prior.depends_on.clone());
    }
    Ok(true)
}

fn prepare(run: &str, revision: i64, task_id: Option<String>) -> Result<WorkflowExecutionStep> {
    Ok(WorkflowExecutionStep::PrepareWorkspace(
        PrepareWorkflowWorkspace {
            request_id: workflow_digest(&("prepare", run, revision, &task_id))?,
            run_id: run.into(),
            revision,
            task_id,
            retry_of: None,
        },
    ))
}

fn attention(reason: &str) -> Result<WorkflowExecutionStep> {
    Ok(WorkflowExecutionStep::Attention {
        reason: reason.into(),
    })
}
