use std::collections::HashMap;

use alera_core::runtime::{
    AgentProfile, LinkedReview, Project, ProjectKind, Workspace, WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn pull_request_watch_start_stop_broadcasts_and_mobile_can_read() {
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
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "w", "instanceId": "instance", "hostId": "local", "projectId": "p",
        "name": "Workspace", "path": "/p", "createdAt": now, "updatedAt": now,
        "kind": "linked", "status": "active", "reusesExistingBranch": false,
    }))
    .unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab-1".into(),
            workspace_id: "w".into(),
            kind: "terminal".into(),
            title: "Grok Build".into(),
            created_at: now,
            updated_at: now,
            payload: json!({"terminalSessionId": "sess-1"}),
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_linked_review(LinkedReview {
            workspace_id: "w".into(),
            dismissed: false,
            provider: Some("github".into()),
            number: Some(801),
            url: Some("https://github.com/leynier/alera/pull/801".into()),
            linked_at: now,
        })
        .await
        .unwrap();

    assert!(actor
        .pull_request_watch_request(99, "pullRequestWatch.list", &json!({}))
        .await
        .is_err());

    let started = actor
        .pull_request_watch_request(
            1,
            "pullRequestWatch.start",
            &json!({
                "workspaceId": "w",
                "tabId": "tab-1",
                "mode": "fixAndMerge",
                "conflicts": false,
            }),
        )
        .await
        .unwrap();
    assert_eq!(started["workspaceId"], "w");
    assert_eq!(started["reviewNumber"], 801);
    assert_eq!(started["mode"], "fixAndMerge");
    assert_eq!(started["checks"], true);
    assert_eq!(started["comments"], true);
    assert_eq!(started["conflicts"], false);
    assert_eq!(started["tabId"], "tab-1");

    for events in [&mut desktop_events, &mut mobile_events] {
        let event = events.try_recv().unwrap().as_json().unwrap();
        assert_eq!(event["event"], "pullRequestWatchChanged");
        assert_eq!(event["payload"]["workspaceId"], "w");
    }

    let listed = actor
        .pull_request_watch_request(2, "pullRequestWatch.list", &json!({}))
        .await
        .unwrap();
    assert_eq!(listed["items"][0]["workspaceId"], "w");
    let found = actor
        .pull_request_watch_request(2, "pullRequestWatch.find", &json!({"workspaceId": "w"}))
        .await
        .unwrap();
    assert_eq!(found["mode"], "fixAndMerge");

    let stopped = actor
        .pull_request_watch_request(1, "pullRequestWatch.stop", &json!({"workspaceId": "w"}))
        .await
        .unwrap();
    assert_eq!(stopped["removed"], true);
    for events in [&mut desktop_events, &mut mobile_events] {
        let event = events.try_recv().unwrap().as_json().unwrap();
        assert_eq!(event["event"], "pullRequestWatchChanged");
    }
    assert!(actor
        .pull_request_watch_request(1, "pullRequestWatch.find", &json!({"workspaceId": "w"}),)
        .await
        .unwrap()
        .is_null());
}

#[tokio::test]
async fn pull_request_watch_start_requires_a_problem_and_an_agent() {
    let dir = tempfile::tempdir().unwrap();
    let (desktop, _events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(desktop))]),
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
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "w", "instanceId": "instance", "hostId": "local", "projectId": "p",
        "name": "Workspace", "path": "/p", "createdAt": now, "updatedAt": now,
        "kind": "linked", "status": "active", "reusesExistingBranch": false,
    }))
    .unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    let missing_pr = actor
        .pull_request_watch_request(
            1,
            "pullRequestWatch.start",
            &json!({"workspaceId": "w", "tabId": "tab-1"}),
        )
        .await
        .unwrap_err();
    assert!(missing_pr.to_string().contains("pull request"));
    let missing_agent = actor
        .pull_request_watch_request(
            1,
            "pullRequestWatch.start",
            &json!({"workspaceId": "w", "reviewNumber": 12}),
        )
        .await
        .unwrap_err();
    assert!(
        missing_agent.to_string().contains("terminal")
            || missing_agent.to_string().contains("profile")
    );
}

#[tokio::test]
async fn pull_request_watch_start_keeps_watermarks_when_the_bound_tab_is_gone() {
    let dir = tempfile::tempdir().unwrap();
    let (desktop, _events) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(desktop))]),
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
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    let workspace: Workspace = serde_json::from_value(json!({
        "id": "w", "instanceId": "instance", "hostId": "local", "projectId": "p",
        "name": "Workspace", "path": "/p", "createdAt": now, "updatedAt": now,
        "kind": "linked", "status": "active", "reusesExistingBranch": false,
    }))
    .unwrap();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_linked_review(LinkedReview {
            workspace_id: "w".into(),
            dismissed: false,
            provider: Some("github".into()),
            number: Some(801),
            url: Some("https://github.com/leynier/alera/pull/801".into()),
            linked_at: now,
        })
        .await
        .unwrap();
    let profile: AgentProfile = serde_json::from_value(json!({
        "id": "prof_1", "name": "Grok Build", "agentType": "grok", "command": "grok",
        "createdAt": now, "updatedAt": now,
    }))
    .unwrap();
    actor
        .runtime_store
        .upsert_agent_profile(profile, None)
        .await
        .unwrap();

    let missing_tab = actor
        .pull_request_watch_request(
            1,
            "pullRequestWatch.start",
            &json!({"workspaceId": "w", "tabId": "tab-gone"}),
        )
        .await
        .unwrap_err();
    assert!(
        missing_tab.to_string().contains("tab"),
        "missing tab without a profile should fail: {missing_tab}"
    );

    let stored = actor
        .pull_request_watch_request(
            1,
            "pullRequestWatch.start",
            &json!({
                "workspaceId": "w",
                "tabId": "tab-gone",
                "profileId": "prof_1",
                "mode": "fixAndMerge",
                "lastMergedHeadSha": "abc123",
                "lastDispatch": {
                    "headSha": "abc123",
                    "checksFailed": true,
                    "conflict": false,
                    "threadIds": ["T1"],
                },
            }),
        )
        .await
        .unwrap();
    assert!(stored["tabId"].is_null());
    assert_eq!(stored["profileId"], "prof_1");
    assert_eq!(stored["lastMergedHeadSha"], "abc123");
    assert_eq!(stored["lastDispatch"]["headSha"], "abc123");
    assert_eq!(stored["lastDispatch"]["checksFailed"], true);
}
