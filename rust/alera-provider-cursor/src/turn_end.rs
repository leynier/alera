//! How a Cursor run's terminal frame ends the turn.

use super::CursorProvider;
use alera_provider_protocol::{EventKind, ProviderError, ProviderEvent, TurnStatus};
use cursor_agent_sdk::RunStreamMessage;
use serde_json::Value;

/// After a turn ends, a retryable stream error can make Cursor's SDK resume
/// the run from an older checkpoint. When those resumes save nothing, it ends
/// the run with this error although the answer was already delivered.
const RESUME_NO_PROGRESS_MESSAGE: &str =
    "Agent turn stopped after repeated resume attempts made no progress";

impl CursorProvider {
    /// Tracks whether the agent's latest turn ended with no new work since.
    pub(super) fn track_turn_end(&mut self, message: &RunStreamMessage) {
        let Some(update) = message.interaction_update.as_ref() else {
            return;
        };
        match update.get("type").and_then(Value::as_str) {
            Some("turn-ended") => self.turn_ended = true,
            Some(
                "step-started"
                | "user-message-appended"
                | "text-delta"
                | "thinking-delta"
                | "partial-tool-call"
                | "tool-call-started",
            ) => self.turn_ended = false,
            _ => {}
        }
    }

    /// Completes a run's terminal events. The last failed status names a
    /// failure the result left blank, and a resume that failed after the turn
    /// already ended does not fail it.
    pub(super) fn settle_terminal_events(
        &self,
        events: &mut Vec<ProviderEvent>,
    ) -> Result<(), ProviderError> {
        if let Some(message) = self.last_status_error_message.as_deref() {
            for event in events.iter_mut() {
                if event.kind == EventKind::TurnCompleted
                    && message_type(event) == Some("result")
                    && event.payload.get("errorMessage").is_none()
                {
                    event.payload["errorMessage"] = Value::String(message.to_owned());
                    event.validate()?;
                }
            }
        }
        if !self.turn_ended {
            return Ok(());
        }
        let mut settled = false;
        for event in events.iter_mut() {
            match event.kind {
                EventKind::RuntimeError if is_late_resume(event.payload.get("message")) => {
                    event.kind = EventKind::ThreadStateChanged;
                }
                EventKind::TurnCompleted
                    if event.payload["state"] == "failed"
                        && is_late_resume(event.payload.get("errorMessage")) =>
                {
                    event.payload["state"] = serde_json::json!(TurnStatus::Completed);
                    if let Some(payload) = event.payload.as_object_mut() {
                        for key in ["errorMessage", "errorCode", "failureClass"] {
                            payload.remove(key);
                        }
                    }
                    event.validate()?;
                    settled = true;
                }
                _ => {}
            }
        }
        if settled {
            // Text from a resume that made no progress is not the turn's answer.
            events.retain(|event| {
                event.kind != EventKind::ContentDelta || message_type(event) != Some("result")
            });
        }
        Ok(())
    }
}

fn message_type(event: &ProviderEvent) -> Option<&str> {
    event.raw.as_ref()?.message_type.as_deref()
}

fn is_late_resume(message: Option<&Value>) -> bool {
    message.and_then(Value::as_str) == Some(RESUME_NO_PROGRESS_MESSAGE)
}
