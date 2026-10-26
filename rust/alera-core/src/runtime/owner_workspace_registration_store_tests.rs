use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};

#[tokio::test]
async fn concurrent_equivalent_registrations_return_one_canonical_owner_state() {
    let (directory, first, mut project) = fixture().await;
    let second = RuntimeStore::open(directory.path()).await.unwrap();
    project.id = "owner-project".into();
    project.repo_path = "/owner-project".into();
    let mut task = workspace(
        "task",
        LOCAL_HOST_ID,
        &project.repo_path,
        WorkspaceKind::Main,
    );
    task.project_id = project.id.clone();
    let mut incoming_project = project.clone();
    incoming_project.name = "Incoming Project".into();
    let mut incoming_task = task.clone();
    incoming_task.name = "Incoming Task".into();
    incoming_task.is_pinned = true;
    let (left, right) = tokio::join!(
        first.register_owner_workspace(&project, &task, None),
        second.register_owner_workspace(&incoming_project, &incoming_task, None),
    );
    let left = left.unwrap();
    let right = right.unwrap();
    assert_eq!(left, right);
    let canonical_project = first.find_project(&project.id).await.unwrap().unwrap();
    if left.name == task.name {
        assert_eq!(canonical_project.name, project.name);
        assert!(!left.is_pinned);
    } else {
        assert_eq!(left.name, incoming_task.name);
        assert_eq!(canonical_project.name, incoming_project.name);
        assert!(left.is_pinned);
    }
    assert_eq!(first.list_workspaces(&project.id).await.unwrap(), [left]);
    assert_eq!(
        first
            .list_project_checkouts(&project.id)
            .await
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn concurrent_conflicting_instances_never_replace_the_winner() {
    let (directory, first, project) = fixture().await;
    let second = RuntimeStore::open(directory.path()).await.unwrap();
    let task = workspace(
        "task",
        LOCAL_HOST_ID,
        &project.repo_path,
        WorkspaceKind::Main,
    );
    let mut conflicting = task.clone();
    conflicting.instance_id = "different-instance".into();
    let (left, right) = tokio::join!(
        first.register_owner_workspace(&project, &task, None),
        second.register_owner_workspace(&project, &conflicting, None),
    );
    let winner = match (left, right) {
        (Ok(winner), Err(_)) => {
            assert_eq!(winner.instance_id, task.instance_id);
            winner
        }
        (Err(_), Ok(winner)) => {
            assert_eq!(winner.instance_id, conflicting.instance_id);
            winner
        }
        _ => panic!("one identity must succeed and the conflicting identity must fail"),
    };
    assert_eq!(first.find_workspace(&task.id).await.unwrap(), Some(winner));
}

#[tokio::test]
async fn conflicting_workspace_or_project_owner_leaves_no_registration_residue() {
    let (_directory, store, project) = fixture().await;
    let task = workspace(
        "task",
        LOCAL_HOST_ID,
        &project.repo_path,
        WorkspaceKind::Main,
    );
    let canonical = store
        .register_owner_workspace(&project, &task, None)
        .await
        .unwrap();
    let binding = store.find_workspace_checkout(&task.id).await.unwrap();
    let original_project = store.find_project(&project.id).await.unwrap();
    let mut unrelated_project = project.clone();
    unrelated_project.id = "unrelated-project".into();
    unrelated_project.repo_path = "/unrelated-project".into();
    let mut collision = task.clone();
    collision.project_id = unrelated_project.id.clone();
    collision.path = unrelated_project.repo_path.clone();
    assert!(store
        .register_owner_workspace(&unrelated_project, &collision, None)
        .await
        .is_err());
    assert!(store
        .find_project(&unrelated_project.id)
        .await
        .unwrap()
        .is_none());
    assert!(store
        .list_project_checkouts(&unrelated_project.id)
        .await
        .unwrap()
        .is_empty());
    let mut different_owner = project.clone();
    different_owner.repo_path = "/different-owner".into();
    collision = task.clone();
    collision.kind = WorkspaceKind::Linked;
    assert!(store
        .register_owner_workspace(&different_owner, &collision, Some("/different-owner"))
        .await
        .is_err());
    collision = task.clone();
    collision.status = WorkspaceStatus::Removed;
    assert!(store
        .register_owner_workspace(&project, &collision, None)
        .await
        .is_err());
    assert_eq!(
        store.find_workspace(&task.id).await.unwrap(),
        Some(canonical)
    );
    assert_eq!(
        store.find_workspace_checkout(&task.id).await.unwrap(),
        binding
    );
    assert_eq!(
        store.find_project(&project.id).await.unwrap(),
        original_project
    );
}

#[tokio::test]
async fn equivalent_linked_registration_preserves_origin_and_rejects_a_different_one() {
    let (directory, first, project) = fixture().await;
    let second = RuntimeStore::open(directory.path()).await.unwrap();
    let task = workspace("linked", LOCAL_HOST_ID, "/linked", WorkspaceKind::Linked);
    let (left, right) = tokio::join!(
        first.register_owner_workspace(&project, &task, Some("/legacy.git")),
        second.register_owner_workspace(&project, &task, Some("/legacy.git")),
    );
    let canonical = left.unwrap();
    assert_eq!(right.unwrap(), canonical);
    assert!(second
        .register_owner_workspace(&project, &task, Some("/different.git"))
        .await
        .is_err());
    assert_eq!(
        first.find_workspace(&task.id).await.unwrap(),
        Some(canonical)
    );
    assert_eq!(
        first
            .find_workspace_checkout(&task.id)
            .await
            .unwrap()
            .unwrap()
            .repository_path
            .as_deref(),
        Some("/legacy.git")
    );
}

#[test]
fn owner_path_identity_preserves_windows_verbatim_compatibility() {
    assert!(same_owner_path(r"\\?\C:\repo", r"C:\repo"));
    assert!(same_owner_path(
        r"\\?\UNC\server\share\repo",
        r"\\server\share\repo"
    ));
    assert!(!same_owner_path(r"\\?\C:\other", r"C:\repo"));
    assert!(!same_owner_path("/repo-other", "/repo"));
}
