//! Stopping a turn. Every provider call made during a turn has a deadline,
//! so Stop always answers. A Stop the provider does not confirm within
//! [StopTiming::unresponsive] is marked `unresponsiveAt` on the session's
//! `stop`, and Force stop then drops the provider, which kills its process
//! group, and ends the turn itself.

use std::future::Future;
use std::time::Duration;

use alera_provider_protocol::{InterruptInput, ProviderError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::time::Instant;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported};
use super::ids::now;
use super::session::ChatSession;

/// The turn ends as `interrupted` with this message after a Force stop.
pub(crate) const FORCE_STOP_MESSAGE: &str = "Force stopped by user";
/// The turn's `reason` after a Force stop.
pub(crate) const FORCE_STOP_REASON: &str = "forceStopped";

/// How long the actor waits on the provider during a turn.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct StopTiming {
    /// `Provider::interrupt`.
    pub interrupt: Duration,
    /// `Provider::steer_turn` and `Provider::respond`.
    pub control: Duration,
    /// From the Stop until it reads as unresponsive.
    pub unresponsive: Duration,
}

impl Default for StopTiming {
    fn default() -> Self {
        Self {
            interrupt: Duration::from_secs(5),
            control: Duration::from_secs(10),
            unresponsive: Duration::from_secs(15),
        }
    }
}

/// `session.stop`: the Stop that reached the running turn, while that turn
/// has not ended.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct StopView {
    pub turn_id: String,
    pub requested_at: String,
    /// Set once the provider failed to end the turn in time; clients then
    /// offer Force stop.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unresponsive_at: Option<String>,
}

/// Why the turn a stop reached ended, recorded on it in place of the
/// provider's own reason.
#[derive(Debug, Clone)]
pub(crate) struct StopNotice {
    pub reason: &'static str,
    pub message: &'static str,
}

/// A provider error as a host error.
pub(super) fn provider_error(error: ProviderError) -> HostError {
    match error {
        ProviderError::Unsupported(message) => unsupported(message),
        other => HostError::state(other.to_string()),
    }
}

/// Runs one provider call with the turn's control deadline.
pub(super) async fn within<T>(
    deadline: Duration,
    call: impl Future<Output = Result<T, ProviderError>>,
) -> HostResult<T> {
    match tokio::time::timeout(deadline, call).await {
        Ok(result) => result.map_err(provider_error),
        Err(_) => Err(conflict(
            "providerTimeout",
            "The agent did not answer in time.",
        )),
    }
}

impl ChatSession {
    /// Stops the running turn. With none running, it stops the background
    /// work earlier turns left instead.
    pub(super) async fn interrupt(&mut self, turn_id: Option<&str>) -> HostResult<Value> {
        let Some(active) = self.header.session.active_turn_id.clone() else {
            let stopped = self.stop_background_work().await;
            return Ok(json!({"acknowledged": true, "interrupted": stopped}));
        };
        if turn_id.is_some_and(|id| id != active) {
            return Err(conflict("turnNotActive", "That turn is no longer running."));
        }
        if self.deferred_turn.take().is_some() || self.provider.is_none() {
            self.cancel_startup().await;
            self.revoke_launch_credentials("interrupted").await;
            self.finish_turn("interrupted", None, Some("interrupted".into()))
                .await;
            return Ok(json!({"acknowledged": true, "interrupted": true}));
        }
        let requested = (Instant::now(), now());
        let deadline = self.deps.stop_timing.interrupt;
        let input = InterruptInput {
            thread_id: self.header.chat_id.clone(),
            turn_id: self.provider_turn_id.clone(),
        };
        let provider = self.provider.as_mut().expect("provider is running");
        match tokio::time::timeout(deadline, provider.interrupt(input)).await {
            Ok(result) => result.map_err(|error| HostError::state(error.to_string()))?,
            // The turn still reads as stopping; the deadline below decides.
            Err(_) => {
                tracing::warn!(chat_id = %self.header.chat_id, "the provider did not answer the interrupt in time")
            }
        }
        self.mark_stopping(active, requested);
        self.events_armed = true;
        Ok(json!({"acknowledged": true, "interrupted": true}))
    }

    /// Records the Stop on the session view once per turn; a repeated Stop
    /// keeps the first request time and deadline.
    fn mark_stopping(&mut self, turn_id: String, requested: (Instant, String)) {
        let known = self
            .header
            .session
            .stop
            .as_ref()
            .is_some_and(|stop| stop.turn_id == turn_id);
        self.stopping_turn = Some(turn_id.clone());
        if known {
            return;
        }
        self.stop_deadline = Some(requested.0 + self.deps.stop_timing.unresponsive);
        self.header.session.stop = Some(StopView {
            turn_id,
            requested_at: requested.1,
            unresponsive_at: None,
        });
    }

    /// The deadline passed with the stopped turn still running.
    pub(super) async fn stop_deadline_passed(&mut self) {
        self.stop_deadline = None;
        let active = self.header.session.active_turn_id.clone();
        let Some(stop) = self.header.session.stop.as_mut() else {
            return;
        };
        if Some(&stop.turn_id) != active.as_ref() || stop.unresponsive_at.is_some() {
            return;
        }
        stop.unresponsive_at = Some(now());
        tracing::warn!(chat_id = %self.header.chat_id, turn_id = %stop.turn_id, "the provider did not end a stopped turn");
        let _ = self.flush().await;
    }

    /// Forgets the Stop of a turn that ended, and returns the notice it left.
    pub(super) fn clear_stop(&mut self) -> Option<StopNotice> {
        self.stopping_turn = None;
        self.stop_deadline = None;
        self.header.session.stop = None;
        self.stop_notice.take()
    }

    /// `agentChat.forceStop`: drops the provider of a chat whose agent does
    /// not stop, which kills its process group (an external OpenCode server
    /// or Cursor bridge only loses this client), ends the running turn as
    /// interrupted, empties the queue and leaves the chat resumable.
    pub(super) async fn force_stop(&mut self, turn_id: Option<&str>) -> HostResult<Value> {
        let active = self.header.session.active_turn_id.clone();
        if turn_id.is_some() && turn_id != active.as_deref() {
            return Err(conflict("turnNotActive", "That turn is no longer running."));
        }
        if active.is_none() && self.provider.is_none() && self.startup.is_none() {
            return Ok(json!({"forceStopped": false}));
        }
        if self
            .native_operation
            .as_ref()
            .is_some_and(super::session_native_history_recovery::native_operation_freezes)
        {
            return Err(conflict(
                "nativeOperationPending",
                "A history operation is still settling; try again once it ends.",
            ));
        }
        self.cancel_startup().await;
        self.revoke_launch_credentials(FORCE_STOP_REASON).await;
        self.deferred_turn = None;
        self.end_subagents_of_process("stopped").await;
        self.awaited_tasks.clear();
        // Never awaited: a provider that ignores Stop may ignore close too.
        drop(self.provider.take());
        self.live_caps = None;
        self.events_armed = false;
        self.stop_notice = Some(StopNotice {
            reason: FORCE_STOP_REASON,
            message: FORCE_STOP_MESSAGE,
        });
        self.finish_turn("interrupted", None, Some(FORCE_STOP_REASON.into()))
            .await;
        self.stop_notice = None;
        self.header.queue.clear();
        self.expire_requests_of_turn(None);
        self.set_status("stopped");
        let recovery = self.stopped_recovery(&format!("{FORCE_STOP_MESSAGE}."));
        self.set_recovery(recovery);
        Ok(json!({"forceStopped": true, "turnId": active}))
    }
}
