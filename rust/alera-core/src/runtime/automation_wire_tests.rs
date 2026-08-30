use serde_json::json;

use super::{AutomationSchedule, AutomationTarget};

#[test]
fn automation_wire_accepts_desktop_target_fields_in_every_variant() {
    for value in [
        json!({"existingTab":{"workspaceId":"w","tabId":"t","conversationId":"c"}}),
        json!({"freshTab":{"workspaceId":"w","agentProfileId":"p"}}),
        json!({"managedWorkspace":{"sourceWorkspaceId":"w","sourceBranch":"main","nameTemplate":"review","agentProfileId":"p"}}),
    ] {
        let target: AutomationTarget = serde_json::from_value(value.clone()).unwrap();
        assert_eq!(serde_json::to_value(target).unwrap(), value);
    }
}

#[test]
fn automation_wire_retains_recurring_bounds_from_desktop_payload() {
    let value = json!({"recurring":{"cron":"0 9 * * *","timezone":"UTC","startAt":"2030-01-01T00:00:00Z","endAt":"2030-02-01T00:00:00Z","maxScheduledRuns":4}});
    let schedule: AutomationSchedule = serde_json::from_value(value.clone()).unwrap();
    assert_eq!(schedule.max_scheduled_runs(), Some(4));
    assert_eq!(serde_json::to_value(schedule).unwrap(), value);
}

#[test]
fn automation_wire_reads_legacy_persisted_snake_case_fields() {
    let target: AutomationTarget = serde_json::from_value(json!({"managedWorkspace":{
        "source_workspace_id":"w","source_branch":"main","name_template":"review","agent_profile_id":"p"
    }})).unwrap();
    assert_eq!(serde_json::to_value(target).unwrap(), json!({"managedWorkspace":{
        "sourceWorkspaceId":"w","sourceBranch":"main","nameTemplate":"review","agentProfileId":"p"
    }}));
    let schedule: AutomationSchedule = serde_json::from_value(json!({"recurring":{
        "cron":"0 9 * * *","timezone":"UTC","start_at":"2030-01-01T00:00:00Z","end_at":null,"max_scheduled_runs":4
    }})).unwrap();
    assert_eq!(schedule.max_scheduled_runs(), Some(4));
    assert_eq!(serde_json::to_value(schedule).unwrap()["recurring"]["startAt"], "2030-01-01T00:00:00Z");
}
