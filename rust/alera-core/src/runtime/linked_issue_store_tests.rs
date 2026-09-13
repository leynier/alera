use chrono::{TimeZone, Utc};

use super::{
    LinkedIssue, Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus,
    LOCAL_HOST_ID,
};

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
        branch: Some("main".to_string()),
        path: format!("/tmp/{project_id}/{id}"),
        created_at: now,
        updated_at: now,
        kind: WorkspaceKind::Linked,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        section_id: None,
        child_count: 0,
    }
}

fn issue(workspace_id: &str) -> LinkedIssue {
    LinkedIssue {
        workspace_id: workspace_id.to_string(),
        url: "https://github.com/leynier/alera/issues/758".to_string(),
        provider: Some("github".to_string()),
        repository: Some("leynier/alera".to_string()),
        number: Some(758),
        title: Some("feat: link an issue to a workspace".to_string()),
        state: Some("open".to_string()),
        state_label: Some("Open".to_string()),
        fetched_at: Some(Utc.with_ymd_and_hms(2026, 9, 12, 20, 0, 0).unwrap()),
        fetch_error: None,
        linked_at: Utc.with_ymd_and_hms(2026, 9, 12, 19, 0, 0).unwrap(),
    }
}

#[tokio::test]
async fn linked_issues_round_trip_and_replace() {
    let (dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    assert!(store.find_linked_issue("a").await.unwrap().is_none());
    store.upsert_linked_issue(issue("a")).await.unwrap();
    assert_eq!(
        store.find_linked_issue("a").await.unwrap(),
        Some(issue("a"))
    );

    let url_only = LinkedIssue {
        url: "https://example.atlassian.net/browse/ABC-1".to_string(),
        provider: None,
        repository: None,
        number: None,
        title: None,
        state: None,
        state_label: None,
        fetched_at: None,
        fetch_error: Some("No issue provider recognizes it.".to_string()),
        ..issue("a")
    };
    store.upsert_linked_issue(url_only.clone()).await.unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(reopened.list_linked_issues().await.unwrap(), vec![url_only]);
    assert!(reopened.remove_linked_issue("a").await.unwrap());
    assert!(!reopened.remove_linked_issue("a").await.unwrap());
}

#[tokio::test]
async fn workspace_removal_drops_the_link() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    store.upsert_workspace(workspace("b", "p")).await.unwrap();
    store.upsert_linked_issue(issue("a")).await.unwrap();
    store.upsert_linked_issue(issue("b")).await.unwrap();
    store.remove_workspace("a", true).await.unwrap();
    let remaining = store.list_linked_issues().await.unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].workspace_id, "b");
}

#[tokio::test]
async fn metadata_refresh_cannot_restore_or_replace_a_changed_link() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    let original = store.upsert_linked_issue(issue("a")).await.unwrap();
    let refreshed = LinkedIssue {
        title: Some("Fresh metadata".into()),
        ..original.clone()
    };
    assert_eq!(
        store
            .update_linked_issue_metadata(refreshed.clone())
            .await
            .unwrap(),
        Some(refreshed.clone())
    );
    store.remove_linked_issue("a").await.unwrap();
    assert!(store
        .update_linked_issue_metadata(refreshed.clone())
        .await
        .unwrap()
        .is_none());
    assert!(store.find_linked_issue("a").await.unwrap().is_none());
    for replacement in [
        LinkedIssue {
            url: "https://github.com/leynier/alera/issues/759".into(),
            ..original.clone()
        },
        LinkedIssue {
            linked_at: original.linked_at + chrono::Duration::seconds(1),
            ..original
        },
    ] {
        let replacement = store.upsert_linked_issue(replacement).await.unwrap();
        assert!(store
            .update_linked_issue_metadata(refreshed.clone())
            .await
            .unwrap()
            .is_none());
        assert_eq!(
            store.find_linked_issue("a").await.unwrap(),
            Some(replacement)
        );
    }
}

#[tokio::test]
async fn failed_refresh_preserves_concurrent_success_and_cannot_restore_a_link() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    let original = store.upsert_linked_issue(issue("a")).await.unwrap();
    let refreshed = LinkedIssue {
        title: Some("New title".into()),
        state: Some("closed".into()),
        state_label: Some("Closed".into()),
        fetched_at: Some(original.fetched_at.unwrap() + chrono::Duration::seconds(1)),
        ..original.clone()
    };
    store
        .update_linked_issue_metadata(refreshed.clone())
        .await
        .unwrap();
    let failed = LinkedIssue {
        fetch_error: Some("Timed out".into()),
        ..original
    };
    assert_eq!(
        store
            .update_linked_issue_fetch_error(&failed)
            .await
            .unwrap(),
        Some(LinkedIssue {
            fetch_error: failed.fetch_error.clone(),
            ..refreshed
        })
    );
    store.remove_linked_issue("a").await.unwrap();
    assert!(store
        .update_linked_issue_fetch_error(&failed)
        .await
        .unwrap()
        .is_none());
}
