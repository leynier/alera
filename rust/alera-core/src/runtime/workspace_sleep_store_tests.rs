use chrono::Utc;

use super::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
    WorkspaceTabRecord, LOCAL_HOST_ID,
};

async fn store_with_tabs(tabs: &[(&str, &str)]) -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "p".to_string(),
            name: "p".to_string(),
            repo_path: "/tmp/p".to_string(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(Workspace {
            id: "w".to_string(),
            instance_id: "inst-w".to_string(),
            host_id: LOCAL_HOST_ID.to_string(),
            project_id: "p".to_string(),
            name: "w".to_string(),
            branch: Some("main".to_string()),
            path: "/tmp/p/w".to_string(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    for (id, kind) in tabs {
        add_tab(&store, id, kind).await;
    }
    (dir, store)
}

async fn add_tab(store: &RuntimeStore, id: &str, kind: &str) {
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: id.to_string(),
            workspace_id: "w".to_string(),
            kind: kind.to_string(),
            title: id.to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: serde_json::json!({}),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn sleep_records_only_terminal_tabs() {
    let (_dir, store) =
        store_with_tabs(&[("terminal-1", "terminal"), ("editor-1", "editor")]).await;

    assert_eq!(
        store.record_workspace_sleep("w").await.unwrap(),
        vec!["terminal-1".to_string()]
    );
    assert_eq!(
        store.list_slept_workspace_tabs().await.unwrap()["w"],
        vec!["terminal-1".to_string()]
    );
}

#[tokio::test]
async fn sleep_without_terminals_records_nothing() {
    let (_dir, store) = store_with_tabs(&[("editor-1", "editor")]).await;

    assert!(store.record_workspace_sleep("w").await.unwrap().is_empty());
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
}

#[tokio::test]
async fn a_slept_terminal_wakes_the_whole_workspace() {
    let (_dir, store) =
        store_with_tabs(&[("terminal-1", "terminal"), ("terminal-2", "terminal")]).await;
    store.record_workspace_sleep("w").await.unwrap();

    assert!(store
        .wake_workspace_for_tab("w", "terminal-2")
        .await
        .unwrap());
    assert!(store.list_slept_workspace_tabs().await.unwrap().is_empty());
}

#[tokio::test]
async fn a_terminal_opened_after_the_sleep_keeps_the_others_asleep() {
    let (_dir, store) = store_with_tabs(&[("terminal-1", "terminal")]).await;
    store.record_workspace_sleep("w").await.unwrap();
    add_tab(&store, "spawned", "terminal").await;

    assert!(!store.wake_workspace_for_tab("w", "spawned").await.unwrap());
    assert_eq!(
        store.list_slept_workspace_tabs().await.unwrap()["w"],
        vec!["terminal-1".to_string()]
    );
}
