use super::agent_presence::AgentPresenceRegistry;

/// Agent-name groups matched against the presence registry's agent type
/// (reported by the app's agent-status hooks), not terminal titles.
const AGENT_NAME_GROUPS: &[&str] = &[
    "claude", "codex", "copilot", "cursor", "agy", "opencode", "opencode2", "pi", "amp",
];

/// A live terminal candidate for group resolution.
pub struct GroupResolutionTerminal {
    pub handle: String,
    pub workspace_id: Option<String>,
}

pub fn is_group_address(to: &str) -> bool {
    to.starts_with('@')
}

/// Resolves a recipient address to concrete terminal handles at send time:
/// one message record per recipient (same thread), so each recipient keeps
/// independent read tracking. Unknown groups resolve to empty rather than
/// erroring so callers can distinguish "valid group, no current members"
/// from programming errors.
pub fn resolve_group_address(
    to: &str,
    sender_handle: &str,
    terminals: &[GroupResolutionTerminal],
    presence: &AgentPresenceRegistry,
) -> Vec<String> {
    if !is_group_address(to) {
        return vec![to.to_string()];
    }
    let group = to.to_lowercase();

    if group == "@all" {
        // Broadcast to every terminal except the sender to avoid
        // self-delivery loops.
        return terminals
            .iter()
            .filter(|terminal| terminal.handle != sender_handle)
            .map(|terminal| terminal.handle.clone())
            .collect();
    }

    if group == "@idle" {
        // Only agents whose presence reports an injection-ready state,
        // useful for dispatching to available agents without interrupting
        // busy ones.
        return terminals
            .iter()
            .filter(|terminal| {
                terminal.handle != sender_handle && presence.is_injection_ready(&terminal.handle)
            })
            .map(|terminal| terminal.handle.clone())
            .collect();
    }

    if let Some(workspace_id) = group.strip_prefix("@workspace:") {
        // Preserve the original casing of the id from the raw address.
        let raw_id = &to["@workspace:".len()..];
        let _ = workspace_id;
        return terminals
            .iter()
            .filter(|terminal| {
                terminal.handle != sender_handle && terminal.workspace_id.as_deref() == Some(raw_id)
            })
            .map(|terminal| terminal.handle.clone())
            .collect();
    }

    let agent_name = &group[1..];
    if AGENT_NAME_GROUPS.contains(&agent_name) {
        return terminals
            .iter()
            .filter(|terminal| {
                terminal.handle != sender_handle
                    && presence.agent_type(&terminal.handle) == Some(agent_name)
            })
            .map(|terminal| terminal.handle.clone())
            .collect();
    }

    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::super::agent_presence::AgentPresenceState;
    use super::*;

    fn terminal(handle: &str, workspace: Option<&str>) -> GroupResolutionTerminal {
        GroupResolutionTerminal {
            handle: handle.to_string(),
            workspace_id: workspace.map(str::to_string),
        }
    }

    fn presence_with(entries: &[(&str, &str, AgentPresenceState)]) -> AgentPresenceRegistry {
        let mut registry = AgentPresenceRegistry::default();
        for (handle, agent, state) in entries {
            registry.update(handle, (*agent).to_string(), *state);
        }
        registry
    }

    #[test]
    fn point_to_point_passes_through() {
        let handles =
            resolve_group_address("term_x", "term_a", &[], &AgentPresenceRegistry::default());
        assert_eq!(handles, vec!["term_x".to_string()]);
    }

    #[test]
    fn all_excludes_sender() {
        let terminals = [
            terminal("a", None),
            terminal("b", None),
            terminal("c", None),
        ];
        let handles =
            resolve_group_address("@all", "b", &terminals, &AgentPresenceRegistry::default());
        assert_eq!(handles, vec!["a".to_string(), "c".to_string()]);
    }

    #[test]
    fn idle_uses_presence_registry() {
        let terminals = [
            terminal("a", None),
            terminal("b", None),
            terminal("c", None),
        ];
        let presence = presence_with(&[
            ("a", "claude", AgentPresenceState::Waiting),
            ("b", "claude", AgentPresenceState::Done),
            ("c", "claude", AgentPresenceState::Working),
        ]);
        let handles = resolve_group_address("@idle", "sender", &terminals, &presence);
        assert_eq!(handles, vec!["b".to_string()]);
    }

    #[test]
    fn workspace_group_filters_by_workspace_id() {
        let terminals = [
            terminal("a", Some("ws-1")),
            terminal("b", Some("ws-2")),
            terminal("c", Some("ws-1")),
        ];
        let handles = resolve_group_address(
            "@workspace:ws-1",
            "c",
            &terminals,
            &AgentPresenceRegistry::default(),
        );
        assert_eq!(handles, vec!["a".to_string()]);
    }

    #[test]
    fn agent_group_matches_presence_agent_type() {
        let terminals = [
            terminal("a", None),
            terminal("b", None),
            terminal("c", None),
        ];
        let presence = presence_with(&[
            ("a", "claude", AgentPresenceState::Working),
            ("b", "codex", AgentPresenceState::Waiting),
        ]);
        let claude = resolve_group_address("@claude", "sender", &terminals, &presence);
        assert_eq!(claude, vec!["a".to_string()]);
        let codex = resolve_group_address("@codex", "sender", &terminals, &presence);
        assert_eq!(codex, vec!["b".to_string()]);
    }

    #[test]
    fn unknown_group_resolves_to_empty() {
        let terminals = [terminal("a", None)];
        let handles = resolve_group_address(
            "@nonsense",
            "sender",
            &terminals,
            &AgentPresenceRegistry::default(),
        );
        assert!(handles.is_empty());
    }
}
