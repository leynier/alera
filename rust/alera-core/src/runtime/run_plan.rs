use std::collections::BTreeMap;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use super::{AgentProfile, RoleContractSnapshot, WorkflowRecipeSnapshot, WorkflowRecipeSource};

pub const WORKFLOW_PLAN_MAX_BYTES: usize = 1024 * 1024;
pub const WORKFLOW_PLAN_MAX_TASKS: usize = 128;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowPlanTask {
    pub id: String,
    pub title: String,
    pub spec: String,
    pub stage_id: String,
    pub role_id: String,
    pub depends_on: Vec<String>,
    pub inputs: Value,
    /// Corrections are new tasks, never a reopen of a completed task.
    pub corrects_task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowPlanProposal {
    pub objective: String,
    pub source_sha: String,
    pub recipe_source: WorkflowRecipeSource,
    pub expected_recipe_digest: String,
    pub coordinator_profile_id: String,
    pub role_profiles: BTreeMap<String, String>,
    #[serde(default = "default_concurrency")]
    pub max_concurrent: u32,
    pub tasks: Vec<WorkflowPlanTask>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrepareWorkflowPlan {
    pub request_id: String,
    pub workspace_id: String,
    pub run_id: Option<String>,
    pub expected_revision: Option<i64>,
    pub proposal: WorkflowPlanProposal,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FrozenWorkflowTask {
    pub task: WorkflowPlanTask,
    pub contract: RoleContractSnapshot,
    pub profile_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPlanSnapshot {
    pub version: u32,
    pub source_workspace: WorkflowSourceWorkspace,
    pub objective: String,
    pub source_sha: String,
    pub recipe: WorkflowRecipeSnapshot,
    pub coordinator_profile_id: String,
    pub profiles: BTreeMap<String, AgentProfile>,
    pub max_concurrent: u32,
    pub tasks: Vec<FrozenWorkflowTask>,
    pub digest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowSourceWorkspace {
    pub workspace_id: String,
    pub instance_id: String,
    pub project_id: String,
    pub path: String,
    pub project_repo_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPlanRevision {
    pub run_id: String,
    pub workspace_id: String,
    pub revision: i64,
    pub status: String,
    pub current_revision: i64,
    pub integration_sha: String,
    pub plan: WorkflowPlanSnapshot,
    pub previous_revision: Option<i64>,
    pub change_reason: Option<String>,
}

impl WorkflowPlanSnapshot {
    pub fn content_digest(&self) -> Result<String> {
        let mut value = serde_json::to_value(self)?;
        value
            .as_object_mut()
            .expect("snapshot is an object")
            .remove("digest");
        workflow_digest(&value)
    }
}

pub(super) fn workflow_digest(value: &impl Serialize) -> Result<String> {
    let mut value = serde_json::to_value(value)?;
    value.sort_all_objects();
    Ok(hex::encode(Sha256::digest(serde_json::to_vec(&value)?)))
}

pub(super) fn workflow_text(value: &str, max: usize) -> Result<()> {
    if value.trim().is_empty() || value.len() > max || value.contains('\0') {
        bail!("workflow text is empty, too long or contains NUL");
    }
    Ok(())
}

fn default_concurrency() -> u32 {
    4
}

/// How a run's workers share the source checkout.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum RunIsolation {
    /// Workers run in the run's workspace; no integration or cleanup.
    Shared,
    /// Every task attempt gets its own worktree; results integrate as serial
    /// squash commits.
    #[default]
    Isolated,
}

impl RunIsolation {
    pub fn as_str(self) -> &'static str {
        match self {
            RunIsolation::Shared => "shared",
            RunIsolation::Isolated => "isolated",
        }
    }
}

/// The source a run starts from, frozen when it is created.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunSourceSnapshot {
    #[serde(flatten)]
    pub workspace: WorkflowSourceWorkspace,
    pub source_sha: Option<String>,
}

/// One task of a proposed plan (plan v2).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunPlanTaskInput {
    pub id: String,
    pub title: String,
    pub spec: String,
    pub stage_id: String,
    #[serde(default)]
    pub role_id: Option<String>,
    #[serde(default)]
    pub depends_on: Vec<String>,
    #[serde(default)]
    pub inputs: Option<Value>,
    #[serde(default)]
    pub corrects_task_id: Option<String>,
}

/// One stage of a shared run's plan. Isolated runs take their stages from
/// the frozen recipe.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunPlanStageInput {
    pub id: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub profile: Option<String>,
    #[serde(default)]
    pub fallbacks: Vec<String>,
    #[serde(default)]
    pub gate: bool,
}

/// What a coordinator submits with `orchestration.planPropose` (plan v2).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunPlanInput {
    #[serde(default)]
    pub request_id: Option<String>,
    #[serde(default)]
    pub stages: Vec<RunPlanStageInput>,
    #[serde(default)]
    pub tasks: Vec<RunPlanTaskInput>,
    #[serde(default)]
    pub stall_policy: Option<String>,
    #[serde(default)]
    pub max_concurrent: Option<u32>,
}

/// The stored plan of a shared run (snapshot version 2).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SharedRunPlanSnapshot {
    pub version: u32,
    pub objective: String,
    pub stages: Vec<RunPlanStageInput>,
    pub tasks: Vec<RunPlanTaskInput>,
    pub stall_policy: String,
    pub max_concurrent: u32,
    pub digest: String,
}

impl SharedRunPlanSnapshot {
    pub fn content_digest(&self) -> Result<String> {
        let mut value = serde_json::to_value(self)?;
        value
            .as_object_mut()
            .expect("snapshot is an object")
            .remove("digest");
        workflow_digest(&value)
    }
}

/// Who acted on a run. Derived from the connection, never from a payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunActor {
    pub kind: super::RunActorKind,
    pub id: Option<String>,
}

impl RunActor {
    pub fn runtime() -> Self {
        Self {
            kind: super::RunActorKind::Runtime,
            id: None,
        }
    }

    pub fn new(kind: super::RunActorKind, id: Option<String>) -> Self {
        Self { kind, id }
    }

    /// `desktop`, `cli`, `mobile:<device>` or `mcp:<client>`.
    pub fn label(&self) -> String {
        match &self.id {
            Some(id) => format!("{}:{id}", self.kind.as_str()),
            None => self.kind.as_str().to_string(),
        }
    }
}
