//! How an ACP prompt's turn ends. ACP v2 answers `session/prompt` with an
//! acceptance and reports the end with the root idle `state_update`, as T3
//! Code's client waits for it (`5a969c17e7`); a response that carries a stop
//! reason, or an RPC error, still ends the turn at once.

use crate::native_children::NativeChildren;
use crate::native_children_route::is_update_method;
use agent_client_protocol::AcpIncoming;
use alera_provider_protocol::{EventKind, ProviderEvent, TurnStatus};
use serde_json::{json, Value};

/// Where a frame comes from, as far as ending turns goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TurnFrame {
    /// The response to a `session/prompt`, current or late.
    PromptResponse,
    /// A `state_update` of the root session.
    RootState,
    Other,
}

impl TurnFrame {
    pub(crate) fn of(incoming: &AcpIncoming, root: &str) -> Self {
        match incoming {
            AcpIncoming::Response(_) => Self::PromptResponse,
            AcpIncoming::Notification { method, params, .. }
                if is_update_method(method) && is_root_state(params, root) =>
            {
                Self::RootState
            }
            _ => Self::Other,
        }
    }
}

/// The mapping takes an update without a session id as the root's.
fn is_root_state(params: &Value, root: &str) -> bool {
    let session = params
        .get("sessionId")
        .or_else(|| params.get("session_id"))
        .and_then(Value::as_str);
    let update = params.get("update").unwrap_or(params);
    session.is_none_or(|session| session == root)
        && update.get("sessionUpdate").and_then(Value::as_str) == Some("state_update")
}

/// What the turns that already ended mean for the frames still to come.
#[derive(Debug, Default)]
pub(crate) struct PromptLifecycle {
    /// The last turn failed, so an idle error after it repeats that failure.
    last_turn_failed: bool,
    /// An ACP v2 turn ended on its prompt response, so the agent may still
    /// send that prompt's idle, which must not end the next turn.
    idle_owed: bool,
}

impl PromptLifecycle {
    /// Whether a root idle ends the running turn. Following work state, only
    /// one after the prompt was accepted or the root ran does; otherwise any
    /// but the idle an earlier turn still owes.
    pub(crate) fn idle_ends_turn(&self, follows: bool, children: &NativeChildren) -> bool {
        if follows {
            children.accepted || children.running_seen
        } else {
            !self.idle_owed
        }
    }

    /// Whether an idle error while no turn runs is shown as an error.
    pub(crate) fn notices_turnless_errors(&self) -> bool {
        !self.last_turn_failed
    }

    pub(crate) fn prompt_sent(&mut self) {
        self.last_turn_failed = false;
    }

    /// Records an event mapped from `frame`. `awaits_idle` is ACP v2, whose
    /// prompts end on their idle.
    pub(crate) fn observe(&mut self, frame: TurnFrame, event: &ProviderEvent, awaits_idle: bool) {
        let ended = event.kind == EventKind::TurnCompleted;
        if ended {
            self.last_turn_failed = event.payload.get("state") == Some(&json!(TurnStatus::Failed));
        }
        match frame {
            // The owed idle came, or the agent already works on the next prompt.
            TurnFrame::RootState => self.idle_owed = false,
            TurnFrame::PromptResponse if ended => self.idle_owed = awaits_idle,
            TurnFrame::PromptResponse
                if event.kind == EventKind::Unknown("acp.prompt.accepted".into()) =>
            {
                self.idle_owed = false;
            }
            _ => {}
        }
    }
}
