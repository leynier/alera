use serde::{Deserialize, Serialize};

use super::{Workspace, WorktreeSetupReport};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrepareWorkflowWorkspace {
    pub request_id: String,
    pub run_id: String,
    pub revision: i64,
    pub task_id: Option<String>,
    pub retry_of: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowWorkspaceIdentity {
    pub workspace: Workspace,
    pub repo_path: String,
    pub owner_workspace_id: String,
    pub run_id: String,
    pub revision: i64,
    pub task_id: Option<String>,
    pub attempt: i64,
    pub base_sha: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowWorkspacePhase {
    Reserved,
    Creating,
    Created,
    SetupRunning,
    Ready,
    Attention,
}

impl WorkflowWorkspacePhase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Reserved => "reserved",
            Self::Creating => "creating",
            Self::Created => "created",
            Self::SetupRunning => "setupRunning",
            Self::Ready => "ready",
            Self::Attention => "attention",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowWorkspaceRecord {
    pub identity: WorkflowWorkspaceIdentity,
    pub phase: WorkflowWorkspacePhase,
    pub setup_report: Option<WorktreeSetupReport>,
    pub error: Option<String>,
    pub dispatch_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowWorkspaceQuery {
    pub run_id: String,
    pub before_row: Option<i64>,
    pub limit: Option<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowWorkspacePage {
    pub items: Vec<WorkflowWorkspaceRecord>,
    pub next_before_row: Option<i64>,
}
