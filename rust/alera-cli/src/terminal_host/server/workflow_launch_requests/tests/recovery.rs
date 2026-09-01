use super::*;

#[tokio::test]
async fn workflow_launch_restart_settles_a_dispatch_that_already_failed() {
    let fixture = Fixture::new("").await;
    let (input, prepared) = prepared(&fixture).await;
    let PreparedLaunch::Fresh { record, .. } = prepared else {
        panic!("fresh launch required")
    };
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
