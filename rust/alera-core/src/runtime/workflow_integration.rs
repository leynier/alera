use serde::{Deserialize, Serialize};

use crate::git::{WorkflowIntegrationReceipt, WorkflowIntegrationRequest};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct IntegrateWorkflowResult {
    pub request_id: String,
    pub run_id: String,
    pub revision: i64,
    pub task_id: String,
    pub workspace_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowIntegrationState {
    Pending,
    Prepared,
    Integrated,
    Conflict,
    Attention,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowIntegrationRecord {
    pub request: WorkflowIntegrationRequest,
    pub state: WorkflowIntegrationState,
    pub receipt: Option<WorkflowIntegrationReceipt>,
    pub conflict_paths: Vec<String>,
    pub conflicts_truncated: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowIntegrationQuery {
    pub run_id: String,
    pub after_row: Option<i64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowIntegrationSummary {
    pub id: String,
    pub task_id: String,
    pub workspace_id: String,
    pub state: WorkflowIntegrationState,
    pub expected_sha: String,
    pub integrated_sha: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowIntegrationPage {
    pub items: Vec<WorkflowIntegrationSummary>,
    pub next_after_row: Option<i64>,
}
