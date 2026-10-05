//! Hook routes registered by `alera tab link-agent`.
//!
//! An agent reports through the terminal identity in its launch environment.
//! When that identity no longer names the tab the agent is shown in (a
//! multiplexer server started from another tab, a restored terminal), its
//! hooks are dropped. A link sends the hooks of one agent, recognized by its
//! conversation id or process id, from the terminal its environment names to
//! the terminal of the tab it was linked to.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentHookLink {
    pub source_terminal_session_id: String,
    pub agent_type: String,
    pub native_session_id: Option<String>,
    pub agent_pid: Option<u32>,
    pub target_terminal_session_id: String,
}

#[derive(Debug, Default)]
pub struct AgentHookLinks {
    links: Vec<AgentHookLink>,
}

impl AgentHookLinks {
    /// A tab shows one agent, so a new link replaces every route into the
    /// same terminal and any older route for the same agent.
    pub fn link(&mut self, link: AgentHookLink) {
        self.links.retain(|existing| {
            existing.target_terminal_session_id != link.target_terminal_session_id
                && !(existing.source_terminal_session_id == link.source_terminal_session_id
                    && existing.agent_type == link.agent_type
                    && identifies_same_agent(
                        existing,
                        link.native_session_id.as_deref(),
                        link.agent_pid,
                    ))
        });
        self.links.push(link);
    }

    /// Routes into this terminal are dropped, for example when the agent was
    /// linked again from inside the tab itself.
    pub fn unlink_target(&mut self, target_terminal_session_id: &str) {
        self.links
            .retain(|link| link.target_terminal_session_id != target_terminal_session_id);
    }

    pub fn retain_targets(&mut self, mut keep: impl FnMut(&str) -> bool) {
        self.links
            .retain(|link| keep(&link.target_terminal_session_id));
    }

    /// The terminal a hook from `source_terminal_session_id` belongs to.
    ///
    /// A match on the process id adopts the conversation the hook names: a
    /// Claude `/clear` starts a new conversation in the same process.
    pub fn target_for(
        &mut self,
        source_terminal_session_id: &str,
        agent_type: &str,
        native_session_id: Option<&str>,
        agent_pid: Option<u32>,
    ) -> Option<String> {
        let link = self.links.iter_mut().find(|link| {
            link.source_terminal_session_id == source_terminal_session_id
                && link.agent_type == agent_type
                && identifies_same_agent(link, native_session_id, agent_pid)
        })?;
        if let Some(native_session_id) = native_session_id {
            link.native_session_id = Some(native_session_id.to_string());
        }
        Some(link.target_terminal_session_id.clone())
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.links.len()
    }
}

fn identifies_same_agent(
    link: &AgentHookLink,
    native_session_id: Option<&str>,
    agent_pid: Option<u32>,
) -> bool {
    let same_pid = matches!((link.agent_pid, agent_pid), (Some(a), Some(b)) if a == b);
    let same_session = matches!(
        (link.native_session_id.as_deref(), native_session_id),
        (Some(a), Some(b)) if a == b
    );
    same_pid || same_session
}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(source: &str, target: &str, session: Option<&str>, pid: Option<u32>) -> AgentHookLink {
        AgentHookLink {
            source_terminal_session_id: source.to_string(),
            agent_type: "claude".to_string(),
            native_session_id: session.map(str::to_string),
            agent_pid: pid,
            target_terminal_session_id: target.to_string(),
        }
    }

    #[test]
    fn routes_only_the_linked_agent_from_its_source_terminal() {
        let mut links = AgentHookLinks::default();
        links.link(link("old", "new", Some("conv-1"), None));

        assert_eq!(
            links.target_for("old", "claude", Some("conv-1"), None),
            Some("new".to_string())
        );
        assert_eq!(
            links.target_for("old", "claude", Some("conv-2"), None),
            None
        );
        assert_eq!(links.target_for("old", "codex", Some("conv-1"), None), None);
        assert_eq!(
            links.target_for("other", "claude", Some("conv-1"), None),
            None
        );
    }

    #[test]
    fn a_process_match_adopts_the_next_conversation() {
        let mut links = AgentHookLinks::default();
        links.link(link("old", "new", Some("conv-1"), Some(42)));

        assert_eq!(
            links.target_for("old", "claude", Some("conv-2"), Some(42)),
            Some("new".to_string())
        );
        assert_eq!(
            links.target_for("old", "claude", Some("conv-2"), None),
            Some("new".to_string())
        );
        assert_eq!(
            links.target_for("old", "claude", Some("conv-1"), Some(7)),
            None
        );
    }

    #[test]
    fn relinking_replaces_routes_into_the_same_terminal_and_for_the_same_agent() {
        let mut links = AgentHookLinks::default();
        links.link(link("old", "new", Some("conv-1"), None));
        links.link(link("older", "new", Some("conv-2"), None));
        assert_eq!(links.len(), 1);
        assert_eq!(
            links.target_for("old", "claude", Some("conv-1"), None),
            None
        );

        links.link(link("older", "other", Some("conv-2"), None));
        assert_eq!(links.len(), 1);
        assert_eq!(
            links.target_for("older", "claude", Some("conv-2"), None),
            Some("other".to_string())
        );
    }

    #[test]
    fn dropping_a_target_removes_its_routes() {
        let mut links = AgentHookLinks::default();
        links.link(link("old", "new", Some("conv-1"), None));
        links.link(link("old", "kept", Some("conv-2"), None));

        links.retain_targets(|target| target != "new");
        assert_eq!(
            links.target_for("old", "claude", Some("conv-1"), None),
            None
        );
        links.unlink_target("kept");
        assert_eq!(links.len(), 0);
    }
}
