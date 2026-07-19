use std::collections::HashMap;

use chrono::{DateTime, Utc};

/// Agent state as reported by the Flutter app's agent-status hooks.
/// `Waiting` includes approval and user-input prompts, so it is not safe for
/// auto-submitted injection. Only `Done` means the agent has returned to an
/// empty prompt where push-on-idle delivery can submit text safely.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentPresenceState {
    Working,
    Waiting,
    Blocked,
    Done,
}

impl AgentPresenceState {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "working" => Some(AgentPresenceState::Working),
            "waiting" => Some(AgentPresenceState::Waiting),
            "blocked" => Some(AgentPresenceState::Blocked),
            "done" => Some(AgentPresenceState::Done),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            AgentPresenceState::Working => "working",
            AgentPresenceState::Waiting => "waiting",
            AgentPresenceState::Blocked => "blocked",
            AgentPresenceState::Done => "done",
        }
    }

    /// Only `done` accepts push-on-idle injection: `waiting` can mean an
    /// approval or user-input prompt, where an injected Enter could answer the
    /// prompt instead of submitting a new orchestration message.
    pub fn accepts_injection(self) -> bool {
        matches!(self, AgentPresenceState::Done)
    }
}

#[derive(Debug, Clone)]
pub struct AgentPresence {
    pub agent_type: String,
    pub state: AgentPresenceState,
    pub state_started_at: DateTime<Utc>,
}

/// Last known agent presence per terminal handle, fed by the Flutter app's
/// `orchestration.agentStatus` forwarding. Cleared when a session exits.
#[derive(Debug, Default)]
pub struct AgentPresenceRegistry {
    entries: HashMap<String, AgentPresence>,
}

impl AgentPresenceRegistry {
    /// Records a presence update. Returns true when this update is a
    /// transition into an injection-ready state (used to trigger
    /// push-on-idle delivery).
    #[cfg(test)]
    pub fn update(&mut self, handle: &str, agent_type: String, state: AgentPresenceState) -> bool {
        self.update_at(handle, agent_type, state, Utc::now())
    }

    pub fn update_at(
        &mut self,
        handle: &str,
        agent_type: String,
        state: AgentPresenceState,
        state_started_at: DateTime<Utc>,
    ) -> bool {
        let was_ready = self
            .entries
            .get(handle)
            .map(|entry| entry.state.accepts_injection())
            .unwrap_or(false);
        self.entries.insert(
            handle.to_string(),
            AgentPresence {
                agent_type,
                state,
                state_started_at,
            },
        );
        state.accepts_injection() && !was_ready
    }

    pub fn remove(&mut self, handle: &str) {
        self.entries.remove(handle);
    }

    pub fn get(&self, handle: &str) -> Option<&AgentPresence> {
        self.entries.get(handle)
    }

    pub fn is_injection_ready(&self, handle: &str) -> bool {
        self.entries
            .get(handle)
            .map(|entry| entry.state.accepts_injection())
            .unwrap_or(false)
    }

    pub fn agent_type(&self, handle: &str) -> Option<&str> {
        self.entries
            .get(handle)
            .map(|entry| entry.agent_type.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transition_into_idle_reports_ready() {
        let mut registry = AgentPresenceRegistry::default();
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Waiting));
        // Repeated waiting is not injection-ready.
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Waiting));
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Working));
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Waiting));
        assert!(registry.update("t1", "claude".into(), AgentPresenceState::Done));
        // Repeated done is not a fresh transition.
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Done));
        assert!(!registry.update("t1", "claude".into(), AgentPresenceState::Waiting));

        assert!(!registry.update("t2", "claude".into(), AgentPresenceState::Working));
        assert!(registry.update("t2", "claude".into(), AgentPresenceState::Done));
    }

    #[test]
    fn waiting_blocked_and_working_do_not_accept_injection() {
        let mut registry = AgentPresenceRegistry::default();
        registry.update("t1", "codex".into(), AgentPresenceState::Waiting);
        assert!(!registry.is_injection_ready("t1"));
        registry.update("t1", "codex".into(), AgentPresenceState::Blocked);
        assert!(!registry.is_injection_ready("t1"));
        registry.update("t1", "codex".into(), AgentPresenceState::Working);
        assert!(!registry.is_injection_ready("t1"));
    }

    #[test]
    fn done_accepts_injection() {
        let mut registry = AgentPresenceRegistry::default();
        assert!(registry.update("t1", "codex".into(), AgentPresenceState::Done));
        assert!(registry.is_injection_ready("t1"));
    }

    #[test]
    fn remove_clears_presence() {
        let mut registry = AgentPresenceRegistry::default();
        registry.update("t1", "claude".into(), AgentPresenceState::Waiting);
        registry.remove("t1");
        assert!(registry.get("t1").is_none());
        assert!(!registry.is_injection_ready("t1"));
    }
}
