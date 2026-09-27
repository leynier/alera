use serde_json::Value;

use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::orchestration::agent_session_resume::hook_identifies_parent_session;

use super::hook_receiver::{AGENT_PID_PAYLOAD_KEY, MULTIPLEXER_PAYLOAD_KEY};
use super::normalize::{bool_field, first_string, normalized_event_name};
use super::AgentHookEvent;

/// The agent process is gone. Claude also ends a session on `/clear` and
/// `/resume`, where the same process carries on with another conversation.
pub fn hook_event_closes_session(event: &AgentHookEvent) -> bool {
    let Some(event_name) = normalized_event_name(event) else {
        return false;
    };
    match (event.agent_type.as_str(), event_name.as_str()) {
        ("claude", "SessionEnd") => !claude_switches_conversation(event),
        (agent, name) => matches!(
            (agent, name),
            ("copilot", "SessionEnd")
                | ("cursor", "sessionEnd")
                | ("pi", "session_shutdown")
                | ("grok", "SessionEnd")
                | ("fx", "SessionEnd")
                | ("codex", "SessionEnd")
        ),
    }
}

pub fn hook_event_resets_session(event: &AgentHookEvent) -> bool {
    event.agent_type == "grok" && normalized_event_name(event).as_deref() == Some("SessionStart")
}

/// Claude announces a fresh, cleared or forked conversation before it has
/// written a transcript, and `--resume` of that id fails. Only a conversation
/// the user has spoken in, or one Claude itself resumed, may be bound.
pub fn hook_event_starts_unsaved_session(event: &AgentHookEvent) -> bool {
    event.agent_type == "claude"
        && normalized_event_name(event).as_deref() == Some("SessionStart")
        && !matches!(
            payload_str(&event.payload, "source"),
            Some("resume" | "compact")
        )
}

/// Hooks fired inside a sub-agent. Claude and Codex keep the root
/// `session_id` and add `agent_id`; Grok gives the child its own session and
/// tags it `subagentType`; OpenCode and older Codex name the parent.
pub fn hook_identifies_child_agent(event: &AgentHookEvent) -> bool {
    hook_identifies_parent_session(&event.payload)
        || payload_str(&event.payload, "subagentType").is_some()
        || (matches!(event.agent_type.as_str(), "claude" | "codex")
            && payload_str(&event.payload, "agent_id").is_some())
}

pub fn event_agent_pid(payload: &Value) -> Option<u32> {
    payload
        .get(AGENT_PID_PAYLOAD_KEY)
        .and_then(Value::as_u64)
        .and_then(|pid| u32::try_from(pid).ok())
        .filter(|pid| *pid > 1)
}

/// The hook ran inside tmux, screen or zellij, where the tab's PTY shows the
/// multiplexer client rather than the agent.
pub fn event_runs_in_multiplexer(payload: &Value) -> bool {
    payload_str(payload, MULTIPLEXER_PAYLOAD_KEY).is_some()
}

/// Grok queues turn-end reports behind one worker, so a cancelled turn's
/// report can land after the next prompt; `promptId` says which turn it is.
pub fn event_turn_id(event: &AgentHookEvent) -> Option<&str> {
    (event.agent_type == "grok")
        .then(|| payload_str(&event.payload, "promptId"))
        .flatten()
}

pub(super) fn is_interrupt(payload: &Value) -> bool {
    bool_field(payload, "is_interrupt") == Some(true)
        || bool_field(payload, "isInterrupt") == Some(true)
}

pub(super) fn notification_type(payload: &Value) -> Option<String> {
    first_string(payload, &["notification_type", "notificationType"])
}

/// Claude and Grok send `idle_prompt` once input has sat idle for a minute,
/// which is the only signal after an interrupt no hook reported. It replaces
/// a host-inferred `done` with a confirmed one. From `waiting` the result is
/// still marked inferred by the caller: the prompt may belong to a dialog.
pub(super) fn idle_notification_state(
    payload: &Value,
    previous: Option<&AgentPresence>,
) -> Option<AgentPresenceState> {
    match notification_type(payload).as_deref() {
        Some("idle_prompt") => previous
            .filter(|entry| match entry.state {
                AgentPresenceState::Working | AgentPresenceState::Waiting => true,
                AgentPresenceState::Done => entry.inferred_idle,
                AgentPresenceState::Blocked => false,
            })
            .map(|_| AgentPresenceState::Done),
        Some(
            "permission_prompt"
            | "elicitation_dialog"
            | "elicitation_url_dialog"
            | "worker_permission_prompt",
        ) => Some(AgentPresenceState::Waiting),
        _ => None,
    }
}

/// A new conversation in a running Claude leaves it idle at its prompt. It
/// never creates presence for an agent nobody has used yet, and `compact` is
/// the same conversation continuing.
pub(super) fn claude_lifecycle_state(
    event: &AgentHookEvent,
    name: &str,
    previous: Option<&AgentPresence>,
) -> Option<AgentPresenceState> {
    previous?;
    let idle = match name {
        "SessionStart" => payload_str(&event.payload, "source") != Some("compact"),
        "SessionEnd" => claude_switches_conversation(event),
        _ => false,
    };
    idle.then_some(AgentPresenceState::Done)
}

fn claude_switches_conversation(event: &AgentHookEvent) -> bool {
    matches!(
        payload_str(&event.payload, "reason"),
        Some("clear" | "resume")
    )
}

fn payload_str<'a>(payload: &'a Value, key: &str) -> Option<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}
