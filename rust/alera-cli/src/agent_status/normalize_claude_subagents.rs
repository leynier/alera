use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};
use crate::terminal_host::orchestration::claude_subagent_roster::{
    ClaudeSubagentRoster, Observed, SubagentState,
};

use super::normalize::{
    first_string, normalize_hook_event, normalized_event_name, NormalizedAgentStatus,
};
use super::AgentHookEvent;

/// Claude's status once its sub-agents are counted. The main agent's own
/// hooks set the state underneath; a child keeps a finished turn `working`
/// until it stops, and a child's question shows as `waiting`. Returns `None`
/// when the tab's shown state does not change, though `roster` may have.
pub fn normalize_claude_hook_event(
    event: &AgentHookEvent,
    previous: Option<&AgentPresence>,
    roster: &mut ClaudeSubagentRoster,
) -> Option<NormalizedAgentStatus> {
    let name = normalized_event_name(event)?;
    let Some(id) = first_string(&event.payload, &["agent_id"]) else {
        let normalized = normalize_hook_event(event, previous)?;
        return Some(lead_status(event, &name, normalized, roster));
    };
    // A child never creates the tab's presence: only the main agent's hooks
    // record the process the exit and silence sweeps watch.
    previous?;
    match name.as_str() {
        "SubagentStart" => {
            roster.start(&id);
            return Some(carried_status(roster, previous));
        }
        "SubagentStop" => {
            roster.finish(&id);
            // Finished first, so an inventory still listing it cannot revive it.
            if event.payload.get("background_tasks").is_some() {
                roster.reconcile_background_tasks(&event.payload);
            }
            return Some(carried_status(roster, previous));
        }
        _ => {}
    }
    let normalized = normalize_hook_event(event, previous)?;
    let observed = match normalized.state {
        // Only an interrupted tool call inside the child reads as done: the
        // interrupt stopped it.
        AgentPresenceState::Done => {
            roster.finish(&id);
            Observed::Tracked
        }
        AgentPresenceState::Working => roster.observe(&id, SubagentState::Working),
        AgentPresenceState::Waiting | AgentPresenceState::Blocked => {
            roster.observe(&id, SubagentState::Waiting)
        }
    };
    match (observed, normalized.state) {
        (Observed::Finished, _) => return None,
        (_, AgentPresenceState::Working) => roster.child_resumed_lead(),
        (Observed::Untracked, AgentPresenceState::Waiting | AgentPresenceState::Blocked) => {
            roster.raise_attention_a_child_may_answer(normalized.state);
        }
        _ => {}
    }
    Some(NormalizedAgentStatus {
        state: roster.effective_state(),
        interrupted: shown_interrupted(roster),
        inferred_idle: shown_inferred_idle(roster),
        ..normalized
    })
}

fn lead_status(
    event: &AgentHookEvent,
    name: &str,
    normalized: NormalizedAgentStatus,
    roster: &mut ClaudeSubagentRoster,
) -> NormalizedAgentStatus {
    if normalized.state == AgentPresenceState::Done {
        let new_conversation = matches!(name, "SessionStart" | "SessionEnd");
        if event.payload.get("background_tasks").is_some() {
            roster.reconcile_background_tasks(&event.payload);
        } else if new_conversation || normalized.interrupted == Some(true) {
            roster.clear_active();
        }
    }
    let attention = matches!(
        normalized.state,
        AgentPresenceState::Waiting | AgentPresenceState::Blocked
    );
    if attention && name == "Notification" {
        roster.raise_attention_a_child_may_answer(normalized.state);
    } else {
        roster.set_lead(
            normalized.state,
            normalized.interrupted,
            normalized.inferred_idle,
        );
    }
    NormalizedAgentStatus {
        state: roster.effective_state(),
        interrupted: shown_interrupted(roster),
        inferred_idle: shown_inferred_idle(roster),
        ..normalized
    }
}

/// A child's start or stop changes nothing the main agent reported, so the
/// prompt, tool and message it last showed stay.
fn carried_status(
    roster: &ClaudeSubagentRoster,
    previous: Option<&AgentPresence>,
) -> NormalizedAgentStatus {
    NormalizedAgentStatus {
        state: roster.effective_state(),
        prompt: previous
            .map(|entry| entry.prompt.clone())
            .unwrap_or_default(),
        tool_name: previous.and_then(|entry| entry.tool_name.clone()),
        tool_input: previous.and_then(|entry| entry.tool_input.clone()),
        last_assistant_message: previous.and_then(|entry| entry.last_assistant_message.clone()),
        interrupted: shown_interrupted(roster),
        inferred_idle: shown_inferred_idle(roster),
    }
}

fn shown_interrupted(roster: &ClaudeSubagentRoster) -> Option<bool> {
    (roster.effective_state() == AgentPresenceState::Done)
        .then(|| roster.lead_interrupted())
        .flatten()
}

fn shown_inferred_idle(roster: &ClaudeSubagentRoster) -> bool {
    roster.effective_state() == AgentPresenceState::Done && roster.lead_inferred_idle()
}

#[cfg(test)]
#[path = "normalize_claude_subagents_tests.rs"]
mod tests;
