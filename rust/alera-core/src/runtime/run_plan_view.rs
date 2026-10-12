//! Read models of a run's plan: `runs.plan` for people and
//! `orchestration.planContext` for the coordinator that proposes it.

use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use serde::Serialize;
use serde_json::{json, Value};
use sqlx::Row;

use super::run_gate_resolution::{run_gate_from_row, RUN_GATE_COLUMNS};
use super::run_lifecycle::FrozenRunSelection;
use super::{RunGate, RuntimeStore, SharedRunPlanSnapshot, WorkflowPlanSnapshot};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPlanStageView {
    pub id: String,
    pub title: String,
    pub role_ids: Vec<String>,
    pub depends_on: Vec<String>,
    pub profile: Option<String>,
    pub fallbacks: Vec<String>,
    pub gate: bool,
    /// `foundation` or `product` for recipe gates.
    pub gate_kind: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPlanTaskView {
    pub id: String,
    pub task_id: Option<String>,
    pub title: String,
    pub spec: String,
    pub stage_id: String,
    pub role_id: Option<String>,
    pub depends_on: Vec<String>,
    pub inputs: Option<Value>,
    pub corrects_task_id: Option<String>,
    pub profile_id: Option<String>,
    pub status: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPlanView {
    pub run_id: String,
    pub revision: i64,
    pub current_revision: Option<i64>,
    pub isolation: String,
    pub run_status: String,
    pub approval_required: bool,
    pub stall_policy: String,
    pub max_concurrent: i64,
    pub objective: String,
    pub source_sha: Option<String>,
    pub digest: String,
    pub previous_revision: Option<i64>,
    pub change_reason: Option<String>,
    pub change_task_ids: Vec<String>,
    /// A change request copied the previous plan; the coordinator has not
    /// proposed the next one yet.
    pub placeholder: bool,
    pub recipe: Option<Value>,
    pub coordinator_profile_id: Option<String>,
    pub role_profiles: BTreeMap<String, String>,
    pub stages: Vec<RunPlanStageView>,
    pub tasks: Vec<RunPlanTaskView>,
    pub plan_gate: Option<RunGate>,
}

impl RuntimeStore {
    /// A revision of a run's plan (the current one by default); `None` while
    /// the run has no plan yet.
    pub async fn run_plan_view(
        &self,
        run_id: &str,
        revision: Option<i64>,
    ) -> Result<Option<RunPlanView>> {
        let run = sqlx::query(
            "SELECT isolation, status, approval_required, stall_policy, max_concurrent, spec,
                plan_revision, json_extract(source_snapshot, '$.sourceSha') AS source_sha
            FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| anyhow!("run_not_found: no run {run_id}"))?;
        let current: Option<i64> = run.try_get("plan_revision")?;
        let Some(revision) = revision.or(current) else {
            return Ok(None);
        };
        let Some(plan) = sqlx::query(
            "SELECT snapshot, digest, previous_revision, change_reason, change_task_ids, request_id
            FROM runPlanRevisions WHERE run_id = ? AND revision = ?",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_optional(self.pool())
        .await?
        else {
            return Ok(None);
        };
        let statuses = sqlx::query(
            "SELECT id, logical_id, status FROM orchestrationTasks
            WHERE run_id = ? AND plan_revision = ?",
        )
        .bind(run_id)
        .bind(revision)
        .fetch_all(self.pool())
        .await?
        .into_iter()
        .map(|row| {
            Ok((
                row.try_get::<String, _>("logical_id")?,
                (
                    row.try_get::<String, _>("id")?,
                    row.try_get::<String, _>("status")?,
                ),
            ))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
        let plan_gate = sqlx::query(sqlx::AssertSqlSafe(format!(
            "SELECT {RUN_GATE_COLUMNS} FROM runGates WHERE run_id = ? AND kind = 'plan'
            AND plan_revision = ? ORDER BY rowid DESC LIMIT 1"
        )))
        .bind(run_id)
        .bind(revision)
        .fetch_optional(self.pool())
        .await?
        .map(run_gate_from_row)
        .transpose()?;
        let snapshot: String = plan.try_get("snapshot")?;
        let isolation: String = run.try_get("isolation")?;
        let lookup = |logical: &str| statuses.get(logical).cloned();
        let (recipe, coordinator_profile_id, role_profiles, stages, tasks) =
            if isolation == "isolated" {
                isolated_view(&serde_json::from_str(&snapshot)?, lookup)
            } else {
                shared_view(&serde_json::from_str(&snapshot)?, lookup)
            };
        Ok(Some(RunPlanView {
            run_id: run_id.into(),
            revision,
            current_revision: current,
            isolation,
            run_status: run.try_get("status")?,
            approval_required: run.try_get("approval_required")?,
            stall_policy: run.try_get("stall_policy")?,
            max_concurrent: run.try_get("max_concurrent")?,
            objective: run.try_get("spec")?,
            source_sha: run.try_get("source_sha")?,
            digest: plan.try_get("digest")?,
            previous_revision: plan.try_get("previous_revision")?,
            change_reason: plan.try_get("change_reason")?,
            change_task_ids: plan
                .try_get::<Option<String>, _>("change_task_ids")?
                .and_then(|raw| serde_json::from_str(&raw).ok())
                .unwrap_or_default(),
            placeholder: plan
                .try_get::<String, _>("request_id")?
                .starts_with("changes:"),
            recipe,
            coordinator_profile_id,
            role_profiles,
            stages,
            tasks,
            plan_gate,
        }))
    }

    /// What a coordinator needs to propose a plan: the frozen objective,
    /// source, recipe and profiles, and the change request it answers.
    pub async fn run_plan_context(&self, run_id: &str) -> Result<Value> {
        let row = sqlx::query(
            "SELECT spec, status, isolation, approval_required, stall_policy, max_concurrent,
                workspace_id, plan_revision, recipe_snapshot, profiles_snapshot, source_snapshot,
                coordinator_profile_id
            FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| anyhow!("run_not_found: no run {run_id}"))?;
        let selection: Option<FrozenRunSelection> = row
            .try_get::<Option<String>, _>("profiles_snapshot")?
            .map(|raw| serde_json::from_str(&raw))
            .transpose()?;
        let source: Option<Value> = row
            .try_get::<Option<String>, _>("source_snapshot")?
            .and_then(|raw| serde_json::from_str(&raw).ok());
        let recipe = selection
            .as_ref()
            .and_then(|selection| selection.recipe.as_ref());
        let profiles = selection
            .as_ref()
            .map(|selection| {
                selection
                    .profiles
                    .values()
                    .map(|profile| {
                        json!({
                            "id": profile.id,
                            "name": profile.name,
                            "agentType": profile.agent_type,
                            "description": profile.description,
                        })
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let current = self.run_plan_view(run_id, None).await?;
        let correction = match &current {
            Some(plan) if plan.placeholder => {
                let prior = sqlx::query(
                    "SELECT t.id, t.logical_id, t.status, substr(t.result, 1, 1024) AS preview,
                        COALESCE(length(t.result) > 1024, 0) AS truncated, e.integration_sha
                    FROM orchestrationTasks t LEFT JOIN runTaskEvidence e ON e.task_id = t.id
                    WHERE t.run_id = ? AND t.plan_revision IS NOT NULL
                    ORDER BY t.plan_revision, t.logical_id LIMIT 256",
                )
                .bind(run_id)
                .fetch_all(self.pool())
                .await?
                .into_iter()
                .map(|task| -> Result<Value> {
                    Ok(json!({
                        "taskId": task.try_get::<String, _>("id")?,
                        "logicalId": task.try_get::<Option<String>, _>("logical_id")?,
                        "status": task.try_get::<String, _>("status")?,
                        "resultPreview": task.try_get::<Option<String>, _>("preview")?,
                        "resultTruncated": task.try_get::<bool, _>("truncated")?,
                        "integrationSha": task.try_get::<Option<String>, _>("integration_sha")?,
                    }))
                })
                .collect::<Result<Vec<_>>>()?;
                Some(json!({
                    "revision": plan.previous_revision,
                    "reason": plan.change_reason,
                    "taskIds": plan.change_task_ids,
                    "priorTasks": prior,
                }))
            }
            _ => None,
        };
        let isolation: String = row.try_get("isolation")?;
        Ok(json!({
            "runId": run_id,
            "objective": row.try_get::<String, _>("spec")?,
            "status": row.try_get::<String, _>("status")?,
            "isolation": isolation,
            "approvalRequired": row.try_get::<bool, _>("approval_required")?,
            "stallPolicy": row.try_get::<String, _>("stall_policy")?,
            "maxConcurrent": row.try_get::<i64, _>("max_concurrent")?,
            "workspaceId": row.try_get::<String, _>("workspace_id")?,
            "source": source,
            "coordinatorProfileId": row.try_get::<Option<String>, _>("coordinator_profile_id")?,
            "recipe": recipe.map(|recipe| json!({
                "source": recipe.source,
                "id": recipe.recipe.id,
                "name": recipe.recipe.name,
                "revision": recipe.recipe.revision,
                "coordinatorInstructions": recipe.recipe.coordinator_instructions,
                "roles": recipe.recipe.roles,
                "stages": recipe.recipe.stages,
                "contracts": recipe.recipe.contracts.iter().map(|contract| json!({
                    "id": contract.id,
                    "revision": contract.revision,
                    "name": contract.name,
                    "purpose": contract.purpose,
                    "inputSchema": contract.input_schema,
                })).collect::<Vec<_>>(),
            })),
            "profiles": profiles,
            "roleProfiles": selection.as_ref().map(|selection| selection.role_profiles.clone()),
            "workerProfileId": selection.as_ref().and_then(|selection| selection.worker_profile_id.clone()),
            "currentPlan": current,
            "correction": correction,
            "planShape": if isolation == "isolated" {
                json!({"tasks": [{"id": "task-id", "title": "Title", "spec": "What to do",
                    "stageId": "stage-id", "roleId": "role-id", "dependsOn": [], "inputs": {}}]})
            } else {
                json!({"stages": [{"id": "work", "title": "Work", "profile": "Profile name",
                    "fallbacks": [], "gate": false}],
                    "tasks": [{"id": "task-id", "title": "Title", "spec": "What to do",
                    "stageId": "work", "dependsOn": []}]})
            },
        }))
    }
}

type PlanParts = (
    Option<Value>,
    Option<String>,
    BTreeMap<String, String>,
    Vec<RunPlanStageView>,
    Vec<RunPlanTaskView>,
);

fn isolated_view(
    plan: &WorkflowPlanSnapshot,
    lookup: impl Fn(&str) -> Option<(String, String)>,
) -> PlanParts {
    let mut role_profiles = BTreeMap::new();
    for task in &plan.tasks {
        role_profiles.insert(task.task.role_id.clone(), task.profile_id.clone());
    }
    let stages = plan
        .recipe
        .recipe
        .stages
        .iter()
        .map(|stage| RunPlanStageView {
            id: stage.id.clone(),
            title: stage.name.clone(),
            role_ids: stage.roles.clone(),
            depends_on: stage.depends_on.clone(),
            profile: None,
            fallbacks: Vec::new(),
            gate: stage.gate.is_some(),
            gate_kind: stage
                .gate
                .and_then(|gate| serde_json::to_value(gate).ok())
                .and_then(|gate| gate.as_str().map(str::to_string)),
        })
        .collect();
    let tasks = plan
        .tasks
        .iter()
        .map(|task| {
            let state = lookup(&task.task.id);
            RunPlanTaskView {
                id: task.task.id.clone(),
                task_id: state.as_ref().map(|(id, _)| id.clone()),
                title: task.task.title.clone(),
                spec: task.task.spec.clone(),
                stage_id: task.task.stage_id.clone(),
                role_id: Some(task.task.role_id.clone()),
                depends_on: task.task.depends_on.clone(),
                inputs: Some(task.task.inputs.clone()),
                corrects_task_id: task.task.corrects_task_id.clone(),
                profile_id: Some(task.profile_id.clone()),
                status: state.map(|(_, status)| status),
            }
        })
        .collect();
    (
        Some(json!({
            "source": plan.recipe.source,
            "id": plan.recipe.recipe.id,
            "name": plan.recipe.recipe.name,
            "revision": plan.recipe.recipe.revision,
            "digest": plan.recipe.digest,
        })),
        Some(plan.coordinator_profile_id.clone()),
        role_profiles,
        stages,
        tasks,
    )
}

fn shared_view(
    plan: &SharedRunPlanSnapshot,
    lookup: impl Fn(&str) -> Option<(String, String)>,
) -> PlanParts {
    let stages = plan
        .stages
        .iter()
        .map(|stage| RunPlanStageView {
            id: stage.id.clone(),
            title: stage.title.clone().unwrap_or_else(|| stage.id.clone()),
            role_ids: Vec::new(),
            depends_on: Vec::new(),
            profile: stage.profile.clone(),
            fallbacks: stage.fallbacks.clone(),
            gate: stage.gate,
            gate_kind: None,
        })
        .collect();
    let tasks = plan
        .tasks
        .iter()
        .map(|task| {
            let state = lookup(&task.id);
            RunPlanTaskView {
                id: task.id.clone(),
                task_id: state.as_ref().map(|(id, _)| id.clone()),
                title: task.title.clone(),
                spec: task.spec.clone(),
                stage_id: task.stage_id.clone(),
                role_id: task.role_id.clone(),
                depends_on: task.depends_on.clone(),
                inputs: task.inputs.clone(),
                corrects_task_id: task.corrects_task_id.clone(),
                profile_id: None,
                status: state.map(|(_, status)| status),
            }
        })
        .collect();
    (None, None, BTreeMap::new(), stages, tasks)
}
