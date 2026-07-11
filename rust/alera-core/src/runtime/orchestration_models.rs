use serde::{Deserialize, Serialize};

// Orchestration rows serialize with snake_case field and enum values on
// purpose: the CLI JSON output mirrors Orca's orchestration payload shapes so
// agent-facing skills and docs stay portable between the two systems.

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationMessageType {
    Status,
    Dispatch,
    WorkerDone,
    MergeReady,
    Escalation,
    Handoff,
    DecisionGate,
    Heartbeat,
}

impl OrchestrationMessageType {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationMessageType::Status => "status",
            OrchestrationMessageType::Dispatch => "dispatch",
            OrchestrationMessageType::WorkerDone => "worker_done",
            OrchestrationMessageType::MergeReady => "merge_ready",
            OrchestrationMessageType::Escalation => "escalation",
            OrchestrationMessageType::Handoff => "handoff",
            OrchestrationMessageType::DecisionGate => "decision_gate",
            OrchestrationMessageType::Heartbeat => "heartbeat",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "status" => Some(OrchestrationMessageType::Status),
            "dispatch" => Some(OrchestrationMessageType::Dispatch),
            "worker_done" => Some(OrchestrationMessageType::WorkerDone),
            "merge_ready" => Some(OrchestrationMessageType::MergeReady),
            "escalation" => Some(OrchestrationMessageType::Escalation),
            "handoff" => Some(OrchestrationMessageType::Handoff),
            "decision_gate" => Some(OrchestrationMessageType::DecisionGate),
            "heartbeat" => Some(OrchestrationMessageType::Heartbeat),
            _ => None,
        }
    }

    pub fn is_lifecycle(self) -> bool {
        matches!(
            self,
            OrchestrationMessageType::WorkerDone | OrchestrationMessageType::Heartbeat
        )
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationMessagePriority {
    #[default]
    Normal,
    High,
    Urgent,
}

impl OrchestrationMessagePriority {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationMessagePriority::Normal => "normal",
            OrchestrationMessagePriority::High => "high",
            OrchestrationMessagePriority::Urgent => "urgent",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "normal" => Some(OrchestrationMessagePriority::Normal),
            "high" => Some(OrchestrationMessagePriority::High),
            "urgent" => Some(OrchestrationMessagePriority::Urgent),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationTaskStatus {
    Pending,
    Ready,
    Dispatched,
    Completed,
    Failed,
    Blocked,
    Stalled,
    Cancelled,
}

impl OrchestrationTaskStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationTaskStatus::Pending => "pending",
            OrchestrationTaskStatus::Ready => "ready",
            OrchestrationTaskStatus::Dispatched => "dispatched",
            OrchestrationTaskStatus::Completed => "completed",
            OrchestrationTaskStatus::Failed => "failed",
            OrchestrationTaskStatus::Blocked => "blocked",
            OrchestrationTaskStatus::Stalled => "stalled",
            OrchestrationTaskStatus::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(OrchestrationTaskStatus::Pending),
            "ready" => Some(OrchestrationTaskStatus::Ready),
            "dispatched" => Some(OrchestrationTaskStatus::Dispatched),
            "completed" => Some(OrchestrationTaskStatus::Completed),
            "failed" => Some(OrchestrationTaskStatus::Failed),
            "blocked" => Some(OrchestrationTaskStatus::Blocked),
            "stalled" => Some(OrchestrationTaskStatus::Stalled),
            "cancelled" => Some(OrchestrationTaskStatus::Cancelled),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationDispatchStatus {
    Pending,
    Dispatched,
    Completed,
    Failed,
    CircuitBroken,
    AwaitingAcceptance,
    StartupFailed,
    Stalled,
    Cancelled,
    Superseded,
}

impl OrchestrationDispatchStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationDispatchStatus::Pending => "pending",
            OrchestrationDispatchStatus::Dispatched => "dispatched",
            OrchestrationDispatchStatus::Completed => "completed",
            OrchestrationDispatchStatus::Failed => "failed",
            OrchestrationDispatchStatus::CircuitBroken => "circuit_broken",
            OrchestrationDispatchStatus::AwaitingAcceptance => "awaiting_acceptance",
            OrchestrationDispatchStatus::StartupFailed => "startup_failed",
            OrchestrationDispatchStatus::Stalled => "stalled",
            OrchestrationDispatchStatus::Cancelled => "cancelled",
            OrchestrationDispatchStatus::Superseded => "superseded",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(OrchestrationDispatchStatus::Pending),
            "dispatched" => Some(OrchestrationDispatchStatus::Dispatched),
            "completed" => Some(OrchestrationDispatchStatus::Completed),
            "failed" => Some(OrchestrationDispatchStatus::Failed),
            "circuit_broken" => Some(OrchestrationDispatchStatus::CircuitBroken),
            "awaiting_acceptance" => Some(OrchestrationDispatchStatus::AwaitingAcceptance),
            "startup_failed" => Some(OrchestrationDispatchStatus::StartupFailed),
            "stalled" => Some(OrchestrationDispatchStatus::Stalled),
            "cancelled" => Some(OrchestrationDispatchStatus::Cancelled),
            "superseded" => Some(OrchestrationDispatchStatus::Superseded),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationGateStatus {
    Pending,
    Resolved,
    Timeout,
}

impl OrchestrationGateStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationGateStatus::Pending => "pending",
            OrchestrationGateStatus::Resolved => "resolved",
            OrchestrationGateStatus::Timeout => "timeout",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(OrchestrationGateStatus::Pending),
            "resolved" => Some(OrchestrationGateStatus::Resolved),
            "timeout" => Some(OrchestrationGateStatus::Timeout),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationCoordinatorStatus {
    Idle,
    Running,
    Completed,
    Failed,
    Stopping,
    Stopped,
}

impl OrchestrationCoordinatorStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationCoordinatorStatus::Idle => "idle",
            OrchestrationCoordinatorStatus::Running => "running",
            OrchestrationCoordinatorStatus::Completed => "completed",
            OrchestrationCoordinatorStatus::Failed => "failed",
            OrchestrationCoordinatorStatus::Stopping => "stopping",
            OrchestrationCoordinatorStatus::Stopped => "stopped",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "idle" => Some(OrchestrationCoordinatorStatus::Idle),
            "running" => Some(OrchestrationCoordinatorStatus::Running),
            "completed" => Some(OrchestrationCoordinatorStatus::Completed),
            "failed" => Some(OrchestrationCoordinatorStatus::Failed),
            "stopping" => Some(OrchestrationCoordinatorStatus::Stopping),
            "stopped" => Some(OrchestrationCoordinatorStatus::Stopped),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationMessage {
    pub id: String,
    pub from_handle: String,
    pub to_handle: String,
    pub subject: String,
    pub body: String,
    #[serde(rename = "type")]
    pub message_type: OrchestrationMessageType,
    pub priority: OrchestrationMessagePriority,
    pub thread_id: Option<String>,
    pub payload: Option<String>,
    pub read: bool,
    pub sequence: i64,
    pub created_at: String,
    pub delivered_at: Option<String>,
    pub run_id: Option<String>,
    pub workspace_id: Option<String>,
    pub task_id: Option<String>,
    pub dispatch_id: Option<String>,
    pub state: String,
    pub expires_at: Option<String>,
    pub obsolete_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationTask {
    pub id: String,
    pub parent_id: Option<String>,
    pub created_by_terminal_handle: Option<String>,
    pub task_title: Option<String>,
    pub display_name: Option<String>,
    pub spec: String,
    pub status: OrchestrationTaskStatus,
    pub deps: Vec<String>,
    pub result: Option<String>,
    pub created_at: String,
    pub completed_at: Option<String>,
    pub run_id: Option<String>,
    pub workspace_id: String,
    pub coordinator_handle: String,
    pub result_schema: Option<String>,
    pub startup_failure_count: i64,
    pub cancelled_at: Option<String>,
    pub stalled_at: Option<String>,
    /// Populated by list-with-dispatch queries: the active dispatch, if any.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assignee_handle: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dispatch_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationDispatchContext {
    pub id: String,
    pub task_id: String,
    pub assignee_handle: Option<String>,
    pub status: OrchestrationDispatchStatus,
    pub failure_count: i64,
    pub last_failure: Option<String>,
    pub dispatched_at: Option<String>,
    pub completed_at: Option<String>,
    pub created_at: String,
    pub last_heartbeat_at: Option<String>,
    pub run_id: Option<String>,
    pub workspace_id: String,
    pub coordinator_handle: String,
    pub accepted_at: Option<String>,
    pub last_activity_at: Option<String>,
    pub context_token_hash: Option<String>,
    pub completion_policy: String,
    pub terminal_policy: String,
    pub startup_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationDecisionGate {
    pub id: String,
    pub task_id: String,
    pub question: String,
    pub options: Vec<String>,
    pub status: OrchestrationGateStatus,
    pub resolution: Option<String>,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationCoordinatorRun {
    pub id: String,
    pub spec: String,
    pub status: OrchestrationCoordinatorStatus,
    pub coordinator_handle: Option<String>,
    pub poll_interval_ms: i64,
    pub created_at: String,
    pub completed_at: Option<String>,
    pub workspace_id: String,
    pub max_concurrent: i64,
    pub last_activity_at: String,
    pub stop_reason: Option<String>,
}
