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
    #[serde(default)]
    pub reasoning_effort: Option<String>,
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
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present_optional_string"
    )]
    pub model: Option<Option<String>>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present_optional_string"
    )]
    pub reasoning_effort: Option<Option<String>>,
    pub runtime_mode: Option<String>,
    pub interaction_mode: Option<String>,
}

fn present_optional_string<'de, D>(deserializer: D) -> Result<Option<Option<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Option::<String>::deserialize(deserializer).map(Some)
}

#[cfg(test)]
mod configure_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn serialized_configuration_preserves_omission_and_explicit_resets() {
        let omitted = serde_json::to_value(ConfigureInput::default()).unwrap();
        assert!(omitted.get("model").is_none());
        assert!(omitted.get("reasoning_effort").is_none());
        let reset = ConfigureInput {
            model: Some(None),
            reasoning_effort: Some(None),
            ..Default::default()
        };
        let encoded = serde_json::to_value(&reset).unwrap();
        assert_eq!(encoded["model"], Value::Null);
        assert_eq!(encoded["reasoning_effort"], Value::Null);
        let decoded: ConfigureInput = serde_json::from_value(encoded).unwrap();
        assert_eq!(decoded.model, Some(None));
        assert_eq!(decoded.reasoning_effort, Some(None));
        let decoded: ConfigureInput = serde_json::from_value(json!({})).unwrap();
        assert_eq!(decoded.model, None);
        assert_eq!(decoded.reasoning_effort, None);
    }
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
    QueuePromoteToSteer {
        queue_id: String,
        turn_id: String,
    },
    ApprovalHistory {
        before: Option<String>,
        limit: usize,
    },
    TurnDiff {
        turn_id: String,
    },
    Fork {
        turn_id: String,
        new_chat_id: String,
        new_tab_id: String,
        title: Option<String>,
    },
    Rewind {
        turn_id: String,
    },
    NativeRewind {
        turn_id: String,
    },
    NativeRewindFiles {
        turn_id: String,
    },
    NativeFileCheckpoints {
        enabled: bool,
    },
    NativeHistoryOperation {
        operation_id: Option<String>,
    },
    NativeHistoryReconcile {
        operation_id: String,
        expected_revision: Option<i64>,
        action: String,
    },
    Delete,
    QueueEdit {
        queue_id: String,
        text: String,
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
        !matches!(
            self,
            ChatOp::Snapshot
                | ChatOp::History { .. }
                | ChatOp::ApprovalHistory { .. }
                | ChatOp::TurnDiff { .. }
                | ChatOp::NativeHistoryOperation { .. }
        )
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
