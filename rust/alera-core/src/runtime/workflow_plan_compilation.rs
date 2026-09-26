use std::collections::{BTreeMap, BTreeSet};

use anyhow::{anyhow, bail, Result};

use super::orchestration_contract_schema::bounded_json;
use super::orchestration_role_contract::portable_id;
use super::workflow_plan::workflow_text;
use super::{
    AgentProfile, AgentProfileLaunchMode, FrozenWorkflowTask, RoleContractSnapshot,
    WorkflowPlanProposal, WorkflowPlanSnapshot, WorkflowRecipeSnapshot, WORKFLOW_PLAN_MAX_BYTES,
    WORKFLOW_PLAN_MAX_TASKS,
};

pub(super) fn compile_plan(
    proposal: WorkflowPlanProposal,
    recipe: WorkflowRecipeSnapshot,
    profiles: BTreeMap<String, AgentProfile>,
    source_workspace: super::WorkflowSourceWorkspace,
) -> Result<WorkflowPlanSnapshot> {
    bounded_json(&serde_json::to_value(&proposal)?, WORKFLOW_PLAN_MAX_BYTES)?;
    recipe.validate()?;
    workflow_text(&proposal.objective, 16384)?;
    if proposal.source_sha.len() != 40
        || !proposal
            .source_sha
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        bail!("workflow source must be an exact lowercase commit SHA");
    }
    if !(1..=16).contains(&proposal.max_concurrent)
        || proposal.tasks.is_empty()
        || proposal.tasks.len() > WORKFLOW_PLAN_MAX_TASKS
    {
        bail!("workflow requires 1-128 tasks and 1-16 concurrent workers");
    }
    if proposal.recipe_source != recipe.source
        || proposal.expected_recipe_digest != recipe.recipe.content_digest()?
    {
        bail!("workflow recipe changed; refresh before proposing a plan");
    }
    let role_ids = recipe
        .recipe
        .roles
        .iter()
        .map(|role| role.id.clone())
        .collect::<BTreeSet<_>>();
    if proposal
        .role_profiles
        .keys()
        .cloned()
        .collect::<BTreeSet<_>>()
        != role_ids
    {
        bail!("workflow requires exactly one profile binding for every role");
    }
    let mut required_profiles = proposal
        .role_profiles
        .values()
        .cloned()
        .collect::<BTreeSet<_>>();
    required_profiles.insert(proposal.coordinator_profile_id.clone());
    if profiles.keys().cloned().collect::<BTreeSet<_>>() != required_profiles {
        bail!("workflow references a missing profile");
    }
    for (id, profile) in &profiles {
        if id != &profile.id || profile.revision < 0 {
            bail!("workflow profile identity or revision is invalid");
        }
        workflow_text(&profile.agent_type, 160)?;
        workflow_text(&profile.command, 16384)?;
        if profile.launch_mode == AgentProfileLaunchMode::Managed
            && profile.managed_config.is_none()
        {
            bail!("managed workflow profile requires launch configuration");
        }
    }
    let stages = recipe
        .recipe
        .stages
        .iter()
        .map(|stage| (stage.id.as_str(), stage))
        .collect::<BTreeMap<_, _>>();
    let roles = recipe
        .recipe
        .roles
        .iter()
        .map(|role| (role.id.as_str(), role))
        .collect::<BTreeMap<_, _>>();
    let ids = proposal
        .tasks
        .iter()
        .map(|task| task.id.clone())
        .collect::<BTreeSet<_>>();
    if ids.len() != proposal.tasks.len() {
        bail!("duplicate workflow task id");
    }
    let mut frozen = Vec::new();
    for original in &proposal.tasks {
        let mut task = original.clone();
        portable_id(&task.id)?;
        workflow_text(&task.title, 256)?;
        workflow_text(&task.spec, 16384)?;
        if task.depends_on.len() > WORKFLOW_PLAN_MAX_TASKS {
            bail!("workflow task exceeds the dependency limit");
        }
        let stage = stages
            .get(task.stage_id.as_str())
            .ok_or_else(|| anyhow!("unknown workflow task stage"))?;
        if !stage.roles.contains(&task.role_id) {
            bail!("workflow role is not allowed in this stage");
        }
        let role = roles
            .get(task.role_id.as_str())
            .ok_or_else(|| anyhow!("unknown workflow task role"))?;
        let mut dependencies = BTreeSet::new();
        for dependency in &task.depends_on {
            if dependency == &task.id
                || !ids.contains(dependency)
                || !dependencies.insert(dependency.clone())
            {
                bail!("workflow task dependency is missing, duplicated or self-referential");
            }
        }
        // Stage ordering is part of the recipe contract, not an optional edge
        // the coordinator can omit from its concrete DAG.
        for predecessor in &proposal.tasks {
            if stage.depends_on.contains(&predecessor.stage_id) {
                dependencies.insert(predecessor.id.clone());
            }
        }
        task.depends_on = dependencies.into_iter().collect();
        let contract = recipe
            .recipe
            .contracts
            .iter()
            .find(|contract| {
                contract.id == role.contract_id && contract.revision == role.contract_revision
            })
            .ok_or_else(|| anyhow!("missing workflow contract revision"))?;
        frozen.push(FrozenWorkflowTask {
            contract: RoleContractSnapshot::freeze(contract.clone(), task.inputs.clone())?,
            profile_id: proposal.role_profiles[&task.role_id].clone(),
            task,
        });
    }
    for stage in stages.values() {
        for role in &stage.roles {
            if !frozen
                .iter()
                .any(|task| task.task.stage_id == stage.id && &task.task.role_id == role)
            {
                bail!("workflow plan omits a mandatory stage or role");
            }
        }
    }
    let mut ordered = Vec::new();
    let mut visited = BTreeSet::new();
    while ordered.len() < frozen.len() {
        let before = ordered.len();
        for task in &frozen {
            if !visited.contains(&task.task.id)
                && task.task.depends_on.iter().all(|id| visited.contains(id))
            {
                visited.insert(task.task.id.clone());
                ordered.push(task.clone());
            }
        }
        if before == ordered.len() {
            bail!("workflow task dependencies contain a cycle");
        }
    }
    let mut snapshot = WorkflowPlanSnapshot {
        version: 1,
        source_workspace,
        objective: proposal.objective,
        source_sha: proposal.source_sha,
        recipe,
        coordinator_profile_id: proposal.coordinator_profile_id,
        profiles,
        max_concurrent: proposal.max_concurrent,
        tasks: ordered,
        digest: String::new(),
    };
    bounded_json(&serde_json::to_value(&snapshot)?, WORKFLOW_PLAN_MAX_BYTES)?;
    snapshot.digest = snapshot.content_digest()?;
    Ok(snapshot)
}
