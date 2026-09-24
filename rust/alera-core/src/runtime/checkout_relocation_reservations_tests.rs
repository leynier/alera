use super::*;

#[tokio::test]
async fn competing_projects_cannot_prepare_the_same_unbound_destination() {
    let (_directory, store, mut project) = fixture().await;
    let first = prepared(&store).await;
    store.begin_workspace_relocation(&first).await.unwrap();
    project.id = "another-project".into();
    project.repo_path = "/another-repository".into();
    store.upsert_project(project).await.unwrap();
    let mut source = workspace(
        "foreign",
        "local",
        "/another-repository",
        WorkspaceKind::Main,
    );
    source.project_id = "another-project".into();
    let source = store.insert_workspace(source).await.unwrap();
    let mut destination = source.clone();
    destination.path = first.destination.path.clone();
    destination.kind = WorkspaceKind::Linked;
    let second = WorkspaceRelocation {
        id: "second-relocation".into(),
        source,
        destination,
        repository_path: "/another-repository".into(),
        ..first
    };
    assert!(store.begin_workspace_relocation(&second).await.is_err());
    assert!(store
        .find_workspace_relocation(&second.id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn reserved_destination_survives_restart_and_is_scoped_to_its_host() {
    let (directory, store, mut project) = fixture().await;
    let journal = prepared(&store).await;
    store.begin_workspace_relocation(&journal).await.unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    project.id = "another-project".into();
    reopened.upsert_project(project).await.unwrap();
    let mut foreign = workspace(
        "foreign",
        "local",
        &journal.destination.path,
        WorkspaceKind::Linked,
    );
    foreign.project_id = "another-project".into();
    assert!(reopened.insert_workspace(foreign.clone()).await.is_err());
    assert!(reopened.find_workspace("foreign").await.unwrap().is_none());
    foreign.host_id = "another-host".into();
    reopened.insert_workspace(foreign).await.unwrap();
    reopened
        .insert_workspace(workspace("sibling", "local", "/repo", WorkspaceKind::Main))
        .await
        .unwrap();
}

#[tokio::test]
async fn retiring_linked_checkout_cannot_be_adopted_before_cleanup_is_confirmed() {
    let (_directory, store, _) = fixture().await;
    let hand_off = prepared(&store).await;
    store.begin_workspace_relocation(&hand_off).await.unwrap();
    let hand_off = ready(&store, hand_off).await;
    store.commit_workspace_relocation(&hand_off).await.unwrap();
    let committed = store
        .find_workspace_relocation(&hand_off.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();

    let hand_on = WorkspaceRelocation {
        id: "hand-on".into(),
        source: store.find_workspace("task").await.unwrap().unwrap(),
        destination: hand_off.source.clone(),
        original_branch: "topic".into(),
        phase: Phase::Prepared,
        ..hand_off
    };
    store.begin_workspace_relocation(&hand_on).await.unwrap();
    let hand_on = ready(&store, hand_on).await;
    store.commit_workspace_relocation(&hand_on).await.unwrap();
    let candidate = workspace(
        "adopt",
        "local",
        &hand_on.source.path,
        WorkspaceKind::Linked,
    );
    assert!(store.insert_workspace(candidate.clone()).await.is_err());
    let committed = store
        .find_workspace_relocation(&hand_on.id)
        .await
        .unwrap()
        .unwrap();
    let removing = store
        .advance_workspace_relocation(&committed, Phase::RemovingSource, None)
        .await
        .unwrap();
    assert!(store.insert_workspace(candidate.clone()).await.is_err());
    store
        .advance_workspace_relocation(&removing, Phase::Completed, None)
        .await
        .unwrap();
    store.insert_workspace(candidate).await.unwrap();
}

#[tokio::test]
async fn relocation_cannot_reserve_another_projects_bound_worktree() {
    let (_directory, store, mut project) = fixture().await;
    let journal = prepared(&store).await;
    project.id = "another-project".into();
    store.upsert_project(project).await.unwrap();
    let mut foreign = workspace(
        "foreign",
        "local",
        &journal.destination.path,
        WorkspaceKind::Linked,
    );
    foreign.project_id = "another-project".into();
    store.insert_workspace(foreign).await.unwrap();
    assert!(store.begin_workspace_relocation(&journal).await.is_err());
    assert!(store
        .find_workspace_relocation(&journal.id)
        .await
        .unwrap()
        .is_none());
}
