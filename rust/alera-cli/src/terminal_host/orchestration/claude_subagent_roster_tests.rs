use serde_json::json;

use super::*;

fn done_lead() -> ClaudeSubagentRoster {
    let mut roster = ClaudeSubagentRoster::default();
    roster.set_lead(AgentPresenceState::Done, None, false);
    roster
}

#[test]
fn a_finished_main_turn_stays_working_until_its_children_finish() {
    let mut roster = done_lead();
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);

    roster.start("a1");
    roster.start("a2");
    assert_eq!(roster.effective_state(), AgentPresenceState::Working);
    assert!(roster.holds_finished_turn_open());

    roster.finish("a1");
    assert_eq!(roster.effective_state(), AgentPresenceState::Working);
    roster.finish("a2");
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);
    assert!(!roster.holds_finished_turn_open());
}

#[test]
fn a_child_question_asks_for_attention_until_the_child_resumes() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.start("a2");
    assert!(roster.observe("a1", SubagentState::Waiting));
    assert_eq!(roster.effective_state(), AgentPresenceState::Waiting);

    assert!(roster.observe("a1", SubagentState::Working));
    assert_eq!(roster.effective_state(), AgentPresenceState::Working);

    roster.observe("a2", SubagentState::Waiting);
    roster.finish("a2");
    roster.finish("a1");
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);
}

#[test]
fn main_agent_attention_wins_over_child_work() {
    let mut roster = ClaudeSubagentRoster::default();
    roster.start("a1");
    roster.set_lead(AgentPresenceState::Waiting, None, false);
    assert_eq!(roster.effective_state(), AgentPresenceState::Waiting);

    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Working);

    roster.set_lead(AgentPresenceState::Done, None, false);
    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Done);
}

#[test]
fn a_late_hook_from_a_finished_child_does_not_revive_it() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.finish("a1");
    assert!(!roster.observe("a1", SubagentState::Working));
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);

    // A teammate's next turn starts explicitly and reuses its id.
    roster.start("a1");
    assert_eq!(roster.effective_state(), AgentPresenceState::Working);
}

#[test]
fn the_stop_inventory_drops_lost_children_and_adopts_unseen_ones() {
    let mut roster = done_lead();
    roster.start("alost");
    roster.start("areviewer-1a2b");
    roster.reconcile_background_tasks(&json!({
        "background_tasks": [
            {"id": "aunseen", "type": "subagent", "status": "running"},
            {"id": "adone", "type": "subagent", "status": "completed"},
            {"id": "shell-1", "type": "shell", "status": "running"},
        ]
    }));
    assert_eq!(roster.active_count(), 1);
    assert!(!roster.observe("alost", SubagentState::Working));
    assert!(!roster.observe("adone", SubagentState::Working));
    assert!(roster.has_working());

    roster.reconcile_background_tasks(&json!({"background_tasks": []}));
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);
}

#[test]
fn listed_teammates_keep_their_unlisted_lifecycle_ids() {
    let mut roster = done_lead();
    roster.start("areviewer-1a2b");
    roster.start("a0f9e8");
    roster.reconcile_background_tasks(&json!({
        "background_tasks": [{"id": "t1", "type": "teammate", "status": "running"}]
    }));
    assert_eq!(roster.active_count(), 1);
    assert!(roster.has_working());
}

#[test]
fn a_missing_inventory_leaves_the_roster_alone() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.reconcile_background_tasks(&json!({"stop_hook_active": false}));
    assert_eq!(roster.effective_state(), AgentPresenceState::Working);
}

#[test]
fn tracking_is_bounded() {
    let mut roster = done_lead();
    for index in 0..(MAX_ACTIVE_SUBAGENTS + 5) {
        roster.start(&format!("a{index}"));
    }
    assert_eq!(roster.active_count(), MAX_ACTIVE_SUBAGENTS);
    for index in 0..(MAX_FINISHED_SUBAGENTS + 5) {
        roster.finish(&format!("b{index}"));
    }
    assert_eq!(roster.finished.len(), MAX_FINISHED_SUBAGENTS);
}

#[test]
fn teammate_ids_are_told_from_one_shot_ids() {
    assert!(is_teammate_lifecycle_id("areviewer-1a2b"));
    assert!(is_teammate_lifecycle_id("arev-two-00ff"));
    assert!(!is_teammate_lifecycle_id("a0f9e8"));
    assert!(!is_teammate_lifecycle_id("a-1a2b"));
    assert!(!is_teammate_lifecycle_id("breviewer-1a2b"));
    assert!(!is_teammate_lifecycle_id("areviewer-xyz"));
}
