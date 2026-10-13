use serde::{Deserialize, Serialize};

// Orchestration rows serialize with snake_case field and enum values on
// purpose: the CLI JSON output mirrors Orca's orchestration payload shapes so
// agent-facing skills and docs stay portable between the two systems.

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum OrchestrationMessageType {
    #[default]
    Status,
    Dispatch,
    MergeReady,
    Escalation,
    Handoff,
    DecisionGate,
    /// A question to an agent, from an inbox (`ext:`) or from `ask`. The
    /// recipient answers it with `reply`.
    Question,
}

impl OrchestrationMessageType {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationMessageType::Status => "status",
            OrchestrationMessageType::Dispatch => "dispatch",
            OrchestrationMessageType::MergeReady => "merge_ready",
            OrchestrationMessageType::Escalation => "escalation",
            OrchestrationMessageType::Handoff => "handoff",
            OrchestrationMessageType::DecisionGate => "decision_gate",
            OrchestrationMessageType::Question => "question",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "status" => Some(OrchestrationMessageType::Status),
            "dispatch" => Some(OrchestrationMessageType::Dispatch),
            "merge_ready" => Some(OrchestrationMessageType::MergeReady),
            "escalation" => Some(OrchestrationMessageType::Escalation),
            "handoff" => Some(OrchestrationMessageType::Handoff),
            "decision_gate" => Some(OrchestrationMessageType::DecisionGate),
            "question" => Some(OrchestrationMessageType::Question),
            _ => None,
        }
    }
}

/// When a queued message may be pasted into the recipient's terminal.
/// `TurnEnd` waits until the agent is idle; `Now` may also be pasted while
/// the agent is working when its adapter queues input typed mid-turn.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "camelCase")]
pub enum MessageDelivery {
    Now,
    #[default]
    TurnEnd,
}

impl MessageDelivery {
    /// The stored column value.
    pub fn as_str(self) -> &'static str {
        match self {
            MessageDelivery::Now => "now",
            MessageDelivery::TurnEnd => "turn_end",
        }
    }

    /// Reads the stored value; the wire form `turnEnd` is accepted too.
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "now" => Some(MessageDelivery::Now),
            "turn_end" | "turnEnd" => Some(MessageDelivery::TurnEnd),
            _ => None,
        }
    }
}

/// What recording runtime activity did to a dispatch's lease.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActivityOutcome {
    /// The dispatch is not active, so nothing changed.
    Ignored,
    /// The lease of a dispatched worker was renewed.
    Recorded,
    /// A stalled dispatch showed activity again and is dispatched once more.
    Revived,
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
    /// Superseded before anyone resolved it, such as a plan proposed again.
    Invalidated,
}

impl OrchestrationGateStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationGateStatus::Pending => "pending",
            OrchestrationGateStatus::Resolved => "resolved",
            OrchestrationGateStatus::Timeout => "timeout",
            OrchestrationGateStatus::Invalidated => "invalidated",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(OrchestrationGateStatus::Pending),
            "resolved" => Some(OrchestrationGateStatus::Resolved),
            "timeout" => Some(OrchestrationGateStatus::Timeout),
            "invalidated" => Some(OrchestrationGateStatus::Invalidated),
            _ => None,
        }
    }
}

/// Run lifecycle, schema v3. A cancelled run without `completed_at` is still
/// settling its cancellation and keeps its workspace.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum OrchestrationCoordinatorStatus {
    Planning,
    AwaitingApproval,
    Running,
    Paused,
    Completed,
    Failed,
    Cancelled,
}

impl OrchestrationCoordinatorStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            OrchestrationCoordinatorStatus::Planning => "planning",
            OrchestrationCoordinatorStatus::AwaitingApproval => "awaitingApproval",
            OrchestrationCoordinatorStatus::Running => "running",
            OrchestrationCoordinatorStatus::Paused => "paused",
            OrchestrationCoordinatorStatus::Completed => "completed",
            OrchestrationCoordinatorStatus::Failed => "failed",
            OrchestrationCoordinatorStatus::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "planning" => Some(OrchestrationCoordinatorStatus::Planning),
            "awaitingApproval" => Some(OrchestrationCoordinatorStatus::AwaitingApproval),
            "running" => Some(OrchestrationCoordinatorStatus::Running),
            "paused" => Some(OrchestrationCoordinatorStatus::Paused),
            "completed" => Some(OrchestrationCoordinatorStatus::Completed),
            "failed" => Some(OrchestrationCoordinatorStatus::Failed),
            "cancelled" => Some(OrchestrationCoordinatorStatus::Cancelled),
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reply_to_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub external_meta: Option<serde_json::Value>,
    #[serde(default)]
    pub delivery: MessageDelivery,
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
    /// The execution-policy stage this task belongs to, when its run has one.
    /// Resolves the preferred profile and the fallback list for the task.
    #[serde(default)]
    pub stage_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role_contract: Option<super::RoleContractSnapshot>,
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
    pub run_id: Option<String>,
    pub workspace_id: String,
    pub coordinator_handle: String,
    pub accepted_at: Option<String>,
    pub last_activity_at: Option<String>,
    pub context_token_hash: Option<String>,
    pub terminal_policy: String,
    pub startup_error: Option<String>,
    /// Exact task-worktree commit accepted with a successful workflow result.
    /// Generic orchestration dispatches leave this unset.
    #[serde(default)]
    pub completion_sha: Option<String>,
    /// Which declared profile launched this dispatch, when one was used.
    /// Recorded so fallback selection knows what has already been tried.
    #[serde(default)]
    pub agent_profile: Option<String>,
    #[serde(default)]
    pub agent_quota_group: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OrchestrationDecisionGate {
    pub id: String,
    #[serde(default)]
    pub run_id: Option<String>,
    /// Empty for run-scoped gates (`plan`, `stage`).
    pub task_id: String,
    #[serde(default)]
    pub kind: RunGateKind,
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
    /// The run's stage plan, as JSON. `None` means the run never had one.
    #[serde(default)]
    pub execution_policy: Option<String>,
    /// Whether the plan waits for a person to approve it before scheduling.
    #[serde(default)]
    pub approval_required: bool,
    /// `ask`, `auto-failover` or `wait`.
    #[serde(default)]
    pub stall_policy: String,
    #[serde(default)]
    pub paused_by: Option<String>,
    #[serde(default)]
    pub isolation: String,
    #[serde(default)]
    pub attention_reason: Option<String>,
    #[serde(default)]
    pub plan_revision: Option<i64>,
    #[serde(default)]
    pub control_sequence: i64,
    #[serde(default)]
    pub coordinator_tab_id: Option<String>,
}

impl OrchestrationCoordinatorRun {
    /// Planning, awaiting plan approval, running, paused, or cancelled with
    /// its cancellation still settling: the states that hold the workspace's
    /// single active-run slot.
    pub fn holds_workspace(&self) -> bool {
        matches!(
            self.status,
            OrchestrationCoordinatorStatus::Planning
                | OrchestrationCoordinatorStatus::AwaitingApproval
                | OrchestrationCoordinatorStatus::Running
                | OrchestrationCoordinatorStatus::Paused
        ) || (self.status == OrchestrationCoordinatorStatus::Cancelled
            && self.completed_at.is_none())
    }
}

/// Which decision a `runGates` row asks for.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RunGateKind {
    #[default]
    Decision,
    Stall,
    Plan,
    Stage,
}

impl RunGateKind {
    pub fn as_str(self) -> &'static str {
        match self {
            RunGateKind::Decision => "decision",
            RunGateKind::Stall => "stall",
            RunGateKind::Plan => "plan",
            RunGateKind::Stage => "stage",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "decision" => Some(RunGateKind::Decision),
            "stall" => Some(RunGateKind::Stall),
            "plan" => Some(RunGateKind::Plan),
            "stage" => Some(RunGateKind::Stage),
            _ => None,
        }
    }
}
