pub(super) fn resolve_selection(
    preferred: Option<String>,
    exists: impl Fn(&str) -> bool,
) -> Option<String> {
    // Flutter keeps an absent selection absent. Startup must not activate a
    // pinned/main workspace just because it happens to arrive first.
    preferred.filter(|id| exists(id))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum InitialTerminalAction { Wait, Create, Complete }

pub(super) fn initial_terminal_action(pending: Option<&str>, selected: Option<&str>, has_terminal: bool, busy: bool) -> InitialTerminalAction {
    if pending.is_none() || pending != selected { return InitialTerminalAction::Wait; }
    if has_terminal { return InitialTerminalAction::Complete; }
    if busy { InitialTerminalAction::Wait } else { InitialTerminalAction::Create }
}

pub(super) fn setup_can_start(initial_terminal:InitialTerminalAction,busy:bool)->bool {
    !busy && initial_terminal!=InitialTerminalAction::Create
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_selection_does_not_invent_a_startup_or_removed_target() {
        assert_eq!(resolve_selection(None, |_| true), None);
        assert_eq!(resolve_selection(Some("removed".into()), |_| false), None);
        assert_eq!(resolve_selection(Some("chosen".into()), |id| id == "chosen"), Some("chosen".into()));
    }

    #[test]
    fn manual_workspace_initial_terminal_waits_for_setup_without_losing_intent() {
        assert_eq!(initial_terminal_action(Some("new"),Some("new"),false,true),InitialTerminalAction::Wait);
        assert_eq!(initial_terminal_action(Some("new"),Some("new"),false,false),InitialTerminalAction::Create);
        assert_eq!(initial_terminal_action(Some("new"),Some("new"),true,true),InitialTerminalAction::Complete);
        assert_eq!(initial_terminal_action(None,None,false,false),InitialTerminalAction::Wait);
        assert_eq!(initial_terminal_action(Some("new"),Some("other"),false,false),InitialTerminalAction::Wait);
    }

    #[test]
    fn manual_workspace_setup_waits_for_initial_terminal_but_prompt_agent_is_preserved() {
        let first=initial_terminal_action(Some("new"),Some("new"),false,false);
        assert!(!setup_can_start(first,false));
        let terminal_persisted=initial_terminal_action(Some("new"),Some("new"),true,false);
        assert!(setup_can_start(terminal_persisted,false));
        let prompt_agent=initial_terminal_action(None,Some("new"),true,false);
        assert!(setup_can_start(prompt_agent,false));
        assert!(!setup_can_start(prompt_agent,true));
    }
}
