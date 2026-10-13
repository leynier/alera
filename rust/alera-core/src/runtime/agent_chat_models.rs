//! Provider-neutral agent chat records persisted in `runtime.sqlite`.
//!
//! The runtime host projects provider events into a canonical snapshot and a
//! delta per commit; the store keeps the snapshot header in one row, turns
//! and items as durable paginated history, and every delta in a cursor journal. Native
//! provider identifiers stay inside the store and never reach a phone payload.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use thiserror::Error;

/// Tab kind whose payload is `{chatId, provider, providerInstanceId, model?}`.
pub const AGENT_CHAT_TAB_KIND: &str = "agentChat";
/// Snapshot window, history page, and event page budget.
pub const AGENT_CHAT_PAGE_MAX_BYTES: usize = 256 * 1024;
/// One serialized item, so any item always fits a page on its own.
pub const AGENT_CHAT_ITEM_MAX_BYTES: usize = 256 * 1024;
/// One turn's metadata, including fields unknown to this store.
pub const AGENT_CHAT_TURN_MAX_BYTES: usize = 64 * 1024;
/// Turn metadata in a snapshot, including the visible item window's turns.
pub const AGENT_CHAT_TURN_PROJECTION_MAX_BYTES: usize = 256 * 1024;
/// Settled turns retained in addition to turns required by visible state.
pub const AGENT_CHAT_RECENT_TURNS: i64 = 32;
/// The snapshot header (everything but `items` and `turns`).
pub const AGENT_CHAT_SNAPSHOT_HEADER_MAX_BYTES: usize = 384 * 1024;
/// One delta; header plus window plus delta stays under the 1 MiB relay frame.
pub const AGENT_CHAT_DELTA_MAX_BYTES: usize = 512 * 1024;
pub const AGENT_CHAT_PAGE_MAX_ITEMS: i64 = 200;
pub const AGENT_CHAT_EVENT_PAGE_MAX: i64 = 500;
/// Deltas kept per chat; a reader further behind reloads the snapshot.
pub const AGENT_CHAT_EVENT_RETENTION: i64 = 2048;
pub const AGENT_CHAT_RECEIPT_RETENTION_DAYS: i64 = 7;
pub const AGENT_CHAT_ID_MAX_BYTES: usize = 256;
pub const AGENT_CHAT_METADATA_MAX_BYTES: usize = 64 * 1024;
/// Recorded as `turn.reason` on turns a runtime restart cut short.
pub const AGENT_CHAT_INTERRUPT_RUNTIME_RESTARTED: &str = "runtimeRestarted";
/// `recovery.kind` values startup recovery writes.
pub const AGENT_CHAT_RECOVERY_RESUMABLE: &str = "resumable";
pub const AGENT_CHAT_RECOVERY_NOT_RESUMABLE: &str = "notResumable";

#[derive(Debug, Error, PartialEq, Eq)]
pub enum AgentChatStoreError {
    #[error("Agent chat not found: {0}")]
    NotFound(String),
    #[error("Invalid agent chat: {0}")]
    Invalid(String),
    #[error("Agent chat already exists: {0}")]
    AlreadyExists(String),
    #[error("Agent chat {chat_id} cannot switch provider while {reason}")]
    ProviderSwitchBlocked { chat_id: String, reason: String },
    #[error("Agent chat {chat_id} native id conflict: {detail}")]
    NativeIdConflict { chat_id: String, detail: String },
    /// The host must split or trim the item (keep the output's head and tail
    /// and say so in the item) and commit again; the store never truncates.
    #[error("Agent chat item {item_id} is {bytes} bytes, over the {limit} byte limit")]
    ItemTooLarge {
        item_id: String,
        bytes: usize,
        limit: usize,
    },
}

/// The persisted chat. `native_thread_id` is the current generation's provider
/// thread and is host-internal: it is never part of `snapshot`.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatRecord {
    pub chat_id: String,
    pub tab_id: String,
    pub workspace_id: String,
    pub provider_instance_id: String,
    pub provider: String,
    pub native_thread_id: Option<String>,
    /// Starts at 1 and grows on every provider switch; native ids are scoped to it.
    pub generation: i64,
    pub archived: bool,
    pub archived_at: Option<DateTime<Utc>>,
    pub cursor: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// Host-only JSON object outside the snapshot (caller origin, parent
    /// chat, task linkage), so new links need no schema change. It never
    /// reaches a phone, and credential-shaped keys are refused like in the
    /// snapshot: MCP bearers and provider env stay in the launch hook.
    pub metadata: Option<Value>,
    /// `AgentChatSnapshot` JSON. Reads fill `items` with the newest page and
    /// `historyBefore` when older items exist; listings leave `items` empty.
    pub snapshot: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentChatSessionStatus {
    Starting,
    Ready,
    Running,
    Waiting,
    Stopped,
    Error,
}

impl AgentChatSessionStatus {
    pub fn is_live(self) -> bool {
        matches!(
            self,
            Self::Starting | Self::Ready | Self::Running | Self::Waiting
        )
    }
}

/// Unknown keys are kept in `extra` so a newer host's fields survive a
/// round trip through an older store.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatSession {
    pub status: AgentChatSessionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub runtime_mode: String,
    pub interaction_mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_turn_id: Option<String>,
    #[serde(default = "empty_object")]
    pub capabilities: Value,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatTurn {
    pub turn_id: String,
    /// `running`, `completed`, `failed`, `interrupted`, or `cancelled`.
    pub status: String,
    /// Why the turn ended early; `runtimeRestarted` after a restart.
    #[serde(
        alias = "interruptReason",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatRequest {
    pub request_id: String,
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// One canonical transcript entry. `type` is snake_case (`user_message`,
/// `assistant_message`, ...) and `status` camelCase (`inProgress`, ...).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatItem {
    pub item_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(rename = "type")]
    pub item_type: String,
    pub status: String,
    #[serde(default)]
    pub streaming: bool,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attachments: Option<Value>,
    #[serde(default = "empty_object")]
    pub normalized: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatSnapshot {
    pub chat_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub provider_instance_id: String,
    pub provider: String,
    #[serde(default)]
    pub title: String,
    pub cursor: i64,
    pub session: AgentChatSession,
    #[serde(default)]
    pub turns: Vec<AgentChatTurn>,
    #[serde(default)]
    pub items: Vec<AgentChatItem>,
    #[serde(default)]
    pub pending_requests: Vec<AgentChatRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recovery: Option<Value>,
    /// Item cursor for `agent_chat_history`; set by the store on reads.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_before: Option<i64>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// Which item field a text append extends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentChatTextStream {
    Text,
    ReasoningText,
    Output,
}

/// `offset` counts UTF-16 code units, which is what a Dart client's
/// `String.length` measures, so it can splice without decoding. Appends are
/// applied after the delta's `items`, and one whose text is already present
/// at `offset` is a no-op, so a delta may carry both a final item and the
/// appends that produced it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatTextAppend {
    pub item_id: String,
    pub stream: AgentChatTextStream,
    pub offset: u64,
    pub text: String,
}

/// Every field mirrors the snapshot it was committed with: `items` and
/// `turns` are upserts, `requests` is the full pending list, and the rest
/// replace their snapshot counterpart.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatDelta {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items: Option<Vec<AgentChatItem>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub removed_item_ids: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub text_appends: Vec<AgentChatTextAppend>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requests: Option<Vec<AgentChatRequest>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<AgentChatSession>,
    /// `null` clears the snapshot's usage; absent leaves it unchanged.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    pub usage: Option<Option<Value>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Present only on a provider switch, which starts a new generation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_instance_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turns: Option<Vec<AgentChatTurn>>,
    /// `null` clears the recovery notice once the host has resumed or restarted.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present"
    )]
    pub recovery: Option<Option<Value>>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// One journal entry: the delta that moved the chat to `cursor`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatEvent {
    pub chat_id: String,
    pub cursor: i64,
    pub delta: Value,
    pub occurred_at: String,
}

/// `snapshot_required` means the reader cannot be caught up from the journal
/// (pruned past it, or ahead of the chat) and must reload the snapshot.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatEventPage {
    pub chat_id: String,
    pub events: Vec<AgentChatEvent>,
    pub cursor: i64,
    pub has_more: bool,
    pub snapshot_required: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatHistoryPage {
    pub chat_id: String,
    pub items: Vec<Value>,
    /// Complete metadata for every persisted turn referenced by this page.
    pub turns: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub history_before: Option<i64>,
}

/// A command receipt. `digest` identifies the request payload (see
/// `agent_chat_command_digest`); `receipt` is the response to replay.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatReceipt {
    pub caller_scope: String,
    pub request_id: String,
    pub digest: String,
    pub receipt: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatReceiptCheck {
    New,
    Replay(Value),
    Conflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatCreateOutcome {
    Created(Box<AgentChatRecord>),
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatRestoreOutcome {
    Restored(Box<AgentChatRecord>),
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatCommitOutcome {
    Committed(AgentChatEvent),
    Replay(Value),
    ReceiptConflict,
    CursorConflict { current: i64 },
}

/// A native id mapping request. `native_id` must be a JSON string or
/// integer; `"1"` and `1` are different ids. `app_id` lets the host keep an
/// id it already handed out (a turn id minted before the provider answered).
#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatNativeIdInput {
    pub chat_id: String,
    pub generation: i64,
    pub kind: String,
    pub native_id: Value,
    pub app_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatNativeId {
    pub chat_id: String,
    pub generation: i64,
    pub kind: String,
    pub native_id: Value,
    pub app_id: String,
}

/// What startup recovery changed in one chat, committed at `cursor`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatRecoveryOutcome {
    pub chat_id: String,
    pub cursor: i64,
    pub interrupted_turn_ids: Vec<String>,
    pub expired_request_ids: Vec<String>,
    pub can_resume: bool,
    pub can_restart: bool,
}

fn present<'de, D>(deserializer: D) -> Result<Option<Option<Value>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Ok(Some(Option::<Value>::deserialize(deserializer)?))
}

pub(super) fn empty_object() -> Value {
    Value::Object(Map::new())
}
