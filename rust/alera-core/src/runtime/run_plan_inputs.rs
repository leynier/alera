//! Turns a coordinator's plan v2 input into a compiled plan: isolated runs
//! compile tasks against their frozen recipe, profiles and source; shared runs
//! validate their stages and the task graph.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{anyhow, bail, Result};

use super::orchestration_role_contract::portable_id;
use super::run_catalog::workflow_blocking;
use super::run_lifecycle::FrozenRunSelection;
use super::run_plan::workflow_text;
use super::run_plan_proposal::{CompiledPlan, RunRow};
use super::{
    RunIsolation, RunPlanInput, RunPlanStageInput, RunPlanTaskInput, RunSourceSnapshot,
    SharedRunPlanSnapshot, WorkflowPlanProposal, WorkflowPlanTask,
};

pub(super) async fn compile(run: &RunRow, input: RunPlanInput) -> Result<CompiledPlan> {
    let selection = run
        .profiles_snapshot
        .as_deref()
        .map(serde_json::from_str::<FrozenRunSelection>)
        .transpose()?;
    match run.isolation {
        RunIsolation::Isolated => {
            if !input.stages.is_empty() {
                bail!("an isolated run takes its stages from its recipe");
            }
            let selection = selection.ok_or_else(|| anyhow!("run has no frozen selection"))?;
            let recipe = selection
                .recipe
                .clone()
                .ok_or_else(|| anyhow!("isolated run has no frozen recipe"))?;
            let source: RunSourceSnapshot = serde_json::from_str(
                run.source_snapshot
                    .as_deref()
                    .ok_or_else(|| anyhow!("isolated run has no frozen source"))?,
            )?;
            let coordinator = run
                .coordinator_profile_id
                .clone()
                .ok_or_else(|| anyhow!("isolated run has no coordinator profile"))?;
            let objective = run.objective.clone();
            let max_concurrent = input
                .max_concurrent
                .unwrap_or(run.max_concurrent.clamp(1, 16) as u32);
            workflow_blocking(move || {
                let tasks = input
                    .tasks
                    .into_iter()
                    .map(|task| isolated_task(task, &recipe, &objective))
                    .collect::<Result<Vec<_>>>()?;
                let bound = selection
                    .profiles
                    .iter()
                    .filter(|(id, _)| {
                        selection.role_profiles.values().any(|value| value == *id)
                            || *id == &coordinator
                    })
                    .map(|(id, profile)| (id.clone(), profile.clone()))
                    .collect::<BTreeMap<_, _>>();
                let proposal = WorkflowPlanProposal {
                    objective,
                    source_sha: source.source_sha.clone().unwrap_or_default(),
                    recipe_source: recipe.source.clone(),
                    expected_recipe_digest: recipe.recipe.content_digest()?,
                    coordinator_profile_id: coordinator,
                    role_profiles: selection.role_profiles.clone(),
                    max_concurrent,
                    tasks,
                };
                Ok(CompiledPlan::Isolated(Box::new(
                    super::run_plan_compilation::compile_plan(
                        proposal,
                        recipe,
                        bound,
                        source.workspace,
                    )?,
                )))
            })
            .await
        }
        RunIsolation::Shared => {
            let worker_name = selection.as_ref().and_then(|selection| {
                selection
                    .worker_profile_id
                    .as_ref()
                    .and_then(|id| selection.profiles.get(id))
                    .map(|profile| profile.name.clone())
            });
            let max_concurrent = input
                .max_concurrent
                .unwrap_or(run.max_concurrent.clamp(1, 16) as u32);
            if !(1..=16).contains(&max_concurrent) {
                bail!("plan.maxConcurrent must be between 1 and 16");
            }
            let stall_policy = input
                .stall_policy
                .clone()
                .unwrap_or_else(|| run.stall_policy.clone());
            let plan = shared_plan(
                &run.objective,
                input.stages,
                input.tasks,
                worker_name,
                stall_policy,
                max_concurrent,
            )?;
            Ok(CompiledPlan::Shared(plan))
        }
    }
}

fn isolated_task(
    task: RunPlanTaskInput,
    recipe: &super::WorkflowRecipeSnapshot,
    objective: &str,
) -> Result<WorkflowPlanTask> {
    let role_id = match task.role_id {
        Some(role) => role,
        None => {
            let stage = recipe
                .recipe
                .stages
                .iter()
                .find(|stage| stage.id == task.stage_id)
                .ok_or_else(|| anyhow!("unknown plan task stage: {}", task.stage_id))?;
            match stage.roles.as_slice() {
                [role] => role.clone(),
                _ => bail!(
                    "task {} must name a roleId for stage {}",
                    task.id,
                    task.stage_id
                ),
            }
        }
    };
    Ok(WorkflowPlanTask {
        id: task.id,
        title: task.title,
        spec: task.spec,
        stage_id: task.stage_id,
        role_id,
        depends_on: task.depends_on,
        inputs: task
            .inputs
            .unwrap_or_else(|| serde_json::json!({ "objective": objective })),
        corrects_task_id: task.corrects_task_id,
    })
}

/// Validates a shared plan: unique stage and task ids, known stages, and an
/// acyclic dependency graph. Stage profiles default to the run's worker.
pub(super) fn shared_plan(
    objective: &str,
    stages: Vec<RunPlanStageInput>,
    tasks: Vec<RunPlanTaskInput>,
    worker_profile: Option<String>,
    stall_policy: String,
    max_concurrent: u32,
) -> Result<SharedRunPlanSnapshot> {
    if stages.is_empty() {
        bail!("plan.stages must not be empty");
    }
    let mut stage_ids = BTreeSet::new();
    let stages = stages
        .into_iter()
        .map(|mut stage| {
            portable_id(&stage.id)?;
            if !stage_ids.insert(stage.id.clone()) {
                bail!("duplicate stage id: {}", stage.id);
            }
            if stage.profile.is_none() {
                stage.profile = worker_profile.clone();
            }
            if stage
                .profile
                .as_deref()
                .is_none_or(|name| name.trim().is_empty())
            {
                bail!("stage {} needs a profile", stage.id);
            }
            Ok(stage)
        })
        .collect::<Result<Vec<_>>>()?;
    let ids = tasks
        .iter()
        .map(|task| task.id.clone())
        .collect::<BTreeSet<_>>();
    if ids.len() != tasks.len() {
        bail!("duplicate plan task id");
    }
    for task in &tasks {
        portable_id(&task.id)?;
        workflow_text(&task.title, 256)?;
        workflow_text(&task.spec, 16384)?;
        if !stage_ids.contains(&task.stage_id) {
            bail!("task {} names an unknown stage {}", task.id, task.stage_id);
        }
        for dependency in &task.depends_on {
            if dependency == &task.id || !ids.contains(dependency) {
                bail!(
                    "task {} has a missing or self-referential dependency",
                    task.id
                );
            }
        }
    }
    let mut visited = BTreeSet::<String>::new();
    while visited.len() < tasks.len() {
        let before = visited.len();
        for task in &tasks {
            if !visited.contains(&task.id) && task.depends_on.iter().all(|id| visited.contains(id))
            {
                visited.insert(task.id.clone());
            }
        }
        if before == visited.len() {
            bail!("plan task dependencies contain a cycle");
        }
    }
    let mut plan = SharedRunPlanSnapshot {
        version: 2,
        objective: objective.into(),
        stages,
        tasks,
        stall_policy,
        max_concurrent,
        digest: String::new(),
    };
    plan.digest = plan.content_digest()?;
    Ok(plan)
}
