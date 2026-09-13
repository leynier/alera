use std::collections::HashMap;

use alera_core::runtime::{LinkedIssue, Project, ProjectKind, Workspace};
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::runtime_mutation_barrier::conflicts_with_runtime_mutation;
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn linked_issues_list_find_and_remove_with_a_scoped_broadcast() {
    let dir = tempfile::tempdir().unwrap();
    let (desktop, mut desktop_events) = ClientHandle::test_channels();
    let (mobile, mut mobile_events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(desktop)),
            (2, mobile_client(mobile, "phone")),
        ]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "p".into(),
            name: "Project".into(),
            repo_path: "/p".into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::Folder,
        })
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "w", "instanceId": "instance", "hostId": "local", "projectId": "p", "name": "Workspace", "path": "/p",
        "createdAt": now, "updatedAt": now, "kind": "main", "status": "active", "reusesExistingBranch": false,
    }))
    .unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_linked_issue(LinkedIssue {
            workspace_id: "w".into(),
            url: "https://example.atlassian.net/browse/ABC-1".into(),
            provider: None,
            repository: None,
            number: None,
            title: None,
            state: None,
            state_label: None,
            fetched_at: None,
            fetch_error: None,
            linked_at: now,
        })
        .await
        .unwrap();

    assert!(actor
        .linked_issue_request(99, "linkedIssue.list", &json!({}))
        .await
        .is_err());
    let list = actor
        .linked_issue_request(2, "linkedIssue.list", &json!({}))
        .await
        .unwrap();
    assert_eq!(list["items"][0]["workspaceId"], "w");
    let found = actor
        .linked_issue_request(1, "linkedIssue.find", &json!({"workspaceId": "w"}))
        .await
        .unwrap();
    assert_eq!(found["url"], "https://example.atlassian.net/browse/ABC-1");
    let missing = actor
        .linked_issue_request(1, "linkedIssue.find", &json!({"workspaceId": "none"}))
        .await
        .unwrap();
    assert!(missing.is_null());

    let removed = actor
        .linked_issue_request(1, "linkedIssue.remove", &json!({"workspaceId": "w"}))
        .await
        .unwrap();
    assert_eq!(removed["removed"], true);
    for events in [&mut desktop_events, &mut mobile_events] {
        let event = events.try_recv().unwrap().as_json().unwrap();
        assert_eq!(event["event"], "linkedIssuesChanged");
        assert_eq!(event["payload"]["workspaceId"], "w");
    }
    let again = actor
        .linked_issue_request(1, "linkedIssue.remove", &json!({"workspaceId": "w"}))
        .await
        .unwrap();
    assert_eq!(again["removed"], false);
    assert!(desktop_events.try_recv().is_err());
}

#[test]
fn link_mutations_wait_behind_runtime_mutations() {
    for verb in [
        "linkedIssue.link",
        "linkedIssue.refresh",
        "linkedIssue.remove",
    ] {
        assert!(conflicts_with_runtime_mutation(verb), "{verb}");
    }
    assert!(!conflicts_with_runtime_mutation("issue.fetch"));
}
