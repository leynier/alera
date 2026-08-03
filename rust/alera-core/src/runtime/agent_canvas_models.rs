use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const AGENT_CANVAS_PROTOCOL_VERSION: i64 = 1;
pub const AGENT_CANVAS_GEN_UI_VERSION: i64 = 1;
pub const AGENT_CANVAS_MAX_PER_WORKSPACE: i64 = 20;
pub const AGENT_CANVAS_RETENTION_HOURS: i64 = 24;
pub const AGENT_CANVAS_MAX_DOCUMENT_BYTES: usize = 512 * 1024;
pub const AGENT_CANVAS_MAX_COMPONENTS: usize = 100;
pub const AGENT_CANVAS_MAX_DECISIONS: usize = 20;
pub const AGENT_CANVAS_MAX_EVENTS: i64 = 2000;
pub const AGENT_CANVAS_COMPONENTS: &[&str] = &[
    "AgentRunHeader",
    "TaskProgress",
    "DecisionRequest",
    "ChangeSummary",
    "FileReferenceList",
    "ValidationResults",
    "RiskSummary",
    "ArtifactCard",
    "Notice",
    "ActionGroup",
];

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentCanvasState {
    Waiting,
    Live,
    Completed,
    Orphaned,
    Closed,
}

impl AgentCanvasState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Live => "live",
            Self::Completed => "completed",
            Self::Orphaned => "orphaned",
            Self::Closed => "closed",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "waiting" => Some(Self::Waiting),
            "live" => Some(Self::Live),
            "completed" => Some(Self::Completed),
            "orphaned" => Some(Self::Orphaned),
            "closed" => Some(Self::Closed),
            _ => None,
        }
    }

    pub fn is_history(self) -> bool {
        matches!(self, Self::Completed | Self::Orphaned | Self::Closed)
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentCanvasDecisionState {
    Pending,
    Resolved,
    Timeout,
}

impl AgentCanvasDecisionState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Resolved => "resolved",
            Self::Timeout => "timeout",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(Self::Pending),
            "resolved" => Some(Self::Resolved),
            "timeout" => Some(Self::Timeout),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentCanvasDecision {
    pub id: String,
    pub canvas_id: String,
    pub revision: i64,
    pub question: String,
    pub options: Value,
    pub state: AgentCanvasDecisionState,
    pub resolution: Option<Value>,
    pub created_at: String,
    pub resolved_at: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentCanvas {
    pub id: String,
    pub workspace_id: String,
    pub terminal_session_id: String,
    pub tab_id: Option<String>,
    pub agent_type: String,
    pub title: String,
    pub state: AgentCanvasState,
    pub pinned: bool,
    pub frozen: bool,
    pub revision: i64,
    pub final_revision: Option<i64>,
    pub document: Value,
    pub decisions: Vec<AgentCanvasDecision>,
    pub created_at: String,
    pub updated_at: String,
    pub completed_at: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentCanvasEvent {
    pub sequence: i64,
    pub canvas_id: String,
    pub workspace_id: String,
    pub event_type: String,
    pub payload: Value,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentCanvasCapabilities {
    pub protocol_version: i64,
    pub gen_ui_version: i64,
    pub max_canvases_per_workspace: i64,
    pub retention_hours: i64,
    pub max_document_bytes: usize,
    pub max_components: usize,
    pub max_decisions: usize,
    pub max_events: i64,
    pub supported_components: Vec<String>,
    pub supported_immediate_actions: Vec<String>,
    pub supported_controlled_actions: Vec<String>,
    pub supported_destructive_actions: Vec<String>,
}

impl Default for AgentCanvasCapabilities {
    fn default() -> Self {
        Self {
            protocol_version: AGENT_CANVAS_PROTOCOL_VERSION,
            gen_ui_version: AGENT_CANVAS_GEN_UI_VERSION,
            max_canvases_per_workspace: AGENT_CANVAS_MAX_PER_WORKSPACE,
            retention_hours: AGENT_CANVAS_RETENTION_HOURS,
            max_document_bytes: AGENT_CANVAS_MAX_DOCUMENT_BYTES,
            max_components: AGENT_CANVAS_MAX_COMPONENTS,
            max_decisions: AGENT_CANVAS_MAX_DECISIONS,
            max_events: AGENT_CANVAS_MAX_EVENTS,
            supported_components: AGENT_CANVAS_COMPONENTS
                .iter()
                .map(|value| (*value).to_string())
                .collect(),
            supported_immediate_actions: vec![
                "openFile",
                "openDiff",
                "openSearch",
                "focusTerminal",
                "openPullRequest",
                "openArtifact",
                "copyText",
                "switchContextPanel",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
            supported_controlled_actions: vec![
                "resolveDecision",
                "approveExecutionPlan",
                "rejectExecutionPlan",
                "editPullRequestComment",
                "rerunValidation",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
            supported_destructive_actions: vec![
                "stage",
                "unstage",
                "discard",
                "commit",
                "pull",
                "push",
                "mergePullRequest",
                "terminateTerminal",
                "deleteArtifact",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
        }
    }
}
