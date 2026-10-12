//! When a message reaches an agent's terminal.
//!
//! An idle agent receives every queued message at once. A working agent only
//! receives messages sent with `delivery = now`, and only when its adapter
//! queues input typed mid-turn (Claude Code and Codex). `Waiting` and
//! `Blocked` agents never receive a paste, because the Enter that submits it
//! could answer the prompt they are showing.

use alera_core::runtime::MessageDelivery;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::session::Session;

use super::ServerActor;

/// What happened to a message right after it was stored, or, for a target
/// listing, what `delivery = now` would do right now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum DeliveryMode {
    /// Pasted into the agent's terminal now.
    PastedNow,
    /// Waits until the agent finishes its turn.
    QueuedAtTurnEnd,
    /// The recipient is an active coordinator, which reads with `check`.
    Check,
    /// No running agent can receive it.
    Unavailable,
}

impl DeliveryMode {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            DeliveryMode::PastedNow => "pasted_now",
            DeliveryMode::QueuedAtTurnEnd => "queued_at_turn_end",
            DeliveryMode::Check => "check",
            DeliveryMode::Unavailable => "unavailable",
        }
    }
}

/// Reads `delivery` from a request payload, falling back to the producer's
/// default when it is absent.
pub(super) fn requested_delivery(
    payload: &Value,
    default: MessageDelivery,
) -> HostResult<MessageDelivery> {
    match payload.get("delivery") {
        None | Some(Value::Null) => Ok(default),
        Some(Value::String(raw)) => match raw.as_str() {
            "now" => Ok(MessageDelivery::Now),
            "turnEnd" => Ok(MessageDelivery::TurnEnd),
            other => Err(HostError::format(format!(
                "delivery must be now or turnEnd, not {other}."
            ))),
        },
        Some(_) => Err(HostError::format("delivery must be now or turnEnd.")),
    }
}

impl ServerActor {
    /// Whether the agent in `handle` queues input submitted while it works.
    pub(super) fn accepts_queued_input(&self, handle: &str) -> bool {
        self.agent_presence
            .agent_type(handle)
            .and_then(adapter_for)
            .is_some_and(|adapter| adapter.accepts_queued_input)
    }

    /// What a `delivery = now` message to `handle` would do right now.
    pub(super) fn delivery_mode_for(&self, handle: &str) -> DeliveryMode {
        if self.is_active_coordinator_handle(handle) {
            return DeliveryMode::Check;
        }
        if !self.sessions.get(handle).is_some_and(Session::running) {
            return DeliveryMode::Unavailable;
        }
        let Some(presence) = self.agent_presence.get(handle) else {
            return DeliveryMode::Unavailable;
        };
        if presence.accepts_injection() || self.accepts_mid_turn_paste(handle) {
            DeliveryMode::PastedNow
        } else {
            DeliveryMode::QueuedAtTurnEnd
        }
    }

    /// Send-time delivery: pastes every queued message into an idle agent,
    /// or only the `delivery = now` ones into a working agent that queues
    /// input. Everything else waits for the agent's next idle transition.
    pub(super) async fn deliver_after_send(&mut self, handle: &str) -> DeliveryMode {
        if self.is_active_coordinator_handle(handle) {
            return DeliveryMode::Check;
        }
        if !self.sessions.get(handle).is_some_and(Session::running) {
            return DeliveryMode::Unavailable;
        }
        if self.agent_presence.get(handle).is_none() {
            return DeliveryMode::Unavailable;
        }
        let pasted = if self.agent_presence.is_injection_ready(handle) {
            self.paste_pending_messages(handle, false).await
        } else if self.accepts_mid_turn_paste(handle) {
            self.deliver_now_messages(handle).await
        } else {
            false
        };
        if pasted {
            DeliveryMode::PastedNow
        } else {
            DeliveryMode::QueuedAtTurnEnd
        }
    }

    /// Pastes the `delivery = now` messages queued for a working agent.
    pub(super) async fn deliver_now_messages(&mut self, handle: &str) -> bool {
        if !self.accepts_mid_turn_paste(handle) {
            return false;
        }
        self.paste_pending_messages(handle, true).await
    }

    fn accepts_mid_turn_paste(&self, handle: &str) -> bool {
        self.agent_presence
            .get(handle)
            .is_some_and(|presence| presence.state == AgentPresenceState::Working)
            && self.accepts_queued_input(handle)
            && !self.is_active_coordinator_handle(handle)
            && !self.orchestration_delivery_in_flight.contains(handle)
    }
}
