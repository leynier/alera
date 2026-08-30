use super::*;
use std::collections::HashMap;

use alera_core::runtime::{
    Project, ProjectKind, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use crate::terminal_host::server::actor_test_harness::test_actor;

#[test]
fn resumed_threads_preserve_manual_tab_titles() {
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "tab-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "codex".to_string(),
        title: "Previous name".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "manualTitle": true,
            "codexSnapshot": {"title": "Resumed conversation"},
        }),
    };

    sync_resumed_thread_title(&mut tab);

    assert_eq!(tab.title, "Previous name");
    assert_eq!(tab.payload["manualTitle"], true);
}

#[test]
fn new_threads_preserve_manual_tab_titles() {
    let now = Utc::now();
    let mut tab = WorkspaceTabRecord {
        id: "tab-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "codex".to_string(),
        title: "Previous name".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({"manualTitle": true}),
    };

    reset_new_thread_title(&mut tab);

    assert_eq!(tab.title, "Previous name");
    assert_eq!(tab.payload["manualTitle"], true);
}

#[tokio::test]
async fn already_bound_threads_can_be_focused_during_an_active_turn() {
    let directory = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;
    let now = Utc::now();
    actor
        .runtime_store
        .upsert_project(Project {
            id: "project-1".to_string(),
            name: "Project".to_string(),
            repo_path: directory.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace(Workspace {
            id: "workspace-1".to_string(),
            instance_id: "instance-1".to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: "project-1".to_string(),
            name: "Workspace".to_string(),
            branch: Some("main".to_string()),
            path: directory.path().to_string_lossy().into_owned(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Main,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    let mut current = tab("tab-current", now);
    set_thread_and_snapshot(
        &mut current,
        "thread-current",
        json!({"activeTurnId": "turn-live"}),
    );
    let mut bound = tab("tab-bound", now);
    set_thread_and_snapshot(&mut bound, "thread-bound", json!({}));
    actor
        .runtime_store
        .upsert_workspace_tab(current)
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(bound)
        .await
        .unwrap();

    let response = actor
        .resume_codex_thread(&json!({
            "tabId": "tab-current",
            "threadId": "thread-bound",
        }))
        .await
        .unwrap();

    assert_eq!(response["alreadyBound"], true);
    assert_eq!(response["boundTabId"], "tab-bound");
    assert_eq!(response["boundWorkspaceId"], "workspace-1");
}

fn tab(id: &str, now: chrono::DateTime<Utc>) -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: id.to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "codex".to_string(),
        title: "Codex Chat".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({}),
    }
}

#[test]
fn agent_title_state_stays_private_in_codex_session_responses() {
    let mut value = tab("tab", Utc::now());
    super::super::super::agent_title_state::initialize(&mut value, "Private initial prompt");
    let response = session_response(&value, false, None, None);
    assert!(response["tab"]["payload"]
        .get("agentTitleStateV1")
        .is_none());
    assert!(value.payload.get("agentTitleStateV1").is_some());
}

#[test]
fn new_codex_thread_keeps_generated_title_until_a_valid_replacement() {
    let mut value = tab("tab", Utc::now());
    value.title = "Previous Generated Title".into();
    value.payload["manualTitle"] = json!(true);
    value.payload["agentTitleSource"] = json!("generated");
    reset_new_thread_title(&mut value);
    assert_eq!(value.title, "Previous Generated Title");
    assert_eq!(snapshot(&value)["title"], "Previous Generated Title");
    assert!(!super::super::super::agent_title_state::is_manual(&value));
}
