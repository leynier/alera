use chrono::{DateTime, Utc};
use serde_json::json;

use super::{
    AutomationDefinition, AutomationSchedule, AutomationTarget, AUTOMATION_DEFAULT_NAME_TEMPLATE,
};

fn utc(value: &str) -> DateTime<Utc> {
    value.parse().unwrap()
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
    assert_eq!(
        encoded.pointer("/target/freshTab/workspaceId"),
        Some(&json!("workspace-1"))
    );
    assert_eq!(
        encoded.pointer("/target/freshTab/agentProfileId"),
        Some(&json!("profile-1"))
    );
    assert!(encoded.pointer("/target/freshTab/workspace_id").is_none());
    assert!(encoded
        .pointer("/target/freshTab/agent_profile_id")
        .is_none());
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
    assert!(encoded.pointer("/recurring/start_at").is_none());
    assert!(encoded.pointer("/recurring/end_at").is_none());
    assert!(encoded.pointer("/recurring/max_scheduled_runs").is_none());
}

#[test]
fn serializes_existing_tab_and_managed_workspace_fields_as_camel_case() {
    let existing = AutomationTarget::ExistingTab {
        workspace_id: "workspace-1".into(),
        tab_id: "tab-1".into(),
        conversation_id: Some("conversation-1".into()),
    };
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

    let managed = AutomationTarget::ManagedWorkspace {
        source_workspace_id: "workspace-1".into(),
        source_branch: "main".into(),
        name_template: AUTOMATION_DEFAULT_NAME_TEMPLATE.into(),
        agent_profile_id: "profile-1".into(),
    };
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
        encoded.pointer("/managedWorkspace/nameTemplate"),
        Some(&json!(AUTOMATION_DEFAULT_NAME_TEMPLATE))
    );
    assert_eq!(
        encoded.pointer("/managedWorkspace/agentProfileId"),
        Some(&json!("profile-1"))
    );
}

#[test]
fn still_accepts_legacy_snake_case_nested_fields() {
    let target: AutomationTarget = serde_json::from_value(json!({
        "freshTab": {
            "workspace_id": "workspace-1",
            "agent_profile_id": "profile-1"
        }
    }))
    .unwrap();
    assert_eq!(
        target,
        AutomationTarget::FreshTab {
            workspace_id: "workspace-1".into(),
            agent_profile_id: "profile-1".into(),
        }
    );

    let schedule: AutomationSchedule = serde_json::from_value(json!({
        "recurring": {
            "cron": "0 * * * *",
            "timezone": "UTC",
            "start_at": "2027-01-01T00:00:00Z",
            "end_at": "2027-12-31T00:00:00Z",
            "max_scheduled_runs": 5
        }
    }))
    .unwrap();
    assert_eq!(schedule.max_scheduled_runs(), Some(5));
}
