use std::collections::{BTreeMap, BTreeSet};

use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use sqlx::Row;

use super::workflow_plan::workflow_digest;
use super::{
    RuntimeStore, WorkflowExecutionState, WorkflowHumanGate, WorkflowPlanSnapshot,
    WorkflowRecipeSource,
};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowRunControls {
    pub run_id: String,
    pub revision: i64,
    pub status: String,
    pub can_control: bool,
    pub can_cancel: bool,
    pub can_correct: bool,
    pub cancellation_pending: i64,
    pub cancellation_error: Option<String>,
    pub integration_sha: String,
    pub source_sha: String,
    pub recipe_name: String,
    pub recipe_source: WorkflowRecipeSource,
    pub execution: Option<WorkflowExecutionState>,
    pub stages: Vec<WorkflowStageControl>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowStageControl {
    pub id: String,
    pub name: String,
    pub depends_on: Vec<String>,
    pub gate: Option<WorkflowHumanGate>,
    pub gate_status: Option<String>,
    pub can_review: bool,
    pub task_count: usize,
    pub integrated_count: usize,
}

impl RuntimeStore {
    /// A bounded projection for the selected run, evaluated off the host actor.
    /// Review availability is advisory; the approval path revalidates evidence.
    pub async fn workflow_run_controls(
        &self,
        run: &str,
        expected_revision: Option<i64>,
    ) -> Result<WorkflowRunControls> {
        let mut tx = self.pool().begin().await?;
        let row=sqlx::query("SELECT w.revision,w.status,w.integration_sha,p.snapshot,c.status AS coordinator_status,
            e.sequence,e.status AS execution_status,i.reason AS attention
            FROM workflowRuns w JOIN workflowPlanRevisions p ON p.run_id=w.run_id AND p.revision=w.revision
            JOIN orchestrationCoordinatorRuns c ON c.id=w.run_id
            LEFT JOIN workflowExecution e ON e.run_id=w.run_id AND e.revision=w.revision
            LEFT JOIN workflowExecutionIssues i ON i.run_id=e.run_id AND i.revision=e.revision AND i.sequence=e.sequence
            WHERE w.run_id=?")
            .bind(run).fetch_optional(&mut *tx).await?.ok_or_else(||anyhow!("workflow run not found"))?;
        let revision: i64 = row.try_get("revision")?;
        if expected_revision.is_some_and(|expected| expected != revision) {
            bail!("workflow revision changed; refresh the run");
        }
        let plan: WorkflowPlanSnapshot =
            serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?;
        if plan.content_digest()? != plan.digest {
            bail!("workflow plan snapshot is invalid");
        }
        let status: String = row.try_get("status")?;
        let cancellation = sqlx::query("SELECT COUNT(*) AS pending,MIN(error) AS error FROM workflowCancellationTargets WHERE run_id=? AND state<>'settled'")
            .bind(run).fetch_one(&mut *tx).await?;
        let cancellation_pending = cancellation.try_get("pending")?;
        let cancellation_error: Option<String> = cancellation.try_get("error")?;
        let can_cancel =
            status != "completed" && (status != "cancelled" || cancellation_error.is_some());
        let can_control = status == "approved"
            && matches!(
                row.try_get::<String, _>("coordinator_status")?.as_str(),
                "idle" | "running"
            );
        let can_correct = matches!(
            status.as_str(),
            "prepared" | "rejected" | "changesRequested"
        ) && matches!(
            row.try_get::<String, _>("coordinator_status")?.as_str(),
            "idle" | "running"
        );
        let sequence: Option<i64> = row.try_get("sequence")?;
        let execution = sequence
            .map(|sequence| -> Result<WorkflowExecutionState> {
                Ok(WorkflowExecutionState {
                    run_id: run.into(),
                    revision,
                    sequence,
                    status: if matches!(status.as_str(), "completed" | "cancelled") {
                        status.clone()
                    } else {
                        row.try_get("execution_status")?
                    },
                    attention: row.try_get("attention")?,
                })
            })
            .transpose()?;
        let tasks=sqlx::query("SELECT t.stage_id,t.status,t.result,e.result_digest,e.artifact_digest,e.integration_sha
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id=p.task_id
            LEFT JOIN workflowTaskEvidence e ON e.task_id=p.task_id WHERE p.run_id=? AND p.revision=? LIMIT 129")
            .bind(run).bind(revision).fetch_all(&mut *tx).await?;
        if tasks.len() > 128 {
            bail!("workflow tasks exceed the projection limit");
        }
        let mut integrated = BTreeMap::<String, usize>::new();
        for task in &tasks {
            let result: Option<String> = task.try_get("result")?;
            let digest: Option<String> = task.try_get("result_digest")?;
            if task.try_get::<String, _>("status")? == "completed"
                && result.is_some()
                && digest.as_deref() == Some(workflow_digest(&result)?.as_str())
                && task
                    .try_get::<Option<String>, _>("artifact_digest")?
                    .is_some()
                && task
                    .try_get::<Option<String>, _>("integration_sha")?
                    .is_some()
            {
                *integrated.entry(task.try_get("stage_id")?).or_default() += 1;
            }
        }
        let gates = sqlx::query(
            "SELECT stage_id,status FROM workflowStageGates WHERE run_id=? AND revision=?",
        )
        .bind(run)
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
        let unsettled:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowIntegrations WHERE run_id=? AND state IN ('pending','prepared','attention'))")
            .bind(run).fetch_one(&mut *tx).await?;
        let stages = plan
            .recipe
            .recipe
            .stages
            .iter()
            .map(|stage| {
                let mut pending = vec![stage.id.clone()];
                let mut ancestors = BTreeSet::new();
                let mut ready = can_control
                    && !unsettled
                    && gates.get(&stage.id).is_some_and(|state| state == "pending");
                while let Some(id) = pending.pop() {
                    if !ancestors.insert(id.clone()) {
                        continue;
                    }
                    let prior = plan
                        .recipe
                        .recipe
                        .stages
                        .iter()
                        .find(|item| item.id == id)
                        .ok_or_else(|| anyhow!("workflow prerequisite stage missing"))?;
                    pending.extend(prior.depends_on.clone());
                    let expected = plan
                        .tasks
                        .iter()
                        .filter(|task| task.task.stage_id == id)
                        .count();
                    ready &= integrated.get(&id).copied().unwrap_or(0) == expected;
                    if id != stage.id && prior.gate.is_some() {
                        ready &= gates.get(&id).is_some_and(|state| state == "approved");
                    }
                }
                Ok(WorkflowStageControl {
                    id: stage.id.clone(),
                    name: stage.name.clone(),
                    depends_on: stage.depends_on.clone(),
                    gate: stage.gate,
                    gate_status: gates.get(&stage.id).cloned(),
                    can_review: stage.gate.is_some() && ready,
                    task_count: plan
                        .tasks
                        .iter()
                        .filter(|task| task.task.stage_id == stage.id)
                        .count(),
                    integrated_count: integrated.get(&stage.id).copied().unwrap_or(0),
                })
            })
            .collect::<Result<Vec<_>>>()?;
        tx.commit().await?;
        Ok(WorkflowRunControls {
            run_id: run.into(),
            revision,
            status,
            can_control,
            can_cancel,
            can_correct,
            cancellation_pending,
            cancellation_error,
            integration_sha: row.try_get("integration_sha")?,
            source_sha: plan.source_sha,
            recipe_name: plan.recipe.recipe.name,
            recipe_source: plan.recipe.source,
            execution,
            stages,
        })
    }
}
