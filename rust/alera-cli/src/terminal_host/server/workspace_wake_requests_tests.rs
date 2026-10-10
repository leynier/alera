use std::collections::HashMap;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord,
};
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::server::ServerActor;
use crate::terminal_host::session::Session;

async fn actor_with_workspace(dir: &tempfile::TempDir, host_id: &str) -> ServerActor {
    let (handle, _) = ClientHandle::test_channels();
    let actor = test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let now = Utc::now();
    let path = dir.path().to_string_lossy().to_string();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project".into(),
            name: "Project".into(),
            repo_path: path.clone(),
            kind: ProjectKind::Folder,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "w".into(),
            instance_id: "w-instance".into(),
            host_id: host_id.into(),
            project_id: "project".into(),
            name: "Task".into(),
            branch: None,
            path,
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: vec![],
            tag_names: vec![],
            section_id: None,
            parent_workspace_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    for (tab, session) in [("tab-1", "s-1"), ("tab-2", "s-2")] {
        actor
            .runtime_store
            .upsert_workspace_tab(WorkspaceTabRecord {
                id: tab.into(),
                workspace_id: "w".into(),
                kind: "terminal".into(),
                title: tab.into(),
                created_at: now,
                updated_at: now,
                payload: json!({ "terminalSessionId": session }),
            })
            .await
            .unwrap();
    }
    actor
}

fn live_session(id: &str, tab_id: &str) -> Session {
    let mut session = Session::driver_test_stub(id, 80, 24);
    session.workspace_id = "w".into();
    session.tab_id = tab_id.into();
    session
}

#[tokio::test]
async fn waking_attaches_every_slept_terminal_and_clears_the_sleep() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;
    actor
        .runtime_store
        .record_workspace_sleep("w")
        .await
        .unwrap();
    // A terminal closed after the sleep has nothing to start.
    actor
        .runtime_store
        .remove_workspace_tab("tab-2")
        .await
        .unwrap();
    actor
        .sessions
        .insert("s-1".into(), live_session("s-1", "tab-1"));

    let woken = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();

    assert_eq!(woken["wasAsleep"], true);
    assert_eq!(
        woken["woken"],
        json!([{ "tabId": "tab-1", "sessionId": "s-1" }])
    );
    assert_eq!(woken["failed"], json!([]));
    assert!(
        !actor.sessions["s-1"].clients.contains(&1),
        "the waking client does not stay attached"
    );
    assert!(actor
        .runtime_store
        .list_slept_workspace_tabs()
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn an_awake_workspace_has_nothing_to_wake() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "local").await;

    let woken = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap();

    assert_eq!(woken["wasAsleep"], false);
    assert_eq!(woken["woken"], json!([]));
    assert!(actor.sessions.is_empty());
}

#[tokio::test]
async fn unknown_and_remote_workspaces_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor_with_workspace(&dir, "ssh-lab").await;

    let remote = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "w" }))
        .await
        .unwrap_err();
    assert!(remote.to_string().contains("SSH host"), "{remote}");
    let missing = actor
        .wake_workspace_request(1, &json!({ "workspaceId": "nope" }))
        .await
        .unwrap_err();
    assert!(missing.to_string().contains("not found"), "{missing}");
}
