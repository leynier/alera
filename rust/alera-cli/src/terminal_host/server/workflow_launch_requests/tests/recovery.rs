use super::*;

#[tokio::test]
async fn workflow_launch_restart_settles_a_dispatch_that_already_failed() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh { record, locks, .. } = prepared else {
        panic!("fresh launch required")
    };
    drop(locks);
    fixture
        .store
        .claim_workflow_launch(&record.id)
        .await
        .unwrap();
    fixture
        .store
        .mark_workflow_launch_started(&record.id)
        .await
        .unwrap();
    sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'startup_failed' WHERE id = ?")
        .bind(&record.dispatch_id)
        .execute(fixture.store.pool())
        .await
        .unwrap();

    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    actor.reconcile_workflow_launches().await;

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
            .workflow_workspace(&input.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
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
    assert_eq!(
        fixture
            .request(Some("fix"), Some(&input.workspace_id))
            .await
            .unwrap()
            .identity
            .attempt,
        2
    );
}

#[tokio::test]
async fn stalled_workflow_failover_settles_before_a_fresh_attempt() {
    let fixture = Fixture::with_command("", "echo workflow-failover-test").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh {
        record,
        token,
        locks,
    } = prepared
    else {
        panic!("fresh launch required")
    };
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let frozen = launch::claim_and_validate(&fixture.store, &record)
        .await
        .unwrap();
    actor
        .spawn_workflow_launch(&record, &token, frozen)
        .await
        .unwrap();
    drop(locks);
    fixture
        .store
        .accept_orchestration_dispatch(
            &record.dispatch_id,
            &record.terminal_handle,
            &hex::encode(Sha256::digest(token.as_bytes())),
        )
        .await
        .unwrap();
    assert_eq!(
        fixture
            .store
            .stall_expired_orchestration_dispatches("2999-01-01 00:00:00")
            .await
            .unwrap()
            .len(),
        1
    );
    assert!(actor.sessions.contains_key(&record.terminal_handle));

    actor.failover_stalled_dispatch(&input.task_id).await;

    assert!(!actor.sessions.contains_key(&record.terminal_handle));
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
            .workflow_workspace(&input.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert_eq!(
        fixture
            .store
            .orchestration_dispatch_by_id(&record.dispatch_id)
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
    assert_eq!(
        fixture
            .request(Some("fix"), Some(&input.workspace_id))
            .await
            .unwrap()
            .identity
            .attempt,
        2
    );
}
