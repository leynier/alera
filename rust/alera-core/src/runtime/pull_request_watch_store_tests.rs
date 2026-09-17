use super::{Project, ProjectKind};
use super::{
    PullRequestWatch, PullRequestWatchDispatchMark, RuntimeStore, Workspace, WorkspaceKind,
    WorkspaceStatus, LOCAL_HOST_ID,
};
use chrono::Utc;

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

fn project(id: &str) -> Project {
    let now = Utc::now();
    Project {
        id: id.to_string(),
        name: id.to_string(),
        repo_path: format!("/tmp/{id}"),
        created_at: now,
        updated_at: now,
        kind: ProjectKind::GitRepository,
    }
}

fn workspace(id: &str, project_id: &str) -> Workspace {
    let now = Utc::now();
    Workspace {
        id: id.to_string(),
        instance_id: format!("inst-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: project_id.to_string(),
        name: id.to_string(),
        branch: Some("feat/watch".to_string()),
        path: format!("/tmp/{project_id}/{id}"),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: Some("main".to_string()),
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

fn watch(workspace_id: &str) -> PullRequestWatch {
    PullRequestWatch {
        workspace_id: workspace_id.to_string(),
        review_number: 801,
        mode: "fixAndMerge".to_string(),
        checks: true,
        comments: true,
        conflicts: false,
        tab_id: Some("tab-1".to_string()),
        profile_id: Some("prof_1".to_string()),
        label: Some("Grok Build".to_string()),
        last_dispatch: Some(PullRequestWatchDispatchMark {
            head_sha: Some("abc".to_string()),
            checks_failed: true,
            conflict: false,
            thread_ids: vec!["T1".to_string()],
        }),
        last_merged_head_sha: None,
    }
}

#[tokio::test]
async fn pull_request_watches_round_trip_replace_and_remove() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    assert!(store.find_pull_request_watch("a").await.unwrap().is_none());
    store.upsert_pull_request_watch(watch("a")).await.unwrap();
    assert_eq!(
        store.find_pull_request_watch("a").await.unwrap(),
        Some(watch("a"))
    );
    let mut next = watch("a");
    next.mode = "fix".to_string();
    next.conflicts = true;
    next.last_dispatch = None;
    store.upsert_pull_request_watch(next.clone()).await.unwrap();
    assert_eq!(
        store.find_pull_request_watch("a").await.unwrap(),
        Some(next)
    );
    assert!(store.remove_pull_request_watch("a").await.unwrap());
    assert!(store.find_pull_request_watch("a").await.unwrap().is_none());
    assert!(!store.remove_pull_request_watch("a").await.unwrap());
}

#[tokio::test]
async fn pull_request_watch_rejects_empty_scope_and_missing_agent() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    let mut empty_scope = watch("a");
    empty_scope.checks = false;
    empty_scope.comments = false;
    empty_scope.conflicts = false;
    assert!(store.upsert_pull_request_watch(empty_scope).await.is_err());
    let mut no_agent = watch("a");
    no_agent.tab_id = None;
    no_agent.profile_id = None;
    assert!(store.upsert_pull_request_watch(no_agent).await.is_err());
}

#[tokio::test]
async fn removing_a_workspace_drops_its_pull_request_watch() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    store.upsert_pull_request_watch(watch("a")).await.unwrap();
    let mut removed = workspace("a", "p");
    removed.status = WorkspaceStatus::Removed;
    store.upsert_workspace(removed).await.unwrap();
    assert!(store.find_pull_request_watch("a").await.unwrap().is_none());

    store.upsert_workspace(workspace("b", "p")).await.unwrap();
    store.upsert_pull_request_watch(watch("b")).await.unwrap();
    store.remove_workspace("b", true).await.unwrap();
    assert!(store.find_pull_request_watch("b").await.unwrap().is_none());
}
