use super::*;

#[tokio::test]
async fn unresolved_owner_choices_and_preparation_survive_restart_without_moving_home() {
    let (root, store, _) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let mut choices = intent(&source);
    choices.destination_path = None;
    let id = uuid::Uuid::new_v4().to_string();
    let pending = store
        .begin_remote_workspace_relocation_with_root(
            &id,
            &source,
            choices.clone(),
            Some("/owner/alias".into()),
        )
        .await
        .unwrap();
    assert!(pending.destination_path.is_none());
    assert!(store.commit_remote_workspace_relocation(&id).await.is_err());
    let mut resolved = pending.clone();
    resolved.destination_path = Some("/owner/canonical/task".into());
    let mut preparation = owner_receipt(&resolved);
    preparation.phase = crate::runtime::WorkspaceRelocationPhase::Prepared;
    store
        .record_remote_workspace_relocation_preparation(&id, &preparation)
        .await
        .unwrap();
    assert!(store
        .record_remote_workspace_relocation_receipt(&id, &preparation)
        .await
        .is_err());
    let reopened = RuntimeStore::open(root.path()).await.unwrap();
    let retried = reopened
        .begin_remote_workspace_relocation_with_root(
            &id,
            &source,
            choices.clone(),
            Some("/owner/alias".into()),
        )
        .await
        .unwrap();
    assert_eq!(retried.destination_path, resolved.destination_path);
    assert!(retried.intent.destination_path.is_none());
    assert!(retried.owner_preparation.is_some());
    assert_eq!(
        reopened
            .find_workspace(&source.id)
            .await
            .unwrap()
            .unwrap()
            .path,
        source.path
    );
    assert!(reopened
        .begin_remote_workspace_relocation_with_root(
            &id,
            &source,
            choices,
            Some("/changed-root".into()),
        )
        .await
        .is_err());
    reopened
        .record_remote_workspace_relocation_preparation(&id, &preparation)
        .await
        .unwrap();
    let mut changed = preparation.clone();
    changed.destination.path = "/elsewhere".into();
    assert!(reopened
        .record_remote_workspace_relocation_preparation(&id, &changed)
        .await
        .is_err());
    let mut receipt = owner_receipt(&retried);
    receipt.source_commit = "2222222222222222222222222222222222222222".into();
    assert!(reopened
        .record_remote_workspace_relocation_receipt(&id, &receipt)
        .await
        .is_err());
    reopened
        .record_remote_workspace_relocation_receipt(&id, &owner_receipt(&retried))
        .await
        .unwrap();
    assert_eq!(
        reopened
            .commit_remote_workspace_relocation(&id)
            .await
            .unwrap()
            .path,
        "/owner/canonical/task"
    );
}

#[tokio::test]
async fn resolved_destination_cannot_adopt_a_worktree_from_another_project() {
    let (_root, store, mut project) = fixture().await;
    let source = remote(&store, "task", "ssh").await;
    let mut choices = intent(&source);
    choices.destination_path = None;
    let id = uuid::Uuid::new_v4().to_string();
    let pending = store
        .begin_remote_workspace_relocation(&id, &source, choices)
        .await
        .unwrap();
    project.id = "other-project".into();
    store.upsert_project(project.clone()).await.unwrap();
    let mut foreign = workspace("foreign", "ssh", "/owner/occupied", WorkspaceKind::Linked);
    foreign.project_id = project.id;
    store.insert_workspace(foreign).await.unwrap();
    let mut resolved = pending.clone();
    resolved.destination_path = Some("/owner/occupied".into());
    let mut preparation = owner_receipt(&resolved);
    preparation.phase = crate::runtime::WorkspaceRelocationPhase::Prepared;
    assert!(store
        .record_remote_workspace_relocation_preparation(&id, &preparation)
        .await
        .is_err());
    let retained = store
        .find_remote_workspace_relocation_intent(&id)
        .await
        .unwrap()
        .unwrap();
    assert!(retained.destination_path.is_none());
    assert!(retained.owner_preparation.is_none());
    preparation.destination.path = "/owner/free".into();
    store
        .record_remote_workspace_relocation_preparation(&id, &preparation)
        .await
        .unwrap();
    let mut competitor = workspace("competitor", "ssh", "/owner/free", WorkspaceKind::Linked);
    competitor.project_id = "other-project".into();
    assert!(store.insert_workspace(competitor).await.is_err());
}
