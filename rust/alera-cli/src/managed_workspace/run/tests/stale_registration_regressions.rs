use super::*;

#[tokio::test]
async fn workflow_worktrees_missing_checkout_does_not_block_unrelated_setup_or_removal() {
    let fixture = Fixture::new("").await;
    let original = fixture.integration().await;
    let identity = &original.identity;
    let path = Path::new(&identity.workspace.path);
    let moved = path.with_file_name("retained-workflow-checkout");
    let ordinary_path = path.with_file_name("ordinary-checkout");
    core_git::create_worktree(
        &identity.repo_path,
        "ordinary",
        ordinary_path.to_str().unwrap(),
        &identity.base_sha,
        false,
    )
    .unwrap();
    let mut ordinary = identity.workspace.clone();
    ordinary.id = Uuid::new_v4().to_string();
    ordinary.instance_id = Uuid::new_v4().to_string();
    ordinary.name = "Ordinary".into();
    ordinary.path = ordinary_path.to_string_lossy().into_owned();
    ordinary.branch = Some("ordinary".into());
    fixture
        .store
        .upsert_workspace(ordinary.clone())
        .await
        .unwrap();
    assert!(core_git::is_registered_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.workspace.id,
    )
    .unwrap());

    std::fs::rename(path, &moved).unwrap();
    let repo = git2::Repository::open(&identity.repo_path).unwrap();
    assert!(repo.find_worktree(&identity.workspace.id).is_ok());
    assert!(!core_git::is_registered_workflow_worktree(
        &identity.repo_path,
        &ordinary.path,
        &identity.workspace.id,
    )
    .unwrap());
    crate::worktree_setup::run_workspace_setup(&fixture.store, &ordinary.id, false)
        .await
        .unwrap();
    remove_managed_workspace(
        &fixture.store,
        ManagedWorkspaceRemoveRequest {
            id: ordinary.id,
            delete_branch: Some(true),
            active_workspace_id: None,
            close_sessions: true,
        },
    )
    .await
    .unwrap();
    assert!(!ordinary_path.exists());
    assert_eq!(
        std::fs::read_to_string(moved.join("shared.txt")).unwrap(),
        "initial"
    );
    assert!(repo.find_worktree(&identity.workspace.id).is_ok());
    assert!(core_git::branch_exists(
        &identity.repo_path,
        identity.workspace.branch.as_deref().unwrap(),
    )
    .unwrap());

    let mut alias = identity.workspace.clone();
    alias.id = Uuid::new_v4().to_string();
    alias.instance_id = Uuid::new_v4().to_string();
    alias.path = moved.to_string_lossy().into_owned();
    fixture.store.upsert_workspace(alias.clone()).await.unwrap();
    assert!(
        crate::worktree_setup::run_workspace_setup(&fixture.store, &alias.id, false)
            .await
            .is_err()
    );
    assert!(remove_managed_workspace(
        &fixture.store,
        ManagedWorkspaceRemoveRequest {
            id: alias.id,
            delete_branch: Some(true),
            active_workspace_id: None,
            close_sessions: true,
        },
    )
    .await
    .is_err());
    assert!(moved.exists());
}

#[cfg(unix)]
#[tokio::test]
async fn workflow_worktrees_unresolvable_checkout_still_fails_closed() {
    let fixture = Fixture::new("").await;
    let original = fixture.integration().await;
    let identity = &original.identity;
    let path = Path::new(&identity.workspace.path);
    let moved = path.with_file_name("retained-checkout");
    std::fs::rename(path, &moved).unwrap();
    std::os::unix::fs::symlink(path, path).unwrap();
    assert!(core_git::is_registered_workflow_worktree(
        &identity.repo_path,
        fixture.source.to_str().unwrap(),
        &identity.workspace.id,
    )
    .is_err());
    assert!(moved.join("shared.txt").exists());
}
