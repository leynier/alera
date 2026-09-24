use super::*;
use crate::runtime::checkout_store_tests::{fixture, workspace};

async fn remote(store: &RuntimeStore, id: &str, host: &str) -> Workspace {
    store
        .register_project_checkout("project", host, "/remote/project")
        .await
        .unwrap();
    store
        .insert_workspace(workspace(id, host, "/remote/project", WorkspaceKind::Main))
        .await
        .unwrap()
}

fn intent(source: &Workspace) -> WorkspaceRelocationIntent {
    WorkspaceRelocationIntent {
        workspace_id: source.id.clone(),
        to_project_checkout: false,
        destination_path: Some("/remote/worktrees/task".into()),
        branch: Some("topic".into()),
        replacement_branch: None,
        move_changes: false,
        shared_impact_confirmed: true,
    }
}

#[tokio::test]
async fn remote_choices_survive_reopen_and_do_not_move_or_recreate_the_task() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let id = uuid::Uuid::new_v4().to_string();
    store
        .begin_remote_workspace_relocation(&id, &source, intent(&source))
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let pending = reopened
        .pending_remote_workspace_relocation("project", "ssh")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.id, id);
    assert_eq!(pending.source.instance_id, source.instance_id);
    assert_eq!(
        pending.destination_path.as_deref(),
        Some("/remote/worktrees/task")
    );
    assert_eq!(
        reopened
            .find_workspace(&source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        source.path
    );
    reopened
        .begin_remote_workspace_relocation(&id, &source, intent(&source))
        .await
        .unwrap();
    let mut changed = intent(&source);
    changed.move_changes = true;
    assert!(reopened
        .begin_remote_workspace_relocation(&id, &source, changed)
        .await
        .is_err());
    assert_eq!(reopened.list_workspaces("project").await.unwrap().len(), 1);
}

#[tokio::test]
async fn pending_remote_relocation_reserves_identity_but_preserves_metadata_edits() {
    let (_root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let id = uuid::Uuid::new_v4().to_string();
    store
        .begin_remote_workspace_relocation(&id, &source, intent(&source))
        .await
        .unwrap();
    assert!(store.remove_workspace(&source.id, true).await.is_err());
    let mut changed = source.clone();
    changed.path = "/remote/other".into();
    assert!(store.upsert_workspace(changed).await.is_err());
    let mut renamed = source.clone();
    renamed.name = "Renamed task".into();
    store.upsert_workspace(renamed.clone()).await.unwrap();
    let retry = store
        .begin_remote_workspace_relocation(&id, &renamed, intent(&renamed))
        .await
        .unwrap();
    assert_eq!(retry.source.name, source.name);
    assert_eq!(
        store
            .find_workspace(&source.id)
            .await
            .unwrap()
            .unwrap()
            .name,
        renamed.name
    );
    assert_eq!(
        store
            .find_workspace_checkout(&source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        source.path
    );
}

#[tokio::test]
async fn concurrent_remote_intents_share_a_checkout_lock_scoped_to_the_host() {
    let (_root, store, _) = fixture().await;
    let first = remote(&store, "one", "ssh").await;
    let second = remote(&store, "two", "ssh").await;
    let first_id = uuid::Uuid::new_v4().to_string();
    let second_id = uuid::Uuid::new_v4().to_string();
    let (one, two) = tokio::join!(
        store.begin_remote_workspace_relocation(&first_id, &first, intent(&first)),
        store.begin_remote_workspace_relocation(&second_id, &second, intent(&second)),
    );
    assert_ne!(one.is_ok(), two.is_ok());
    let other_host = remote(&store, "other-host", "another-ssh").await;
    store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &other_host,
            intent(&other_host),
        )
        .await
        .unwrap();
}

fn owner_receipt(pending: &RemoteWorkspaceRelocationIntent) -> crate::runtime::WorkspaceRelocation {
    let mut source = pending.source.clone();
    source.host_id = LOCAL_HOST_ID.into();
    let mut destination = source.clone();
    destination.path = pending.destination_path.clone().unwrap();
    let original_branch = source.branch.clone().unwrap_or_else(|| "main".into());
    destination.kind = if pending.intent.to_project_checkout {
        WorkspaceKind::Main
    } else {
        WorkspaceKind::Linked
    };
    destination.branch = if pending.intent.to_project_checkout {
        Some(original_branch.clone())
    } else {
        pending.intent.branch.clone()
    };
    crate::runtime::WorkspaceRelocation {
        id: pending.id.clone(),
        source,
        destination,
        repository_path: pending.project_checkout_path.clone(),
        original_branch,
        source_commit: "1111111111111111111111111111111111111111".into(),
        replacement_branch: None,
        replacement_commit: None,
        destination_original_branch: None,
        destination_original_commit: None,
        move_changes: pending.intent.move_changes,
        recovery_stash_oid: None,
        phase: crate::runtime::WorkspaceRelocationPhase::Completed,
    }
}

#[tokio::test]
async fn owner_receipt_is_durable_but_does_not_move_home_or_release_its_reservation() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    let receipt = owner_receipt(&pending);
    for (path, value) in [
        ("/phase", serde_json::json!("committed")),
        ("/source/instanceId", serde_json::json!("other")),
        ("/destination/path", serde_json::json!("/wrong")),
        ("/destination/branch", serde_json::json!("wrong")),
        ("/source/hostId", serde_json::json!("ssh")),
        ("/moveChanges", serde_json::json!(true)),
        (
            "/repositoryPath",
            serde_json::json!("/different-repository"),
        ),
    ] {
        let mut changed = serde_json::to_value(&receipt).unwrap();
        *changed.pointer_mut(path).unwrap() = value;
        assert!(
            store
                .record_remote_workspace_relocation_receipt(
                    &pending.id,
                    &serde_json::from_value(changed).unwrap()
                )
                .await
                .is_err(),
            "{path}"
        );
    }
    assert!(store
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .is_none());
    store
        .record_remote_workspace_relocation_receipt(&pending.id, &receipt)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    reopened
        .record_remote_workspace_relocation_receipt(&pending.id, &receipt)
        .await
        .unwrap();
    let recovered = reopened
        .find_remote_workspace_relocation_receipt(&pending.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.source_commit, receipt.source_commit);
    assert_eq!(
        reopened
            .find_workspace(&source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        source.path
    );
    assert!(reopened.remove_workspace(&source.id, true).await.is_err());
    let mut changed = receipt.clone();
    changed.recovery_stash_oid = Some("different-evidence".into());
    assert!(reopened
        .record_remote_workspace_relocation_receipt(&pending.id, &changed)
        .await
        .is_err());
}

#[tokio::test]
async fn pending_remote_worktree_reservation_blocks_cross_project_adoption_after_reopen() {
    let (root, store, mut project) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let pending = store
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &source,
            intent(&source),
        )
        .await
        .unwrap();
    project.id = "other-project".into();
    store.upsert_project(project.clone()).await.unwrap();
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let mut other = workspace(
        "other-task",
        "ssh",
        pending.destination_path.as_deref().unwrap(),
        WorkspaceKind::Linked,
    );
    other.project_id = project.id.clone();
    assert!(reopened.insert_workspace(other.clone()).await.is_err());
    assert!(reopened.find_workspace(&other.id).await.unwrap().is_none());
    other.host_id = "another-ssh".into();
    reopened.insert_workspace(other).await.unwrap();
    let mut competing = workspace(
        "competing",
        "ssh",
        "/different/project",
        WorkspaceKind::Main,
    );
    competing.project_id = project.id;
    reopened
        .register_project_checkout(&competing.project_id, "ssh", &competing.path)
        .await
        .unwrap();
    reopened.insert_workspace(competing.clone()).await.unwrap();
    assert!(reopened
        .begin_remote_workspace_relocation(
            &uuid::Uuid::new_v4().to_string(),
            &competing,
            intent(&competing)
        )
        .await
        .is_err());
}

#[path = "remote_workspace_relocation_commit_tests.rs"]
mod commit_tests;

#[path = "remote_relocation_launch_barrier_tests.rs"]
mod launch_barrier_tests;

#[path = "remote_relocation_preparation_tests.rs"]
mod preparation_tests;

#[path = "remote_relocation_recovery_tests.rs"]
mod recovery_tests;
