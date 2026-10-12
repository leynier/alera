use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
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
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OrchestrationBoardCursor {
    pub created_at: String,
    pub id: String,
    pub revision: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
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
    pub completed_at: Option<String>,
    /// A plan gate is waiting for approval; scheduling is held.
    pub plan_gate_pending: bool,
    pub isolation: String,
    pub approval_required: bool,
    pub plan_revision: Option<i64>,
    pub attention_reason: Option<String>,
    pub coordinator_state: String,
    pub paused_by: Option<String>,
    pub control_sequence: i64,
    /// Kinds of the gates a person can resolve now (`decision`, `stall`,
    /// `plan`, `stage`).
    pub pending_gate_kinds: Vec<String>,
    pub task_count: i64,
    pub completed_count: i64,
    pub running_count: i64,
    pub failed_count: i64,
    pub stalled_count: i64,
    pub blocked_count: i64,
    pub pending_gate_count: i64,
    pub cleanup_attention: bool,
    pub cleanup_applying: bool,
    /// The newest gates a person can resolve now, at most
    /// [`RUN_SUMMARY_PENDING_GATES_MAX`], so a client can open one directly.
    pub pending_gates: Vec<RunPendingGateRef>,
}

pub const RUN_SUMMARY_PENDING_GATES_MAX: i64 = 5;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunPendingGateRef {
    pub id: String,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrchestrationBoardCounts {
    pub attention: i64,
    pub active: i64,
    pub history: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OrchestrationBoardSnapshot {
    pub revision: i64,
    pub counts: OrchestrationBoardCounts,
    pub items: Vec<OrchestrationRunSummary>,
    pub next_cursor: Option<OrchestrationBoardCursor>,
}
