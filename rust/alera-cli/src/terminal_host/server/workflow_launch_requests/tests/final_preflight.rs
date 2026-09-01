use super::*;

async fn reject_after_prepare(
    fixture: &Fixture,
    input: &LaunchWorkflowTask,
    prepared: PreparedLaunch,
    expected_error: &str,
) {
    let PreparedLaunch::Fresh { ref record, .. } = prepared else {
        panic!("fresh launch required")
    };
    let launch_id = record.id.clone();
    let terminal = record.terminal_handle.clone();
    let dispatch_id = record.dispatch_id.clone();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut events) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_workflow_launch_prepared(1, 1, Ok(Box::new(prepared)))
        .await;
    let command = tokio::time::timeout(std::time::Duration::from_secs(10), events.recv())
        .await
        .unwrap()
        .unwrap();
    actor.handle(command).await;

    assert!(actor.sessions.is_empty());
    assert!(fixture
        .store
        .find_workspace_tab(&terminal)
        .await
        .unwrap()
        .is_none());
    let launch = fixture.store.workflow_launch(&launch_id).await.unwrap();
    assert_eq!(launch.status, WorkflowLaunchStatus::Attention);
    assert!(launch.error.unwrap().contains(expected_error));
    assert_eq!(
        fixture
            .store
            .workflow_workspace(&input.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::StartupFailed
    );
    assert_eq!(
        fixture
            .store
            .orchestration_task_by_id(&input.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Pending
    );
}

fn commit_external_change(path: &str) -> String {
    let repo = git2::Repository::open(path).unwrap();
    std::fs::write(
        std::path::Path::new(path).join("external.txt"),
        "external commit",
    )
    .unwrap();
    let mut index = repo.index().unwrap();
    index
        .add_path(std::path::Path::new("external.txt"))
        .unwrap();
    let tree_id = index.write_tree().unwrap();
    let tree = repo.find_tree(tree_id).unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    let signature = git2::Signature::now("External", "external@example.com").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "external commit",
        &tree,
        &[&parent],
    )
    .unwrap()
    .to_string()
}

#[tokio::test]
async fn workflow_launch_rechecks_dirty_attempt_after_reservation() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let attempt = fixture
        .store
        .workflow_workspace(&input.workspace_id)
        .await
        .unwrap();
    let change = std::path::Path::new(&attempt.identity.workspace.path).join("external.txt");
    std::fs::write(&change, "pending external change").unwrap();

    reject_after_prepare(&fixture, &input, prepared, "attempt changed").await;
    assert_eq!(
        std::fs::read_to_string(&change).unwrap(),
        "pending external change"
    );
    assert!(matches!(
        launch::prepare(&fixture.store, &fixture.runtime, input.clone())
            .await
            .unwrap(),
        PreparedLaunch::Replay(_)
    ));
    let retry = fixture
        .request(Some("fix"), Some(&input.workspace_id))
        .await
        .unwrap();
    assert_eq!(retry.identity.attempt, 2);
}

#[tokio::test]
async fn workflow_launch_rechecks_attempt_tip_after_reservation() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let attempt = fixture
        .store
        .workflow_workspace(&input.workspace_id)
        .await
        .unwrap();
    let external_sha = commit_external_change(&attempt.identity.workspace.path);

    reject_after_prepare(&fixture, &input, prepared, "attempt tip changed").await;
    let repo = git2::Repository::open(&attempt.identity.workspace.path).unwrap();
    assert_eq!(
        repo.head().unwrap().target().unwrap().to_string(),
        external_sha
    );
}

#[tokio::test]
async fn workflow_launch_rechecks_dirty_integration_after_reservation() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let integration = fixture
        .store
        .workflow_integration_workspace(&input.run_id)
        .await
        .unwrap();
    let change = std::path::Path::new(&integration.identity.workspace.path).join("external.txt");
    std::fs::write(&change, "pending integration change").unwrap();

    reject_after_prepare(&fixture, &input, prepared, "integration workspace changed").await;
    assert_eq!(
        std::fs::read_to_string(&change).unwrap(),
        "pending integration change"
    );
}

#[tokio::test]
async fn workflow_launch_does_not_spawn_after_claim_is_cancelled() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    fixture
        .store
        .cancel_orchestration_task(&input.task_id, "cancel after claim")
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();

    actor
        .handle_workflow_launch_claimed(1, 1, record.clone(), token, locks, Ok(frozen))
        .await;

    assert!(actor.sessions.is_empty());
    assert!(fixture
        .store
        .find_workspace_tab(&record.terminal_handle)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        fixture
            .store
            .workflow_launch(&record.id)
            .await
            .unwrap()
            .status,
        WorkflowLaunchStatus::Attention
    );
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&record.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Cancelled
    );
}
