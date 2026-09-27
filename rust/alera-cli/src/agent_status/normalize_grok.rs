use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};

use super::normalize::first_string;
use super::normalize_lifecycle::{idle_notification_state, notification_type};
use super::AgentHookEvent;

pub(super) fn normalize_grok(
    event: &AgentHookEvent,
    name: &str,
    previous: Option<&AgentPresence>,
) -> Option<AgentPresenceState> {
    // Grok documents `notificationType` as the stable field; `message` is
    // display text kept only as a fallback for releases without the type.
    if name == "Notification" && notification_type(&event.payload).is_some() {
        return idle_notification_state(&event.payload, previous);
    }
    if name == "Notification" {
        let message = first_string(&event.payload, &["message"])?.to_ascii_lowercase();
        if [
            "type your message",
            "enter send",
            "shift-tab normal",
            "ask a side question",
        ]
        .iter()
        .any(|needle| message.contains(needle))
        {
            return Some(AgentPresenceState::Done);
        }
        if [
            "permission",
            "approval",
            "approve",
            "allow",
            "confirm",
            "feedback",
            "question",
        ]
        .iter()
        .any(|needle| message.contains(needle))
        {
            return Some(AgentPresenceState::Waiting);
        }
        return None;
    }
    match name {
        "UserPromptSubmit" | "PreToolUse" | "PostToolUse" | "PostToolUseFailure" => {
            Some(AgentPresenceState::Working)
        }
        // `StopCancelled` replaces `Stop` for Ctrl+C, a declined permission,
        // the turn limit and a no-progress bail-out.
        "Stop" | "StopFailure" | "StopCancelled" | "SessionEnd" => Some(AgentPresenceState::Done),
        _ => None,
    }
}
