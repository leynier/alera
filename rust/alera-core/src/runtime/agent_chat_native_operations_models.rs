//! Host-internal native mutation intent. No provider response bodies are stored.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::runtime::{AgentChatEvent, AgentChatRecord};

pub const AGENT_CHAT_NATIVE_REWIND: &str = "rewind";
pub const AGENT_CHAT_NATIVE_REWIND_FILES: &str = "rewindFiles";
pub const AGENT_CHAT_NATIVE_OPERATION_MAX_BYTES: usize = 4096;
pub const AGENT_CHAT_NATIVE_OPERATION_PAGE_LIMIT: i64 = 100;

#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatNativeOperationInput {
    pub operation_id: String,
    pub chat_id: String,
    pub expected_cursor: i64,
    pub expected_generation: i64,
    pub expected_native_thread_id: String,
    pub process_epoch: String,
    pub kind: String,
    pub turn_id: String,
    pub boundary: Value,
    pub actor: String,
}

/// Plain caller scope and verb are folded into the existing receipt namespace
/// as a JSON pair, exactly like the runtime host's receipt_scope helper.
#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatNativeOperationReceipt {
    pub caller_scope: String,
    pub verb: String,
    pub request_id: String,
    pub digest: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentChatNativeOperation {
    pub operation_id: String,
    pub chat_id: String,
    pub generation: i64,
    pub base_cursor: i64,
    pub native_thread_id: String,
    pub process_epoch: String,
    pub kind: String,
    pub turn_id: String,
    pub boundary: Value,
    pub actor: String,
    pub caller_scope: String,
    pub verb: String,
    pub request_id: String,
    pub digest: String,
    pub state: String,
    pub revision: i64,
    pub ack: Option<Value>,
    pub result: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatNativeOperationOutcome {
    Applied(Box<AgentChatNativeOperation>),
    Existing(Box<AgentChatNativeOperation>),
    Replay(Value),
    ReceiptConflict,
    CursorConflict { current: i64 },
    RevisionConflict { current: i64 },
    Busy { reason: String },
}

#[derive(Debug, Clone, PartialEq)]
pub enum AgentChatNativeOperationCompleteOutcome {
    Committed {
        record: Box<AgentChatRecord>,
        event: AgentChatEvent,
        response: Value,
    },
    Replay(Value),
    ReceiptConflict,
    CursorConflict {
        current: i64,
    },
    RevisionConflict {
        current: i64,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentChatNativeOperationPage {
    pub operations: Vec<AgentChatNativeOperation>,
    pub next_after: Option<String>,
}
