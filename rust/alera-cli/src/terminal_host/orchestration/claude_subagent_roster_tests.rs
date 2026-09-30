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
    assert_eq!(
        roster.observe("a1", SubagentState::Waiting),
        Observed::Tracked
    );
    assert_eq!(roster.effective_state(), AgentPresenceState::Waiting);

    assert_eq!(
        roster.observe("a1", SubagentState::Working),
        Observed::Tracked
    );
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

    // The main agent's own approval prompt is not the child's to answer.
    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Waiting);
    // A notification for that same prompt keeps it the main agent's.
    roster.raise_attention_a_child_may_answer(AgentPresenceState::Waiting);
    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Waiting);

    roster.set_lead(AgentPresenceState::Done, None, false);
    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Done);
}

#[test]
fn a_child_answers_attention_announced_without_naming_it() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.raise_attention_a_child_may_answer(AgentPresenceState::Waiting);
    assert_eq!(roster.effective_state(), AgentPresenceState::Waiting);
    roster.child_resumed_lead();
    assert_eq!(roster.lead(), AgentPresenceState::Working);
}

#[test]
fn giving_up_on_silent_children_keeps_a_confirmed_main_done() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.settle_after_silence();
    assert_eq!(roster.effective_state(), AgentPresenceState::Done);
    assert!(!roster.lead_inferred_idle());

    let mut running = ClaudeSubagentRoster::default();
    running.start("a1");
    running.settle_after_silence();
    assert_eq!(running.effective_state(), AgentPresenceState::Done);
    assert!(running.lead_inferred_idle());
}

#[test]
fn a_late_hook_from_a_finished_child_does_not_revive_it() {
    let mut roster = done_lead();
    roster.start("a1");
    roster.finish("a1");
    assert_eq!(
        roster.observe("a1", SubagentState::Working),
        Observed::Finished
    );
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
    assert_eq!(
        roster.observe("alost", SubagentState::Working),
        Observed::Finished
    );
    assert_eq!(
        roster.observe("adone", SubagentState::Working),
        Observed::Finished
    );
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
    assert_eq!(
        roster.observe("aoverflow", SubagentState::Waiting),
        Observed::Untracked
    );
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
