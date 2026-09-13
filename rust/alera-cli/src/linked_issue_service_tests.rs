use alera_core::runtime::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

use super::*;
use crate::issue_tracking::FakeForgeCliRunner;

async fn store_with_workspace() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    store
        .upsert_project(Project {
            id: "p".into(),
            name: "p".into(),
            repo_path: "/tmp/p".into(),
            created_at: now,
            updated_at: now,
            kind: ProjectKind::GitRepository,
        })
        .await
        .unwrap();
    store
        .upsert_workspace(Workspace {
            id: "w".into(),
            instance_id: "inst-w".into(),
            host_id: LOCAL_HOST_ID.into(),
            project_id: "p".into(),
            name: "w".into(),
            branch: Some("main".into()),
            path: "/tmp/p/w".into(),
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: vec![],
            tag_names: vec![],
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    (dir, store)
}

const ISSUE_URL: &str = "https://github.com/leynier/alera/issues/758";
const ISSUE_JSON: &str = r#"{"number":758,"title":"Link an issue","state":"OPEN","url":"https://github.com/leynier/alera/issues/758"}"#;

#[tokio::test]
async fn links_and_caches_the_fetched_metadata() {
    let (_dir, store) = store_with_workspace().await;
    let runner = FakeForgeCliRunner::replying(0, ISSUE_JSON, "");
    let mut persisted = None;
    let outcome = link_workspace_issue(&store, "w", ISSUE_URL, &runner, |record| {
        persisted = Some(record.clone());
    })
    .await
    .unwrap();
    let persisted = persisted.expect("persisted before fetching");
    assert_eq!(persisted.title, None);
    assert_eq!(persisted.provider.as_deref(), Some("github"));
    assert_eq!(outcome.linked_issue.title.as_deref(), Some("Link an issue"));
    assert_eq!(outcome.linked_issue.state.as_deref(), Some("open"));
    assert!(outcome.linked_issue.fetched_at.is_some());
    assert!(outcome.fetch_error.is_none());
    assert_eq!(
        store.find_linked_issue("w").await.unwrap(),
        Some(outcome.linked_issue.clone())
    );
    let json = outcome.to_json();
    assert_eq!(json["linkedIssue"]["workspaceId"], "w");
    assert_eq!(json["issue"]["number"], 758);
    assert!(json["fetchError"].is_null());
}

#[tokio::test]
async fn a_failed_fetch_keeps_the_url_and_records_the_error() {
    let (_dir, store) = store_with_workspace().await;
    let runner = FakeForgeCliRunner::default();
    runner.push(Err(std::io::Error::from(std::io::ErrorKind::NotFound)));
    let outcome = link_workspace_issue(&store, "w", ISSUE_URL, &runner, |_| {})
        .await
        .unwrap();
    assert_eq!(outcome.fetch_error.as_ref().unwrap().code(), "cliMissing");
    let stored = store.find_linked_issue("w").await.unwrap().unwrap();
    assert_eq!(stored.url, ISSUE_URL);
    assert!(stored.fetch_error.unwrap().contains("gh"));
    assert_eq!(outcome.to_json()["fetchError"]["code"], "cliMissing");
}

#[tokio::test]
async fn unrecognized_urls_link_without_spawning() {
    let (_dir, store) = store_with_workspace().await;
    let runner = FakeForgeCliRunner::default();
    let outcome = link_workspace_issue(
        &store,
        "w",
        "https://example.atlassian.net/browse/ABC-1",
        &runner,
        |_| {},
    )
    .await
    .unwrap();
    assert!(runner.calls.lock().unwrap().is_empty());
    assert_eq!(outcome.fetch_error.unwrap().code(), "unsupported");
    let stored = store.find_linked_issue("w").await.unwrap().unwrap();
    assert_eq!(stored.provider, None);
    assert_eq!(stored.fetch_error, None);
}

#[tokio::test]
async fn relinking_the_same_url_keeps_the_cache_and_invalid_input_is_rejected() {
    let (_dir, store) = store_with_workspace().await;
    let runner = FakeForgeCliRunner::replying(0, ISSUE_JSON, "");
    link_workspace_issue(&store, "w", ISSUE_URL, &runner, |_| {})
        .await
        .unwrap();
    let relinked = persist_issue_link(&store, "w", ISSUE_URL).await.unwrap();
    assert_eq!(relinked.title.as_deref(), Some("Link an issue"));
    assert!(persist_issue_link(&store, "w", "not a url").await.is_err());
    assert!(persist_issue_link(&store, "missing", ISSUE_URL)
        .await
        .is_err());
    assert!(refresh_workspace_issue(&store, "missing", &runner)
        .await
        .is_err());
}
