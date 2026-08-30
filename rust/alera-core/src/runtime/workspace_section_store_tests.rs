use chrono::Utc;

use super::{
    Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus, LOCAL_HOST_ID,
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

#[tokio::test]
async fn sections_move_clear_and_delete_without_touching_workspaces() {
    let (dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    let original = store.upsert_workspace(workspace("a", "p")).await.unwrap();
    store.upsert_workspace(workspace("b", "p")).await.unwrap();
    let first = store
        .create_workspace_section("  Work  ", "a")
        .await
        .unwrap();
    assert_eq!(first.name, "Work");
    store
        .set_workspace_section("b", Some(&first.id))
        .await
        .unwrap();
    let next = store.create_workspace_section("Next", "a").await.unwrap();
    assert_eq!(store.list_workspace_sections().await.unwrap().len(), 2);
    store
        .set_workspace_section("b", Some(&next.id))
        .await
        .unwrap();
    assert_eq!(store.list_workspace_sections().await.unwrap().len(), 1);
    // Old clients upsert a workspace without section metadata.
    store.upsert_workspace(original.clone()).await.unwrap();
    assert_eq!(
        store.find_workspace("a").await.unwrap().unwrap().section_id,
        Some(next.id.clone())
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(reopened.list_workspace_sections().await.unwrap().len(), 1);
    store.remove_workspace_section(&next.id).await.unwrap();
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
    let restored = store.find_workspace("a").await.unwrap().unwrap();
    assert_eq!(restored, original);
    assert!(store.find_workspace("b").await.unwrap().is_some());
    let last = store.create_workspace_section("Last", "a").await.unwrap();
    store.set_workspace_section("a", None).await.unwrap();
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
    assert!(store
        .set_workspace_section("a", Some(&last.id))
        .await
        .is_err());
}

#[tokio::test]
async fn section_validation_rolls_back_and_removal_cleans_last_members() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    for name in ["", "  ", "Others", "others"] {
        assert!(store.create_workspace_section(name, "a").await.is_err());
    }
    assert!(store
        .create_workspace_section("No orphan", "missing")
        .await
        .is_err());
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
    let section = store.create_workspace_section("Work", "a").await.unwrap();
    assert!(store.create_workspace_section("work", "a").await.is_err());
    assert!(store
        .set_workspace_section("a", Some("missing"))
        .await
        .is_err());
    assert_eq!(
        store.workspace_section_id("a").await.unwrap(),
        Some(section.id)
    );
    store.remove_workspace("a", true).await.unwrap();
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
    store.upsert_workspace(workspace("b", "p")).await.unwrap();
    store
        .create_workspace_section("Project", "b")
        .await
        .unwrap();
    store.remove_project("p").await.unwrap();
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
}

#[tokio::test]
async fn unicode_section_names_are_unique_and_soft_removal_cleans_membership() {
    let (_dir, store) = store().await;
    store.upsert_project(project("p")).await.unwrap();
    store.upsert_workspace(workspace("a", "p")).await.unwrap();
    store.create_workspace_section("ÁREA", "a").await.unwrap();
    assert!(store.create_workspace_section("área", "a").await.is_err());
    let mut removed = workspace("a", "p");
    removed.status = WorkspaceStatus::Removed;
    store.upsert_workspace(removed).await.unwrap();
    assert!(store.list_workspace_sections().await.unwrap().is_empty());
}
