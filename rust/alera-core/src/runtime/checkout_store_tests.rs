#[path = "checkout_migration_metadata_tests.rs"]
mod migration_metadata_tests;

use chrono::Utc;
use tempfile::TempDir;

use super::{Project, ProjectKind, RuntimeStore, Workspace, WorkspaceKind, WorkspaceStatus};

pub(super) async fn fixture() -> (TempDir, RuntimeStore, Project) {
    let directory = TempDir::new().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let project = Project {
        id: "project".into(),
        name: "Project".into(),
        repo_path: "/repo".into(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind: ProjectKind::GitRepository,
    };
    store.upsert_project(project.clone()).await.unwrap();
    (directory, store, project)
}

pub(super) fn workspace(id: &str, host: &str, path: &str, kind: WorkspaceKind) -> Workspace {
    Workspace {
        id: id.into(),
        instance_id: format!("instance-{id}"),
        project_id: "project".into(),
        host_id: host.into(),
        name: id.into(),
        path: path.into(),
        branch: Some("main".into()),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: vec![],
        tag_names: vec![],
        section_id: None,
        parent_workspace_id: None,
        child_count: 0,
    }
}

#[tokio::test]
async fn linked_repository_origin_is_atomic_and_survives_restart() {
    let (directory, store, _) = fixture().await;
    let task = workspace("remote-linked", "ssh", "/linked", WorkspaceKind::Linked);
    store
        .insert_workspace_with_repository(task.clone(), "/original-repo")
        .await
        .unwrap();
    assert!(store
        .insert_workspace_with_repository(task, "/replacement-repo")
        .await
        .is_err());
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .find_workspace_checkout("remote-linked")
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some("/original-repo")
    );
    assert_eq!(
        reopened
            .find_workspace("remote-linked")
            .await
            .unwrap()
            .unwrap()
            .instance_id,
        "instance-remote-linked"
    );
}

#[tokio::test]
async fn duplicate_workspace_id_does_not_leave_an_origin_or_binding() {
    let (_directory, store, _) = fixture().await;
    store
        .insert_workspace(workspace("task", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    assert!(store
        .insert_workspace_with_repository(
            workspace("task", "ssh", "/new-linked", WorkspaceKind::Linked),
            "/remote-repo"
        )
        .await
        .is_err());
    assert_eq!(
        store
            .find_workspace_checkout("task")
            .await
            .unwrap()
            .unwrap()
            .path,
        "/repo"
    );
    assert!(store
        .list_project_checkouts("project")
        .await
        .unwrap()
        .iter()
        .all(|checkout| checkout.path != "/new-linked"));
}

#[tokio::test]
async fn duplicate_creation_preserves_identity_and_checkout_binding() {
    let (_directory, store, _) = fixture().await;
    let original = store
        .insert_workspace(workspace("task", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    let mut duplicate = workspace("task", "local", "/other", WorkspaceKind::Linked);
    duplicate.instance_id = "replacement".into();
    assert!(store.insert_workspace(duplicate).await.is_err());
    assert_eq!(store.find_workspace("task").await.unwrap(), Some(original));
    assert_eq!(
        store
            .find_workspace_checkout("task")
            .await
            .unwrap()
            .unwrap()
            .path,
        "/repo"
    );
}

#[tokio::test]
async fn equivalent_local_paths_share_checkout_without_merging_task_records() {
    let (directory, store, mut project) = fixture().await;
    let repository = directory.path().join("repository");
    std::fs::create_dir(&repository).unwrap();
    project.repo_path = repository.to_string_lossy().to_string();
    store.upsert_project(project.clone()).await.unwrap();
    let alias = repository
        .join("..")
        .join("repository")
        .to_string_lossy()
        .to_string();
    let first = store
        .insert_workspace(workspace(
            "first",
            "local",
            &project.repo_path,
            WorkspaceKind::Main,
        ))
        .await
        .unwrap();
    let second = store
        .insert_workspace(workspace("second", "local", &alias, WorkspaceKind::Main))
        .await
        .unwrap();
    assert_ne!(first.path, second.path);
    assert_eq!(
        store.find_workspace_checkout("first").await.unwrap(),
        store.find_workspace_checkout("second").await.unwrap()
    );
    sqlx::query("DELETE FROM workspaceCheckoutBindings")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("DELETE FROM repositoryCheckouts")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(reopened.find_workspace("first").await.unwrap(), Some(first));
    assert_eq!(
        reopened.find_workspace("second").await.unwrap(),
        Some(second)
    );
    assert_eq!(
        reopened.find_workspace_checkout("first").await.unwrap(),
        reopened.find_workspace_checkout("second").await.unwrap()
    );
}

#[tokio::test]
async fn shared_tasks_keep_distinct_identity_and_survive_reopen() {
    let (directory, store, _) = fixture().await;
    for id in ["task-a", "task-b"] {
        store
            .upsert_workspace(workspace(id, "local", "/repo", WorkspaceKind::Main))
            .await
            .unwrap();
    }
    let a = store
        .find_workspace_checkout("task-a")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        Some(a.clone()),
        store.find_workspace_checkout("task-b").await.unwrap()
    );
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(reopened.list_workspaces("project").await.unwrap().len(), 2);
    assert_eq!(
        Some(a),
        reopened.find_workspace_checkout("task-a").await.unwrap()
    );
    assert_eq!(
        reopened
            .find_workspace("task-b")
            .await
            .unwrap()
            .unwrap()
            .instance_id,
        "instance-task-b"
    );
}

#[tokio::test]
async fn removing_last_task_retains_checkout_without_recreating_task() {
    let (directory, store, _) = fixture().await;
    store
        .upsert_workspace(workspace("task", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
    store.remove_workspace("task", true).await.unwrap();
    assert!(store
        .find_workspace_checkout("task")
        .await
        .unwrap()
        .is_none());
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened
        .list_workspaces("project")
        .await
        .unwrap()
        .is_empty());
    assert!(reopened
        .find_project_checkout("project", "local")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn identical_paths_on_different_hosts_are_different_checkouts() {
    let (_directory, store, _) = fixture().await;
    for host in ["local", "ssh-one"] {
        store
            .upsert_workspace(workspace(host, host, "/repo", WorkspaceKind::Main))
            .await
            .unwrap();
    }
    assert_ne!(
        store
            .find_workspace_checkout("local")
            .await
            .unwrap()
            .unwrap()
            .id,
        store
            .find_workspace_checkout("ssh-one")
            .await
            .unwrap()
            .unwrap()
            .id,
    );
}

#[tokio::test]
async fn linked_checkout_rejects_second_owner_without_leaving_a_task() {
    let (_directory, store, _) = fixture().await;
    store
        .upsert_workspace(workspace(
            "first",
            "local",
            "/linked",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap();
    let error = store
        .upsert_workspace(workspace(
            "second",
            "local",
            "/linked",
            WorkspaceKind::Linked,
        ))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("only one workspace"));
    assert!(store.find_workspace("second").await.unwrap().is_none());
    assert!(store
        .find_workspace_checkout("second")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn registering_another_project_checkout_does_not_replace_the_first() {
    let (_directory, store, _) = fixture().await;
    let first = store
        .register_project_checkout("project", "local", "/repo")
        .await
        .unwrap();
    assert!(store
        .register_project_checkout("project", "local", "/different")
        .await
        .is_err());
    assert_eq!(
        store
            .find_project_checkout("project", "local")
            .await
            .unwrap(),
        Some(first)
    );
}

#[tokio::test]
async fn legacy_binding_backfill_preserves_task_metadata() {
    let (directory, store, _) = fixture().await;
    let mut task = workspace("legacy", "local", "/repo", WorkspaceKind::Main);
    task.name = "Existing Task".into();
    task.is_pinned = true;
    let before = store.upsert_workspace(task).await.unwrap();
    sqlx::query("DELETE FROM workspaceCheckoutBindings")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("DELETE FROM repositoryCheckouts")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        Some(before),
        reopened.find_workspace("legacy").await.unwrap()
    );
    assert!(reopened
        .find_workspace_checkout("legacy")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn project_checkout_backfill_runs_once_for_legacy_projects_including_empty_ones() {
    let (directory, store, project) = fixture().await;
    assert!(store
        .find_project_checkout(&project.id, "local")
        .await
        .unwrap()
        .is_none());
    sqlx::query("DELETE FROM runtimeMetadata WHERE key = 'checkout.projectBackfillV1'")
        .execute(store.pool())
        .await
        .unwrap();
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let checkout = store
        .find_project_checkout(&project.id, "local")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(checkout.path, project.repo_path);
    assert!(store.list_all_workspaces().await.unwrap().is_empty());
    let mut owner_only = project.clone();
    owner_only.id = "new-owner".into();
    owner_only.repo_path = "/legacy.git".into();
    store
        .register_project_identity(owner_only.clone())
        .await
        .unwrap();
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        store
            .find_project_checkout(&project.id, "local")
            .await
            .unwrap(),
        Some(checkout)
    );
    assert!(store
        .find_project_checkout(&owner_only.id, "local")
        .await
        .unwrap()
        .is_none());
    assert!(store.list_all_workspaces().await.unwrap().is_empty());
}

#[tokio::test]
async fn first_owner_principal_registration_is_atomic_and_preserves_legacy_worktrees() {
    let (directory, store, project) = fixture().await;
    let task = workspace("legacy", "local", "/linked", WorkspaceKind::Linked);
    let task = store
        .insert_workspace_with_repository(task, "/legacy.git")
        .await
        .unwrap();
    let binding = store
        .find_workspace_checkout(&task.id)
        .await
        .unwrap()
        .unwrap();
    let mut candidate = project.clone();
    candidate.repo_path = task.path.clone();
    assert!(store
        .register_owner_project_checkout(candidate.clone())
        .await
        .is_err());
    assert_eq!(
        store
            .find_project(&project.id)
            .await
            .unwrap()
            .unwrap()
            .repo_path,
        project.repo_path
    );
    assert!(store
        .find_project_checkout(&project.id, "local")
        .await
        .unwrap()
        .is_none());
    candidate.repo_path = "/principal".into();
    candidate.name = "Incoming Name".into();
    store
        .register_owner_project_checkout(candidate.clone())
        .await
        .unwrap();
    let adopted = store.find_project(&project.id).await.unwrap().unwrap();
    assert_eq!(adopted.repo_path, candidate.repo_path);
    assert_eq!(adopted.name, project.name);
    candidate.repo_path = "/another".into();
    assert!(store
        .register_owner_project_checkout(candidate.clone())
        .await
        .is_err());
    candidate.repo_path = adopted.repo_path.clone();
    candidate.kind = ProjectKind::Folder;
    assert!(store
        .register_owner_project_checkout(candidate)
        .await
        .is_err());
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        store
            .find_project(&project.id)
            .await
            .unwrap()
            .unwrap()
            .repo_path,
        adopted.repo_path
    );
    assert_eq!(
        store.find_workspace_checkout(&task.id).await.unwrap(),
        Some(binding)
    );
    assert_eq!(store.find_workspace(&task.id).await.unwrap(), Some(task));
    assert_eq!(
        store
            .find_project_checkout(&project.id, "local")
            .await
            .unwrap()
            .unwrap()
            .path,
        adopted.repo_path
    );
}
