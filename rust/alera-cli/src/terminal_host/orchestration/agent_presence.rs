use std::collections::HashMap;

use chrono::{DateTime, Utc};

use super::claude_subagent_roster::ClaudeSubagentRoster;

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
    pub updated_at: DateTime<Utc>,
    pub prompt: String,
    pub tool_name: Option<String>,
    pub tool_input: Option<String>,
    pub last_assistant_message: Option<String>,
    pub interrupted: Option<bool>,
    /// Native conversation that produced this presence, so a nested agent the
    /// parent runs as a tool (`codex exec`, `claude -p`) cannot take it over.
    pub native_session_id: Option<String>,
    /// Foreground process group of the PTY when a local hook last fired: the
    /// agent's own group, used to notice the agent exiting back to the shell.
    pub process_group: Option<u32>,
    /// Process id of the agent that reported, when the agent exposes it
    /// (Claude's `CLAUDE_PID`). Tells a relaunched agent from a nested one.
    pub agent_pid: Option<u32>,
    /// The turn a turn-scoped agent (Grok's `promptId`) is running, so a late
    /// report for an older turn cannot end the current one.
    pub turn_id: Option<String>,
    /// Set only by this host's own hook receiver. Relayed and client-reported
    /// presence is reconciled by whoever observed it.
    pub local_hook: bool,
    /// `done` concluded by the host from a silent PTY rather than reported by
    /// the agent. It never accepts injection: the agent may be sitting in a
    /// prompt no hook announced.
    pub inferred_idle: bool,
    /// Claude sub-agents still running or waiting, and the main agent's own
    /// state underneath them. Host memory only, never sent to clients.
    pub claude_subagents: ClaudeSubagentRoster,
}

impl AgentPresence {
    pub fn accepts_injection(&self) -> bool {
        self.state.accepts_injection() && !self.inferred_idle
    }
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

    #[cfg(test)]
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
            .is_some_and(AgentPresence::accepts_injection);
        self.entries.insert(
            handle.to_string(),
            AgentPresence {
                agent_type,
                state,
                state_started_at,
                updated_at: Utc::now(),
                prompt: String::new(),
                tool_name: None,
                tool_input: None,
                last_assistant_message: None,
                interrupted: None,
                native_session_id: None,
                process_group: None,
                agent_pid: None,
                turn_id: None,
                local_hook: false,
                inferred_idle: false,
                claude_subagents: ClaudeSubagentRoster::default(),
            },
        );
        state.accepts_injection() && !was_ready
    }

    pub fn update_full(&mut self, handle: &str, presence: AgentPresence) -> bool {
        let was_ready = self
            .entries
            .get(handle)
            .is_some_and(AgentPresence::accepts_injection);
        let is_ready = presence.accepts_injection();
        self.entries.insert(handle.to_string(), presence);
        is_ready && !was_ready
    }

    pub fn retain_enabled(&mut self, enabled_agents: &[&str]) {
        self.entries
            .retain(|_, entry| enabled_agents.contains(&entry.agent_type.as_str()));
    }

    pub fn get_mut(&mut self, handle: &str) -> Option<&mut AgentPresence> {
        self.entries.get_mut(handle)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &AgentPresence)> {
        self.entries.iter()
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
            .is_some_and(AgentPresence::accepts_injection)
    }

    pub fn agent_type(&self, handle: &str) -> Option<&str> {
        self.entries
            .get(handle)
            .map(|entry| entry.agent_type.as_str())
    }

    pub fn has(&self, handle: &str) -> bool {
        self.entries.contains_key(handle)
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
    fn inferred_idle_never_accepts_injection() {
        let mut registry = AgentPresenceRegistry::default();
        registry.update("t1", "claude".into(), AgentPresenceState::Working);
        let mut inferred = registry.get("t1").unwrap().clone();
        inferred.state = AgentPresenceState::Done;
        inferred.inferred_idle = true;
        assert!(!registry.update_full("t1", inferred));
        assert!(!registry.is_injection_ready("t1"));
        assert!(registry.update("t1", "claude".into(), AgentPresenceState::Done));
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
