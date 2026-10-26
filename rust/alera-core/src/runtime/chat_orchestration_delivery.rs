use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::chat_orchestration_models::{ChatOrchestrationTask, ChatOrchestrationTaskStatus};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatOrchestrationWakeStatus {
    /// Open cohort: concurrent completions merge into it.
    Pending,
    /// Closed for merging and being delivered; redelivered after a restart.
    Sealed,
    /// The parent chat accepted the queued message.
    Delivered,
}

impl ChatOrchestrationWakeStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Sealed => "sealed",
            Self::Delivered => "delivered",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        [Self::Pending, Self::Sealed, Self::Delivered]
            .into_iter()
            .find(|status| status.as_str() == value)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatOrchestrationWakeEntry {
    pub task_id: String,
    pub task_status: ChatOrchestrationTaskStatus,
    pub task_revision: i64,
}

/// A durable parent wake. `client_message_id` is stable for the cohort, so
/// redelivering a sealed wake after a crash queues the same message once.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatOrchestrationWake {
    pub parent_chat_id: String,
    pub generation: i64,
    pub client_message_id: String,
    pub status: ChatOrchestrationWakeStatus,
    pub entries: Vec<ChatOrchestrationWakeEntry>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub sealed_at: Option<DateTime<Utc>>,
    pub delivered_at: Option<DateTime<Utc>>,
}

/// Receipt identity `(scope, verb, requestId)` plus the canonical payload
/// digest and the response a replay returns.
#[derive(Debug, Clone, PartialEq)]
pub struct ChatOrchestrationReceipt {
    pub scope: String,
    pub verb: String,
    pub request_id: String,
    pub digest: String,
    pub response: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatOrchestrationReceiptCheck {
    New,
    Replay(Value),
    Conflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatOrchestrationCreateOutcome {
    Created(Box<ChatOrchestrationTask>),
    Replay(Value),
    Conflict,
}

/// An issued MCP credential. The secret itself is never stored, only its
/// hash, and this record deliberately carries neither.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatOrchestrationCredential {
    pub chat_id: String,
    pub generation: i64,
    pub issued_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub revoke_reason: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ChatOrchestrationRecovery {
    /// Tasks settled from the chat store or marked interrupted/cancelled.
    pub settled: Vec<ChatOrchestrationTask>,
    /// Non-terminal tasks whose child runs on another host; the hub
    /// reconciles them over the host link.
    pub remote: Vec<ChatOrchestrationTask>,
    /// Pending and sealed wakes to (re)deliver once their parent is idle.
    pub wakes: Vec<ChatOrchestrationWake>,
    pub revoked_credentials: u64,
}

/// A child chat's turn as the chat store recorded it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatOrchestrationChildTurn {
    /// `running`, `completed`, `failed`, `interrupted`, `cancelled`; `None`
    /// when the chat has no turn with that id.
    pub turn_status: Option<String>,
    /// Text of the turn's last assistant message, untruncated.
    pub final_assistant_text: Option<String>,
}
