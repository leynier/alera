use chrono::{DateTime, Duration, Utc};

use crate::terminal_host::orchestration::agent_presence::{AgentPresence, AgentPresenceState};

pub const AGENT_STATUS_IDENTITY_STALE_THRESHOLD: Duration = Duration::minutes(30);

pub struct AgentStatusIdentityResolution {
    pub effective_agent_type: String,
    pub should_ignore_event: bool,
}

pub fn resolve_agent_status_identity(
    previous: Option<&AgentPresence>,
    incoming_agent_type: &str,
    normalized_state: AgentPresenceState,
    received_at: DateTime<Utc>,
    stale_threshold: Duration,
) -> AgentStatusIdentityResolution {
    let inherited_from = previous.filter(|previous| {
        previous.state != AgentPresenceState::Done
            && previous.agent_type != incoming_agent_type
            && !is_stale(previous, received_at, stale_threshold)
            // Claude-compat hooks can land first; a later Grok/Cursor event
            // must take over instead of inheriting Claude for 30 minutes.
            && !(previous.agent_type == "claude" && incoming_agent_type != "claude")
    });
    AgentStatusIdentityResolution {
        effective_agent_type: inherited_from
            .map(|previous| previous.agent_type.clone())
            .unwrap_or_else(|| incoming_agent_type.to_string()),
        should_ignore_event: inherited_from.is_some()
            && normalized_state == AgentPresenceState::Done,
    }
}

fn is_stale(entry: &AgentPresence, received_at: DateTime<Utc>, stale_threshold: Duration) -> bool {
    received_at.signed_duration_since(entry.updated_at) > stale_threshold
}

#[cfg(test)]
mod tests {
    use super::*;

    fn presence(
        agent_type: &str,
        state: AgentPresenceState,
        updated_at: DateTime<Utc>,
    ) -> AgentPresence {
        AgentPresence {
            agent_type: agent_type.to_string(),
            state,
            state_started_at: updated_at,
            updated_at,
            prompt: String::new(),
            tool_name: None,
            tool_input: None,
            last_assistant_message: None,
            interrupted: None,
        }
    }

    #[test]
    fn grok_then_claude_pre_tool_use_keeps_grok() {
        let now = Utc::now();
        let previous = presence("grok", AgentPresenceState::Working, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "claude",
            AgentPresenceState::Working,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "grok");
        assert!(!resolved.should_ignore_event);
    }

    #[test]
    fn grok_working_then_claude_stop_is_ignored() {
        let now = Utc::now();
        let previous = presence("grok", AgentPresenceState::Working, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "claude",
            AgentPresenceState::Done,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "grok");
        assert!(resolved.should_ignore_event);
    }

    #[test]
    fn grok_done_then_claude_turn_becomes_claude() {
        let now = Utc::now();
        let previous = presence("grok", AgentPresenceState::Done, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "claude",
            AgentPresenceState::Working,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "claude");
        assert!(!resolved.should_ignore_event);
    }

    #[test]
    fn cursor_working_then_claude_event_keeps_cursor() {
        let now = Utc::now();
        let previous = presence("cursor", AgentPresenceState::Working, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "claude",
            AgentPresenceState::Working,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "cursor");
        assert!(!resolved.should_ignore_event);
    }

    #[test]
    fn claude_then_grok_takes_over() {
        let now = Utc::now();
        let previous = presence("claude", AgentPresenceState::Working, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "grok",
            AgentPresenceState::Working,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "grok");
        assert!(!resolved.should_ignore_event);
    }

    #[test]
    fn claude_then_cursor_takes_over() {
        let now = Utc::now();
        let previous = presence("claude", AgentPresenceState::Working, now);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "cursor",
            AgentPresenceState::Working,
            now,
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "cursor");
        assert!(!resolved.should_ignore_event);
    }

    #[test]
    fn stale_parent_allows_a_new_identity() {
        let started = Utc::now() - Duration::minutes(31);
        let previous = presence("grok", AgentPresenceState::Working, started);
        let resolved = resolve_agent_status_identity(
            Some(&previous),
            "claude",
            AgentPresenceState::Working,
            Utc::now(),
            AGENT_STATUS_IDENTITY_STALE_THRESHOLD,
        );
        assert_eq!(resolved.effective_agent_type, "claude");
        assert!(!resolved.should_ignore_event);
    }
}
