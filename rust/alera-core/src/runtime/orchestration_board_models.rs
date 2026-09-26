use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OrchestrationBoardQuery {
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    pub search: Option<String>,
    pub bucket: Option<OrchestrationBoardBucket>,
    pub cursor: Option<OrchestrationBoardCursor>,
    pub limit: Option<u32>,
}

impl OrchestrationBoardQuery {
    pub(super) fn validate(&self) -> Result<i64> {
        for value in [&self.project_id, &self.workspace_id, &self.search]
            .into_iter()
            .flatten()
        {
            if value.len() > 256 {
                bail!("board filter exceeds 256 bytes");
            }
        }
        if let Some(cursor) = &self.cursor {
            if cursor.id.len() > 256 || cursor.created_at.len() > 64 || cursor.revision < 0 {
                bail!("invalid board cursor");
            }
        }
        let limit = self.limit.unwrap_or(50);
        if !(1..=100).contains(&limit) {
            bail!("board page size must be between 1 and 100");
        }
        Ok(i64::from(limit))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationBoardBucket {
    Attention,
    Active,
    History,
}

impl OrchestrationBoardBucket {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            Self::Attention => "attention",
            Self::Active => "active",
            Self::History => "history",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OrchestrationBoardCursor {
    pub created_at: String,
    pub id: String,
    pub revision: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrchestrationRunSummary {
    pub id: String,
    pub objective: String,
    pub status: String,
    pub bucket: OrchestrationBoardBucket,
    pub workspace_id: String,
    pub workspace_name: Option<String>,
    pub project_id: Option<String>,
    pub project_name: Option<String>,
    pub created_at: String,
    pub last_activity_at: String,
    pub policy_status: String,
    pub task_count: i64,
    pub completed_count: i64,
    pub running_count: i64,
    pub failed_count: i64,
    pub stalled_count: i64,
    pub blocked_count: i64,
    pub pending_gate_count: i64,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct OrchestrationBoardCounts {
    pub attention: i64,
    pub active: i64,
    pub history: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct OrchestrationBoardSnapshot {
    pub revision: i64,
    pub counts: OrchestrationBoardCounts,
    pub items: Vec<OrchestrationRunSummary>,
    pub next_cursor: Option<OrchestrationBoardCursor>,
}
