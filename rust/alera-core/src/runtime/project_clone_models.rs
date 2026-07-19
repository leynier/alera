use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProjectCloneJobStatus {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl ProjectCloneJobStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            ProjectCloneJobStatus::Queued => "queued",
            ProjectCloneJobStatus::Running => "running",
            ProjectCloneJobStatus::Completed => "completed",
            ProjectCloneJobStatus::Failed => "failed",
            ProjectCloneJobStatus::Cancelled => "cancelled",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "running" => ProjectCloneJobStatus::Running,
            "completed" => ProjectCloneJobStatus::Completed,
            "failed" => ProjectCloneJobStatus::Failed,
            "cancelled" => ProjectCloneJobStatus::Cancelled,
            _ => ProjectCloneJobStatus::Queued,
        }
    }

    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            ProjectCloneJobStatus::Completed
                | ProjectCloneJobStatus::Failed
                | ProjectCloneJobStatus::Cancelled
        )
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProjectCloneJobPhase {
    Cloning,
    Registering,
}

impl ProjectCloneJobPhase {
    pub fn as_str(self) -> &'static str {
        match self {
            ProjectCloneJobPhase::Cloning => "cloning",
            ProjectCloneJobPhase::Registering => "registering",
        }
    }

    pub fn from_db(value: &str) -> Self {
        match value {
            "registering" => ProjectCloneJobPhase::Registering,
            _ => ProjectCloneJobPhase::Cloning,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectCloneJob {
    pub id: String,
    pub source: String,
    pub parent_path: String,
    pub directory_name: String,
    pub destination_path: String,
    pub project_name: Option<String>,
    pub status: ProjectCloneJobStatus,
    pub phase: ProjectCloneJobPhase,
    pub progress_percent: Option<i64>,
    pub message: Option<String>,
    pub error: Option<String>,
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
}
