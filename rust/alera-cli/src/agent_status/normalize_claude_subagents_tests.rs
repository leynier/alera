use chrono::Utc;
use serde_json::{json, Value};

use super::*;

fn event(name: &str, payload: Value) -> AgentHookEvent {
    AgentHookEvent {
        terminal_session_id: "session-1".into(),
        workspace_id: "workspace-1".into(),
        tab_id: "tab-1".into(),
        agent_type: "claude".into(),
        event_name: Some(name.into()),
        payload,
    }
}

fn presence(state: AgentPresenceState, roster: &ClaudeSubagentRoster) -> AgentPresence {
    AgentPresence {
        agent_type: "claude".into(),
        state,
        state_started_at: Utc::now(),
        updated_at: Utc::now(),
        prompt: "Review the branch".into(),
        tool_name: Some("Task".into()),
        tool_input: None,
        last_assistant_message: Some("Waiting for the reviewers".into()),
        interrupted: None,
        native_session_id: None,
        process_group: None,
        agent_pid: None,
        turn_id: None,
        local_hook: true,
        inferred_idle: false,
        claude_subagents: roster.clone(),
    }
}

/// Feeds events through the normalizer the way the host does, keeping the
/// shown state as `previous` for the next one.
struct Tab {
    roster: ClaudeSubagentRoster,
    shown: Option<AgentPresence>,
}

impl Tab {
    fn new() -> Self {
        Self {
            roster: ClaudeSubagentRoster::default(),
            shown: None,
        }
    }

    fn send(&mut self, name: &str, payload: Value) -> Option<NormalizedAgentStatus> {
        let status = normalize_claude_hook_event(
            &event(name, payload),
            self.shown.as_ref(),
            &mut self.roster,
        );
        if let Some(status) = &status {
            let mut next = presence(status.state, &self.roster);
            next.prompt = status.prompt.clone();
            next.last_assistant_message = status.last_assistant_message.clone();
            self.shown = Some(next);
        }
        status
    }

    fn state(&self) -> Option<AgentPresenceState> {
        self.shown.as_ref().map(|entry| entry.state)
    }
}

#[test]
fn a_stop_that_waits_for_background_sub_agents_is_not_done() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({"prompt": "Review the branch"}));
    tab.send(
        "SubagentStart",
        json!({"agent_id": "a1", "agent_type": "Explore"}),
    );
    tab.send("SubagentStart", json!({"agent_id": "a2"}));
    tab.send("Stop", json!({"session_id": "s"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));

    tab.send("SubagentStop", json!({"agent_id": "a1"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
    let done = tab.send("SubagentStop", json!({"agent_id": "a2"})).unwrap();
    assert_eq!(done.state, AgentPresenceState::Done);
    assert!(!done.inferred_idle);
    assert_eq!(done.prompt, "Review the branch");
}

#[test]
fn a_sub_agent_question_shows_waiting_even_after_the_main_turn_ended() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("Stop", json!({}));
    tab.send(
        "PermissionRequest",
        json!({"agent_id": "a1", "tool_name": "Bash"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Waiting));

    tab.send(
        "PostToolUse",
        json!({"agent_id": "a1", "tool_name": "Bash"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
    tab.send("SubagentStop", json!({"agent_id": "a1"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
}

#[test]
fn answering_a_childs_prompt_after_the_main_stop_still_ends_in_done() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("Stop", json!({}));
    tab.send(
        "Notification",
        json!({"notification_type": "permission_prompt"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Waiting));
    tab.send(
        "PostToolUse",
        json!({"agent_id": "a1", "tool_name": "Bash"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
    let done = tab.send("SubagentStop", json!({"agent_id": "a1"})).unwrap();
    assert_eq!(done.state, AgentPresenceState::Done);
    assert!(!done.inferred_idle);
}

#[test]
fn a_child_resuming_clears_the_notification_that_announced_its_prompt() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send(
        "Notification",
        json!({"notification_type": "permission_prompt"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Waiting));
    tab.send(
        "PostToolUse",
        json!({"agent_id": "a1", "tool_name": "Bash"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
}

#[test]
fn a_late_hook_from_a_finished_child_does_not_reopen_the_turn() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("SubagentStop", json!({"agent_id": "a1"}));
    tab.send("Stop", json!({}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
    assert!(tab
        .send(
            "PostToolUse",
            json!({"agent_id": "a1", "tool_name": "Read"}),
        )
        .is_none());
    assert!(tab
        .send(
            "PermissionRequest",
            json!({"agent_id": "a1", "tool_name": "Bash"}),
        )
        .is_none());
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
}

#[test]
fn a_child_working_leaves_the_main_agents_own_prompt_up() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("PermissionRequest", json!({"tool_name": "Bash"}));
    tab.send(
        "Notification",
        json!({"notification_type": "permission_prompt"}),
    );
    tab.send(
        "PostToolUse",
        json!({"agent_id": "a1", "tool_name": "Read"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Waiting));
    tab.send("PostToolUse", json!({"tool_name": "Bash"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
}

#[test]
fn a_question_from_a_child_the_full_roster_could_not_track_still_shows() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    for index in 0..40 {
        tab.send("SubagentStart", json!({"agent_id": format!("a{index}")}));
    }
    tab.send(
        "PreToolUse",
        json!({"agent_id": "a39", "tool_name": "AskUserQuestion"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Waiting));
    tab.send(
        "PostToolUse",
        json!({"agent_id": "a39", "tool_name": "AskUserQuestion"}),
    );
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
}

#[test]
fn a_sibling_stop_inventory_drops_a_child_whose_own_stop_was_lost() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("SubagentStart", json!({"agent_id": "a2"}));
    tab.send("Stop", json!({}));
    let inventory = json!({
        "agent_id": "a2",
        "background_tasks": [{"id": "a2", "type": "subagent", "status": "running"}],
    });
    tab.send("SubagentStop", inventory);
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
}

#[test]
fn an_interrupted_turn_drops_its_children_until_one_reports_again() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send(
        "PostToolUseFailure",
        json!({"tool_name": "Task", "is_interrupt": true}),
    );
    let done = tab.shown.clone().unwrap();
    assert_eq!(done.state, AgentPresenceState::Done);

    // A background child survives Esc and speaks up on its next tool call.
    tab.send("PreToolUse", json!({"agent_id": "a1", "tool_name": "Grep"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Working));
}

#[test]
fn the_stop_inventory_ends_a_turn_whose_sub_agent_stop_was_lost() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("Stop", json!({"background_tasks": []}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
}

#[test]
fn a_new_conversation_forgets_the_previous_ones_children() {
    let mut tab = Tab::new();
    tab.send("UserPromptSubmit", json!({}));
    tab.send("SubagentStart", json!({"agent_id": "a1"}));
    tab.send("SessionStart", json!({"source": "clear"}));
    assert_eq!(tab.state(), Some(AgentPresenceState::Done));
}

#[test]
fn a_sub_agent_hook_with_nothing_shown_creates_no_presence() {
    let mut tab = Tab::new();
    assert!(tab
        .send("SubagentStart", json!({"agent_id": "a1"}))
        .is_none());
    assert!(tab
        .send("SubagentStop", json!({"agent_id": "a1"}))
        .is_none());
    assert!(tab
        .send(
            "PostToolUse",
            json!({"agent_id": "a1", "tool_name": "Read"})
        )
        .is_none());
}
