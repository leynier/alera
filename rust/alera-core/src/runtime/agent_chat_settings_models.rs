//! Host-owned preferences and sanitized provider overrides.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const AGENT_CHAT_SETTINGS_MAX_BYTES: usize = 256 * 1024;
pub const AGENT_CHAT_SETTINGS_MAX_ENTRIES: usize = 500;
pub const AGENT_CHAT_SETTINGS_MAX_OPERATIONS: usize = 100;

/// An entry edit preserves every other entry in the same section. Supported
/// sections are rememberedSelection, defaultSelection, projectDefaults,
/// models, and favorites. Singleton sections have no key; map sections do.
/// A null/absent value removes the entry. Favorite values are selections.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentChatPreferenceOperation {
    pub section: String,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default)]
    pub value: Option<Value>,
}

/// Internal record, never a wire response. The envelope has no sensitive
/// values. Secret refs name credential-store entries, not their contents.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatProviderInstanceRecord {
    pub provider_instance_id: String,
    pub envelope: Value,
    pub secret_refs: BTreeMap<String, String>,
    pub revision: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatProviderInstances {
    pub instances: Vec<AgentChatProviderInstanceRecord>,
    pub revision: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatProviderInstanceMutation {
    /// Replaces this envelope, preserving refs for still-declared secrets.
    Upsert {
        provider_instance_id: String,
        envelope: Value,
    },
    UpsertWithSecretRef {
        provider_instance_id: String,
        envelope: Value,
        name: String,
        secret_ref: Option<String>,
    },
    /// Removes an override. The host decides whether a built-in falls back
    /// to defaults and checks removal impact before requesting the mutation.
    Remove { provider_instance_id: String },
    /// `name` is a sensitive env declaration or `option:<key>` declaration.
    /// The credential store must save a new immutable entry before this call;
    /// on a revision conflict it can remove that unreferenced new entry.
    SetSecretRef {
        provider_instance_id: String,
        name: String,
        secret_ref: Option<String>,
    },
}

/// Applied/replayed values are sanitized response envelopes including the
/// revision. A replay returns the original value even after later edits.
#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatSettingsOutcome {
    Applied(Value),
    Replay(Value),
    RevisionConflict { revision: i64 },
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatCloseOutcome {
    Closed {
        chat_id: String,
        tab_id: String,
        archived: bool,
        discarded: bool,
    },
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatDeleteOutcome {
    Deleted,
    NotNeverSent,
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatArchivedDeleteOutcome {
    Deleted,
    NotArchived,
    ReferencedByTasks,
    CursorConflict { current: i64 },
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatRewindOutcome {
    Rewound {
        record: Box<super::AgentChatRecord>,
        event: super::AgentChatEvent,
        /// The complete selected turn's user message including attachments.
        prompt: Value,
    },
    Replay(Value),
    ReceiptConflict,
    CursorConflict {
        current: i64,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatReadOutcome {
    Applied(Value),
    Replay(Value),
    ReceiptConflict,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatAttention {
    pub chat_id: String,
    pub cursor: i64,
    pub read_cursor: i64,
    pub unread: bool,
    pub open_child_task_count: i64,
    pub child_needs_input: bool,
    pub child_failed: bool,
}
