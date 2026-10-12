use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{MessageDelivery, OrchestrationMessage, OrchestrationMessagePriority};

/// Addresses that belong to no terminal. Questions from them are the inbox.
pub const EXTERNAL_INBOX_PREFIX: &str = "ext:";
pub const INBOX_PENDING_LIMIT: i64 = 100;
pub const INBOX_DEFAULT_EXPIRY_SECONDS: i64 = 5 * 60 * 60;
pub const INBOX_MIN_EXPIRY_SECONDS: i64 = 60;
pub const INBOX_MAX_EXPIRY_SECONDS: i64 = 7 * 24 * 60 * 60;
pub const INBOX_HISTORY_SECONDS: i64 = 7 * 24 * 60 * 60;
pub const INBOX_EXTERNAL_META_MAX_BYTES: usize = 16 * 1024;
const INBOX_NAME_MAX_BYTES: usize = 63;

pub fn is_external_inbox(handle: &str) -> bool {
    handle.starts_with(EXTERNAL_INBOX_PREFIX)
}

/// The inbox and the agent of a thread root, in either direction: an inbox
/// asks an agent, or an agent opens a thread with an inbox.
pub fn inbox_thread_parties(root: &OrchestrationMessage) -> Option<(&str, &str)> {
    if root.thread_id.is_some() {
        return None;
    }
    if is_external_inbox(&root.from_handle) && !is_external_inbox(&root.to_handle) {
        Some((&root.from_handle, &root.to_handle))
    } else if is_external_inbox(&root.to_handle) && !is_external_inbox(&root.from_handle) {
        Some((&root.to_handle, &root.from_handle))
    } else {
        None
    }
}

pub fn validate_inbox_address(address: &str) -> Result<()> {
    let Some(name) = address.strip_prefix(EXTERNAL_INBOX_PREFIX) else {
        anyhow::bail!(
            "inbox_invalid_address: an inbox address starts with {EXTERNAL_INBOX_PREFIX}"
        );
    };
    let first_is_alphanumeric = name
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    let rest_is_valid = name
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '.' | '_' | '-'));
    if !first_is_alphanumeric || !rest_is_valid || name.len() > INBOX_NAME_MAX_BYTES {
        anyhow::bail!(
            "inbox_invalid_address: use {EXTERNAL_INBOX_PREFIX} followed by 1-63 lowercase letters, digits, dots, underscores or hyphens, starting with a letter or digit"
        );
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InboxQuestionStatus {
    Pending,
    /// Pasted into the agent's terminal, or read by it with `check`.
    Delivered,
    Expired,
    Answered,
    Cancelled,
}

impl InboxQuestionStatus {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "pending" => Some(Self::Pending),
            "delivered" => Some(Self::Delivered),
            "expired" => Some(Self::Expired),
            "answered" => Some(Self::Answered),
            "cancelled" => Some(Self::Cancelled),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InboxMessageKind {
    /// Sent by the inbox to an agent.
    Question,
    /// Sent to the inbox and naming the question it answers.
    Reply,
    /// Sent to the inbox without a reference to a question.
    Message,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InboxMessage {
    pub kind: InboxMessageKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<InboxQuestionStatus>,
    pub delivery: MessageDelivery,
    pub delivered_at: Option<String>,
    /// How the host routed a question when it was asked: `pasted_now`,
    /// `queued_at_turn_end`, `check` or `unavailable`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delivery_mode: Option<String>,
    pub message: OrchestrationMessage,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InboxThread {
    pub thread_id: String,
    pub inbox: String,
    pub recipient: String,
    pub workspace_id: Option<String>,
    pub subject: String,
    pub created_at: String,
    pub last_activity_at: String,
    pub last_sequence: i64,
    pub status: InboxQuestionStatus,
    pub question_count: i64,
    pub reply_count: i64,
    pub unread_reply_count: i64,
    pub origin: Option<Value>,
    pub target: Option<Value>,
    /// The delivery mode of the thread's latest question, if any.
    pub delivery_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InboxThreadDetail {
    pub thread: InboxThread,
    pub messages: Vec<InboxMessage>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct InboxThreadPage {
    pub items: Vec<InboxThread>,
    pub next_before: Option<i64>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InboxSummaryEntry {
    pub inbox: String,
    pub thread_count: i64,
    pub pending_count: i64,
    pub awaiting_reply_count: i64,
    pub unread_reply_count: i64,
    pub last_activity_at: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct InboxThreadFilter {
    pub inbox: Option<String>,
    pub workspace_id: Option<String>,
    pub status: Option<InboxQuestionStatus>,
    /// Only threads whose recorded `origin.clientId` equals this value, such
    /// as the questions one MCP client asked in a shared inbox.
    pub origin_client_id: Option<String>,
    pub before_sequence: Option<i64>,
    pub limit: i64,
}

pub struct NewInboxQuestion {
    pub delivery: MessageDelivery,
    pub inbox: String,
    pub recipient: String,
    pub subject: String,
    pub body: String,
    pub priority: OrchestrationMessagePriority,
    pub thread_id: Option<String>,
    pub workspace_id: Option<String>,
    pub payload: Option<String>,
    pub expires_in_seconds: Option<i64>,
    pub external_meta: Value,
}
