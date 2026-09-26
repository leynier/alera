use serde::{Deserialize, Serialize};

use super::{AgentProfile, FrozenWorkflowTask, WorkflowWorkspaceIdentity};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LaunchWorkflowTask {
    pub request_id: String,
    pub run_id: String,
    pub revision: i64,
    pub task_id: String,
    pub workspace_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowLaunchStatus {
    Reserved,
    Starting,
    Started,
    Attention,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowLaunchQuery {
    pub run_id: String,
    pub after_row: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowLaunchPage {
    pub items: Vec<WorkflowLaunchRecord>,
    pub next_after_row: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowLaunchRecord {
    pub id: String,
    pub request: LaunchWorkflowTask,
    pub terminal_handle: String,
    pub dispatch_id: String,
    pub base_sha: String,
    pub profile_id: String,
    pub profile_revision: i64,
    pub status: WorkflowLaunchStatus,
    pub error: Option<String>,
}

/// Private launch configuration is never part of the public launch receipt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowLaunchInputs {
    pub workspace: WorkflowWorkspaceIdentity,
    pub task: FrozenWorkflowTask,
    pub profile: AgentProfile,
    pub plan_digest: String,
}
