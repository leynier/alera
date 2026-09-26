use super::*;

#[tokio::test]
async fn workflow_cleanup_abandonment_allows_fresh_preview_after_head_drift() {
    let _serial = crate::terminal_host::server::workflow_cleanup_execution::CLEANUP_TEST_LOCK
        .lock()
        .await;
    let fixture = Fixture::new("").await;
    let resource = fixture.integration().await;
    let workspace = resource.identity.workspace.clone();
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-for-cleanup".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
    let git = alera_core::git::preview_workflow_cleanup(
        &resource.identity.repo_path,
        &workspace.path,
        &resource.identity.base_sha,
        &workspace.id,
    )
    .unwrap();
    let preview = fixture
        .store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &fixture.plan.run_id,
            vec![WorkflowCleanupItem {
                identity: resource.identity.clone(),
                git,
                remove_branch: false,
            }],
        )
        .await
        .unwrap();
    {
        let repo = git2::Repository::open(&workspace.path).unwrap();
        let parent = repo.head().unwrap().peel_to_commit().unwrap();
        let signature = git2::Signature::now("Test", "test@example.com").unwrap();
        repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            "external change",
            &parent.tree().unwrap(),
            &[&parent],
        )
        .unwrap();
    }
    let dir = tempfile::tempdir().unwrap();
    let (client, _responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(
            1,
            crate::terminal_host::server::ClientState::local(client, true),
        )]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store = alera_core::runtime::RuntimeStore::open(&fixture.runtime)
        .await
        .unwrap();
    actor.runtime_dir = fixture.runtime.clone();
    cleanup_and_wait(&mut actor, &preview, "workflows.applyCleanup", false).await;
    cleanup_and_wait(&mut actor, &preview, "workflows.retryCleanup", false).await;
    assert!(fixture
        .store
        .require_workspace_outside_cleanup(&workspace.id)
        .await
        .is_err());
    // Another actor-owned workspace operation must settle before claims release.
    actor.managed_workspace_jobs = 1;
    cleanup_and_wait(&mut actor, &preview, "workflows.abandonCleanup", false).await;
    assert!(fixture
        .store
        .require_workspace_outside_cleanup(&workspace.id)
        .await
        .is_err());
    actor.managed_workspace_jobs = 0;
    cleanup_and_wait(&mut actor, &preview, "workflows.abandonCleanup", true).await;
    cleanup_and_wait(&mut actor, &preview, "workflows.abandonCleanup", true).await;
    fixture
        .store
        .require_workspace_outside_cleanup(&workspace.id)
        .await
        .unwrap();
    assert!(std::path::Path::new(&workspace.path).exists());
    let git = alera_core::git::preview_workflow_cleanup(
        &resource.identity.repo_path,
        &workspace.path,
        &resource.identity.base_sha,
        &workspace.id,
    )
    .unwrap();
    let fresh = fixture
        .store
        .publish_workflow_cleanup_preview(
            &uuid::Uuid::new_v4().to_string(),
            &fixture.plan.run_id,
            vec![WorkflowCleanupItem {
                identity: resource.identity,
                git,
                remove_branch: false,
            }],
        )
        .await
        .unwrap();
    cleanup_and_wait(&mut actor, &fresh, "workflows.applyCleanup", true).await;
    assert!(!std::path::Path::new(&workspace.path).exists());
}
