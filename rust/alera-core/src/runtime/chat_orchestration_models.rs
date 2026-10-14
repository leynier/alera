//! Durable records for orchestration between agent chats. They live in their
//! own `chatOrchestration*` tables, apart from terminal orchestration, and hold
//! no foreign key to chats or workspaces: a task outlives a deleted workspace
//! or chat so its lineage and result stay readable.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use super::chat_orchestration_delivery::ChatOrchestrationWake;

pub const CHAT_ORCHESTRATION_SCHEMA_VERSION_KEY: &str = "chatOrchestration.schemaVersion";
pub const CHAT_ORCHESTRATION_SCHEMA_VERSION: i64 = 1;
/// Final assistant text kept on a task; the parent reads the chat for more.
pub const CHAT_ORCHESTRATION_RESULT_MAX_BYTES: usize = 64 * 1024;
pub const CHAT_ORCHESTRATION_BRIEF_MAX_BYTES: usize = 256 * 1024;
pub const CHAT_ORCHESTRATION_ERROR_MAX_BYTES: usize = 4 * 1024;
pub const CHAT_ORCHESTRATION_LABEL_MAX_BYTES: usize = 512;
pub const CHAT_ORCHESTRATION_ID_MAX_BYTES: usize = 256;
pub const CHAT_ORCHESTRATION_OPTIONS_MAX_BYTES: usize = 64 * 1024;
pub const CHAT_ORCHESTRATION_RECEIPT_MAX_BYTES: usize = 256 * 1024;
pub const CHAT_ORCHESTRATION_RECEIPT_RETENTION_DAYS: i64 = 7;
pub const CHAT_ORCHESTRATION_REVOKED_CREDENTIAL_RETENTION_DAYS: i64 = 30;
pub const CHAT_ORCHESTRATION_LIST_MAX_LIMIT: i64 = 500;
/// Error recorded on work a runtime restart cut short.
pub const CHAT_ORCHESTRATION_INTERRUPT_RUNTIME_RESTARTED: &str = "runtimeRestarted";
pub const CHAT_ORCHESTRATION_INTERRUPT_CHILD_CHAT_MISSING: &str = "childChatMissing";

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ChatOrchestrationStoreError {
    #[error("Chat orchestration task not found: {0}")]
    NotFound(String),
    #[error("Invalid chat orchestration request: {0}")]
    Invalid(String),
    #[error("Chat orchestration conflict: {0}")]
    Conflict(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationTaskStatus {
    Preparing,
    Running,
    NeedsInput,
    Completed,
    Failed,
    Interrupted,
    CancelRequested,
    Cancelled,
}

impl ChatOrchestrationTaskStatus {
    pub const ALL: [Self; 8] = [
        Self::Preparing,
        Self::Running,
        Self::NeedsInput,
        Self::Completed,
        Self::Failed,
        Self::Interrupted,
        Self::CancelRequested,
        Self::Cancelled,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Running => "running",
            Self::NeedsInput => "needs_input",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Interrupted => "interrupted",
            Self::CancelRequested => "cancel_requested",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|status| status.as_str() == value)
    }

    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Completed | Self::Failed | Self::Interrupted | Self::Cancelled
        )
    }

    /// Statuses a task may move to `self` from. Terminal statuses are final,
    /// and only a cancellation request leads into `cancel_requested`, so a
    /// late child event can still settle a task whose cancel lost the race.
    pub fn legal_predecessors(self) -> &'static [Self] {
        match self {
            Self::Preparing => &[],
            Self::Running => &[Self::Preparing, Self::NeedsInput],
            Self::NeedsInput => &[Self::Running],
            Self::Completed | Self::Failed | Self::Interrupted => &[
                Self::Preparing,
                Self::Running,
                Self::NeedsInput,
                Self::CancelRequested,
            ],
            Self::CancelRequested => &[Self::Preparing, Self::Running, Self::NeedsInput],
            Self::Cancelled => &[
                Self::Preparing,
                Self::Running,
                Self::NeedsInput,
                Self::CancelRequested,
            ],
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationTaskKind {
    /// `delegate`: a brief handed to an existing or new child chat.
    Delegate,
    /// `send` with `expectReply`: completes with the recipient's reply.
    Message,
    /// Further work handed to a child chat an earlier task created.
    Followup,
}

impl ChatOrchestrationTaskKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Delegate => "delegate",
            Self::Message => "message",
            Self::Followup => "followup",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        [Self::Delegate, Self::Message, Self::Followup]
            .into_iter()
            .find(|kind| kind.as_str() == value)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationNotify {
    /// Wake the parent on settlement and when the child needs input.
    Always,
    SettledOnly,
    Never,
}

impl ChatOrchestrationNotify {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Always => "always",
            Self::SettledOnly => "settled_only",
            Self::Never => "never",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        [Self::Always, Self::SettledOnly, Self::Never]
            .into_iter()
            .find(|notify| notify.as_str() == value)
    }

    /// Whether moving into `status` owes the parent a wake.
    pub fn wakes_on(self, status: ChatOrchestrationTaskStatus) -> bool {
        match self {
            Self::Never => false,
            Self::SettledOnly => status.is_terminal(),
            Self::Always => {
                status.is_terminal() || status == ChatOrchestrationTaskStatus::NeedsInput
            }
        }
    }
}

/// How far the parent has received a task's result.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationResultDelivery {
    Pending,
    /// A wake naming the settled task reached the parent chat.
    Notified,
    /// The parent read it with `ack`, or a bounded wait returned it inline.
    Acknowledged,
}

impl ChatOrchestrationResultDelivery {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Notified => "notified",
            Self::Acknowledged => "acknowledged",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        [Self::Pending, Self::Notified, Self::Acknowledged]
            .into_iter()
            .find(|delivery| delivery.as_str() == value)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationWorkspaceMode {
    Worktree,
    Shared,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationSetupMode {
    #[default]
    Inline,
    Deferred,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatOrchestrationNewWorkspace {
    pub project_id: String,
    pub host_id: String,
    pub mode: ChatOrchestrationWorkspaceMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reuse_existing_branch: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_workspace_id: Option<String>,
    #[serde(default)]
    pub setup: ChatOrchestrationSetupMode,
}

/// Exactly one of `{chat}`, `{workspace}` or `{newWorkspace}` on the wire.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChatOrchestrationTarget {
    #[serde(rename_all = "camelCase")]
    Chat {
        chat_id: String,
    },
    #[serde(rename_all = "camelCase")]
    Workspace {
        workspace_id: String,
    },
    NewWorkspace(ChatOrchestrationNewWorkspace),
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatOrchestrationTask {
    pub task_id: String,
    /// Insertion order; `before_sequence` pages listings with it.
    pub sequence: i64,
    pub kind: ChatOrchestrationTaskKind,
    pub status: ChatOrchestrationTaskStatus,
    /// Grows on every status change, for compare-and-set updates. Result
    /// delivery bookkeeping does not move it.
    pub revision: i64,
    /// Authenticated scope that created it (`chat:<id>`, `desktop`, ...).
    pub caller_scope: String,
    pub parent_task_id: Option<String>,
    pub root_task_id: String,
    pub depth: i64,
    pub parent_chat_id: Option<String>,
    /// The chat at the top of the lineage (the root task's parent chat).
    pub root_chat_id: Option<String>,
    pub child_chat_id: Option<String>,
    pub child_turn_id: Option<String>,
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    /// `None` or `local` when the child runs on this runtime.
    pub host_id: Option<String>,
    pub target: ChatOrchestrationTarget,
    pub title: Option<String>,
    pub role: Option<String>,
    pub brief: String,
    pub notify: ChatOrchestrationNotify,
    /// Launch choices (`agent`, `runtimeMode`, `interactionMode`) as sent.
    pub launch_options: Option<Value>,
    pub result_text: Option<String>,
    pub result_truncated: bool,
    pub result_delivery: ChatOrchestrationResultDelivery,
    /// Stable code for `error` (`runtimeRestarted`, `childChatMissing`, ...).
    pub error_code: Option<String>,
    pub error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub cancel_requested_at: Option<DateTime<Utc>>,
    pub settled_at: Option<DateTime<Utc>>,
}

impl ChatOrchestrationTask {
    /// Needs a person or the parent: waiting for input, or failed with a
    /// result nobody has acknowledged.
    pub fn needs_attention(&self) -> bool {
        self.status == ChatOrchestrationTaskStatus::NeedsInput
            || (self.status == ChatOrchestrationTaskStatus::Failed
                && self.result_delivery != ChatOrchestrationResultDelivery::Acknowledged)
    }

    /// Payload of `chatOrchestrationChanged` for this task.
    pub fn change(&self) -> ChatOrchestrationChange {
        ChatOrchestrationChange {
            task_id: self.task_id.clone(),
            parent_chat_id: self.parent_chat_id.clone(),
            child_chat_id: self.child_chat_id.clone(),
            workspace_id: self.workspace_id.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatOrchestrationChange {
    pub task_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_chat_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub child_chat_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NewChatOrchestrationTask {
    /// Caller-minted (`new_chat_orchestration_task_id`) so a receipt can name
    /// it before the insert commits.
    pub task_id: String,
    pub kind: ChatOrchestrationTaskKind,
    pub caller_scope: String,
    pub parent_task_id: Option<String>,
    pub parent_chat_id: Option<String>,
    pub child_chat_id: Option<String>,
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    pub host_id: Option<String>,
    pub target: ChatOrchestrationTarget,
    pub title: Option<String>,
    pub role: Option<String>,
    pub brief: String,
    pub notify: ChatOrchestrationNotify,
    pub launch_options: Option<Value>,
}

/// A conditional status change. It applies only while the task is in one of
/// `from` (and at `expected_revision` when given) and the move is legal.
#[derive(Debug, Clone, PartialEq)]
pub struct ChatOrchestrationTaskTransition {
    pub to: ChatOrchestrationTaskStatus,
    pub from: Vec<ChatOrchestrationTaskStatus>,
    pub expected_revision: Option<i64>,
    /// Set fields overwrite; `None` keeps the stored value.
    pub child_chat_id: Option<String>,
    pub child_turn_id: Option<String>,
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    pub host_id: Option<String>,
    /// Final assistant text; truncated to `CHAT_ORCHESTRATION_RESULT_MAX_BYTES`.
    pub result_text: Option<String>,
    pub error_code: Option<String>,
    pub error: Option<String>,
}

impl ChatOrchestrationTaskTransition {
    pub fn new(
        from: impl Into<Vec<ChatOrchestrationTaskStatus>>,
        to: ChatOrchestrationTaskStatus,
    ) -> Self {
        Self {
            to,
            from: from.into(),
            expected_revision: None,
            child_chat_id: None,
            child_turn_id: None,
            project_id: None,
            workspace_id: None,
            host_id: None,
            result_text: None,
            error_code: None,
            error: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatOrchestrationTransitionOutcome {
    /// Committed; `wake` is the parent cohort it joined, if any.
    Applied {
        task: ChatOrchestrationTask,
        wake: Option<ChatOrchestrationWake>,
    },
    /// The task was not in an expected state; `current` is what is stored.
    Rejected { current: ChatOrchestrationTask },
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatOrchestrationCancelOutcome {
    pub task: ChatOrchestrationTask,
    /// Tasks (the target first, then descendants) moved to `cancel_requested`
    /// by this call; empty when everything had already settled or was asked.
    pub requested: Vec<ChatOrchestrationTask>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ChatOrchestrationTaskFilter {
    pub parent_chat_id: Option<String>,
    pub root_chat_id: Option<String>,
    pub child_chat_id: Option<String>,
    pub project_id: Option<String>,
    pub workspace_id: Option<String>,
    pub host_id: Option<String>,
    pub parent_task_id: Option<String>,
    pub root_task_id: Option<String>,
    pub caller_scope: Option<String>,
    /// Empty means every status.
    pub statuses: Vec<ChatOrchestrationTaskStatus>,
    /// Filters on `ChatOrchestrationTask::needs_attention`.
    pub attention: Option<bool>,
    pub before_sequence: Option<i64>,
    /// Clamped to `CHAT_ORCHESTRATION_LIST_MAX_LIMIT`; `None` uses it.
    pub limit: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatOrchestrationTaskPage {
    pub tasks: Vec<ChatOrchestrationTask>,
    /// Pass as `before_sequence` for the next page.
    pub next_before_sequence: Option<i64>,
}
