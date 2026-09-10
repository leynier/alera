use chrono::{DateTime, Utc};
use serde_json::{json, Value};

use super::{
    AutomationDefinition, AutomationSchedule, AutomationTarget, AUTOMATION_DEFAULT_NAME_TEMPLATE,
};

fn utc(value: &str) -> DateTime<Utc> {
    value.parse().unwrap()
}

fn assert_camel_case_object(value: &Value, pointer: &str) {
    let object = value
        .pointer(pointer)
        .and_then(Value::as_object)
        .unwrap_or_else(|| panic!("missing object at {pointer}"));
    for key in object.keys() {
        assert!(
            !key.contains('_'),
            "{pointer} serialized snake_case key {key}; rename_all_fields likely regressed"
        );
    }
}

#[test]
fn accepts_desktop_fresh_tab_camel_case_definition() {
    let value = json!({
        "id": "repro-camel",
        "slug": "repro-camel",
        "name": "Repro Camel",
        "promptTemplate": "ping",
        "schedule": { "oneTime": { "at": "2027-01-01T00:00:00Z", "timezone": "UTC" } },
        "target": {
            "freshTab": {
                "workspaceId": "workspace-1",
                "agentProfileId": "profile-1"
            }
        },
        "state": "draft",
        "revision": 0,
        "createdBy": { "kind": "localCli" },
        "modifiedBy": { "kind": "localCli" },
        "createdAt": "2026-09-08T00:00:00Z",
        "updatedAt": "2026-09-08T00:00:00Z"
    });

    let definition: AutomationDefinition = serde_json::from_value(value).unwrap();
    assert_eq!(
        definition.target,
        AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: "profile-1".into(),
        }
    );

    let encoded = serde_json::to_value(&definition).unwrap();
    let reread: AutomationDefinition = serde_json::from_value(encoded.clone()).unwrap();
    assert_eq!(reread.target, definition.target);
    assert_eq!(
        encoded.pointer("/target/freshTab/workspaceId"),
        Some(&json!("workspace-1"))
    );
    assert_eq!(
        encoded.pointer("/target/freshTab/agentProfileId"),
        Some(&json!("profile-1"))
    );
    assert_camel_case_object(&encoded, "/target/freshTab");
}

#[test]
fn accepts_recurring_schedule_camel_case_extras() {
    let value = json!({
        "recurring": {
            "cron": "0 * * * *",
            "timezone": "UTC",
            "startAt": "2027-01-01T00:00:00Z",
            "endAt": "2027-12-31T00:00:00Z",
            "maxScheduledRuns": 5
        }
    });

    let schedule: AutomationSchedule = serde_json::from_value(value).unwrap();
    assert_eq!(
        schedule,
        AutomationSchedule::Recurring {
            cron: "0 * * * *".into(),
            timezone: "UTC".into(),
            start_at: Some(utc("2027-01-01T00:00:00Z")),
            end_at: Some(utc("2027-12-31T00:00:00Z")),
            max_scheduled_runs: Some(5),
        }
    );

    let encoded = serde_json::to_value(&schedule).unwrap();
    let reread: AutomationSchedule = serde_json::from_value(encoded.clone()).unwrap();
    assert_eq!(reread, schedule);
    assert_eq!(
        encoded.pointer("/recurring/startAt"),
        Some(&json!("2027-01-01T00:00:00Z"))
    );
    assert_eq!(
        encoded.pointer("/recurring/endAt"),
        Some(&json!("2027-12-31T00:00:00Z"))
    );
    assert_eq!(
        encoded.pointer("/recurring/maxScheduledRuns"),
        Some(&json!(5))
    );
    assert_camel_case_object(&encoded, "/recurring");
}

#[test]
fn round_trips_existing_tab_and_managed_workspace_camel_case() {
    let existing: AutomationTarget = serde_json::from_value(json!({
        "existingTab": {
            "workspaceId": "workspace-1",
            "tabId": "tab-1",
            "conversationId": "conversation-1"
        }
    }))
    .unwrap();
    assert_eq!(
        existing,
        AutomationTarget::ExistingTab {
            workspace_id: "workspace-1".into(),
            tab_id: "tab-1".into(),
            conversation_id: Some("conversation-1".into()),
        }
    );
    let encoded = serde_json::to_value(&existing).unwrap();
    assert_eq!(
        encoded.pointer("/existingTab/workspaceId"),
        Some(&json!("workspace-1"))
    );
    assert_eq!(encoded.pointer("/existingTab/tabId"), Some(&json!("tab-1")));
    assert_eq!(
        encoded.pointer("/existingTab/conversationId"),
        Some(&json!("conversation-1"))
    );
    assert_camel_case_object(&encoded, "/existingTab");

    let without_conversation: AutomationTarget = serde_json::from_value(json!({
        "existingTab": {
            "workspaceId": "workspace-1",
            "tabId": "tab-1"
        }
    }))
    .unwrap();
    assert_eq!(
        without_conversation,
        AutomationTarget::ExistingTab {
            workspace_id: "workspace-1".into(),
            tab_id: "tab-1".into(),
            conversation_id: None,
        }
    );
    let encoded = serde_json::to_value(&without_conversation).unwrap();
    assert_eq!(
        encoded.pointer("/existingTab/conversationId"),
        Some(&json!(null))
    );

    let managed: AutomationTarget = serde_json::from_value(json!({
        "managedWorkspace": {
            "sourceWorkspaceId": "workspace-1",
            "sourceBranch": "main",
            "nameTemplate": AUTOMATION_DEFAULT_NAME_TEMPLATE,
            "agentProfileId": "profile-1"
        }
    }))
    .unwrap();
    assert_eq!(
        managed,
        AutomationTarget::ManagedWorkspace {
            source_workspace_id: "workspace-1".into(),
            source_branch: "main".into(),
            name_template: AUTOMATION_DEFAULT_NAME_TEMPLATE.into(),
            agent_profile_id: "profile-1".into(),
        }
    );
    let encoded = serde_json::to_value(&managed).unwrap();
    assert_eq!(
        encoded.pointer("/managedWorkspace/sourceWorkspaceId"),
        Some(&json!("workspace-1"))
    );
    assert_eq!(
        encoded.pointer("/managedWorkspace/sourceBranch"),
        Some(&json!("main"))
    );
    assert_eq!(
        encoded.pointer("/managedWorkspace/agentProfileId"),
        Some(&json!("profile-1"))
    );
    assert_camel_case_object(&encoded, "/managedWorkspace");
}

#[test]
fn snake_case_nested_payloads_still_deserialize_and_emit_camel_case() {
    let definition: AutomationDefinition = serde_json::from_value(json!({
        "id": "repro-snake",
        "slug": "repro-snake",
        "name": "Repro Snake",
        "promptTemplate": "ping",
        "schedule": {
            "recurring": {
                "cron": "0 * * * *",
                "timezone": "UTC",
                "start_at": "2027-01-01T00:00:00Z",
                "end_at": "2027-12-31T00:00:00Z",
                "max_scheduled_runs": 5
            }
        },
        "target": {
            "freshTab": {
                "workspace_id": "workspace-1",
                "agent_profile_id": "profile-1"
            }
        },
        "state": "draft",
        "revision": 0,
        "createdBy": { "kind": "localCli" },
        "modifiedBy": { "kind": "localCli" },
        "createdAt": "2026-09-08T00:00:00Z",
        "updatedAt": "2026-09-08T00:00:00Z"
    }))
    .unwrap();
    assert_eq!(
        definition.target,
        AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: "profile-1".into(),
        }
    );
    assert_eq!(definition.schedule.max_scheduled_runs(), Some(5));

    let encoded = serde_json::to_value(&definition).unwrap();
    assert_eq!(
        encoded.pointer("/target/freshTab/workspaceId"),
        Some(&json!("workspace-1"))
    );
    assert_eq!(
        encoded.pointer("/target/freshTab/agentProfileId"),
        Some(&json!("profile-1"))
    );
    assert_eq!(
        encoded.pointer("/schedule/recurring/startAt"),
        Some(&json!("2027-01-01T00:00:00Z"))
    );
    assert_camel_case_object(&encoded, "/target/freshTab");
    assert_camel_case_object(&encoded, "/schedule/recurring");

    let existing: AutomationTarget = serde_json::from_value(json!({
        "existingTab": {
            "workspace_id": "workspace-1",
            "tab_id": "tab-1",
            "conversation_id": "conversation-1"
        }
    }))
    .unwrap();
    assert_eq!(existing.workspace_id(), Some("workspace-1"));

    let managed: AutomationTarget = serde_json::from_value(json!({
        "managedWorkspace": {
            "source_workspace_id": "workspace-1",
            "source_branch": "main",
            "name_template": AUTOMATION_DEFAULT_NAME_TEMPLATE,
            "agent_profile_id": "profile-1"
        }
    }))
    .unwrap();
    assert_eq!(managed.agent_profile_id(), Some("profile-1"));
}
