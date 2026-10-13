//! Requests a session actor accepts, parsed from the wire payloads.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

/// Who is calling, derived from the connection by the host.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct CallerCtx {
    /// Receipt scope: `desktop`, `cli`, `mobile:<device>`, ...
    pub scope: String,
    /// Stamped on user messages and request resolutions.
    pub actor: String,
    pub mobile: bool,
}

impl CallerCtx {
    pub(crate) fn runtime() -> Self {
        Self {
            scope: "runtime".into(),
            actor: "runtime".into(),
            mobile: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct SendInput {
    pub client_message_id: String,
    pub text: String,
    /// Attachments already validated and resolved to host paths.
    pub attachments: Vec<Value>,
    /// `auto | steer | queue`.
    pub delivery: String,
    pub model: Option<String>,
    pub interaction_mode: Option<String>,
    /// The maximum runtime mode allowed by the authenticated host caller.
    /// This is stamped by host code before an internal send and is never
    /// accepted from a desktop or mobile payload.
    #[serde(default)]
    pub runtime_mode_ceiling: Option<String>,
    /// Host-only: who sent a message that no person typed
    /// (`{kind: chatMessage|orchestrationWake, senderChatId?, taskIds?}`).
    /// Wire requests always leave it `None`, which records `{kind: user}`.
    pub origin: Option<Value>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct ConfigureInput {
    pub provider: Option<String>,
    pub provider_instance_id: Option<String>,
    pub model: Option<Option<String>>,
    pub runtime_mode: Option<String>,
    pub interaction_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum ChatOp {
    Snapshot,
    History {
        before: String,
        limit: usize,
    },
    Send(SendInput),
    /// Send on behalf of an authenticated chat while enforcing its mode
    /// ceiling inside the serialized session actor.
    SendWithinCeiling {
        input: SendInput,
        runtime_mode_ceiling: String,
    },
    /// Runs a mutating control operation while checking the current mode and
    /// any requested new mode inside the serialized session actor.
    WithinCeiling {
        runtime_mode_ceiling: String,
        operation: Box<ChatOp>,
    },
    QueueCancel {
        queue_id: String,
    },
    /// Atomically cancel one client message, removing it from the queue or
    /// interrupting its owned active turn.
    CancelMessage {
        client_message_id: String,
    },
    Interrupt {
        turn_id: Option<String>,
    },
    Respond {
        runtime_request_id: String,
        response: Value,
    },
    Configure(ConfigureInput),
    Rename {
        title: String,
    },
    Recover {
        mode: Option<String>,
    },
    /// `agentChat.close` and `tab.remove`: archive and stop.
    Close,
    /// Attach a fresh tab to an archived chat.
    Reopen {
        tab_id: String,
    },
    /// Workspace slept or archived: stop the provider, keep the chat open.
    Stop,
    /// Graceful host shutdown.
    Shutdown,
}

impl ChatOp {
    pub(crate) fn mutates(&self) -> bool {
        !matches!(self, ChatOp::Snapshot | ChatOp::History { .. })
    }
}

pub(crate) struct ChatEnvelope {
    pub op: ChatOp,
    pub ctx: CallerCtx,
    /// Client idempotency key with the verb and payload digest it covers.
    pub receipt_key: Option<ReceiptKey>,
    pub reply: oneshot::Sender<HostResult<Value>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ReceiptKey {
    pub verb: String,
    pub request_id: String,
    pub digest: String,
}

pub(crate) fn conflict(code: &str, message: impl Into<String>) -> HostError {
    HostError::conflict(code, message, serde_json::json!({}))
}

pub(crate) fn unsupported(message: impl Into<String>) -> HostError {
    conflict("unsupported", message)
}

pub(crate) fn turn_active(message: impl Into<String>) -> HostError {
    conflict("turnActive", message)
}

pub(crate) fn optional_string(payload: &Value, key: &str) -> HostResult<Option<String>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if value.trim().is_empty() => Ok(None),
        Some(Value::String(value)) => Ok(Some(value.clone())),
        Some(_) => Err(HostError::format(format!("{key} must be a string"))),
    }
}

pub(crate) fn required_string(payload: &Value, key: &str) -> HostResult<String> {
    optional_string(payload, key)?.ok_or_else(|| HostError::format(format!("{key} is required")))
}
