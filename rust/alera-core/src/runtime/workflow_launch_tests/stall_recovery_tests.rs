use super::*;

#[tokio::test]
async fn workflow_stalled_tasks_require_launch_settlement() {
    let (_dir, store, request) = prepared().await;
    let context_hash = "a".repeat(64);
    let (launch, _) = store
        .reserve_workflow_launch(&request, &context_hash)
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&launch.dispatch_id, &launch.terminal_handle, &context_hash)
        .await
        .unwrap();
    assert_eq!(
        store
            .stall_expired_orchestration_dispatches("2999-01-01 00:00:00")
            .await
            .unwrap()
            .len(),
        1
    );

    for status in [
        OrchestrationTaskStatus::Ready,
        OrchestrationTaskStatus::Failed,
    ] {
        let error = store
            .recover_stalled_orchestration_task(
                &request.task_id,
                status,
                Some("coordinator"),
                "legacy recovery",
                true,
            )
            .await
            .unwrap_err();
        assert!(error.to_string().contains("terminal settlement"));
    }
    assert!(
        sqlx::query("UPDATE orchestrationTasks SET status = 'ready' WHERE id = ?")
            .bind(&request.task_id)
            .execute(store.pool())
            .await
            .is_err()
    );
    assert_eq!(
        store
            .orchestration_task_by_id(&request.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Stalled
    );
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&launch.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Stalled
    );

    store
        .settle_workflow_launch_without_session(
            &launch.terminal_handle,
            "The stalled workflow worker was terminated.",
        )
        .await
        .unwrap();
    assert_eq!(
        store.workflow_launch(&launch.id).await.unwrap().status,
        WorkflowLaunchStatus::Attention
    );
    assert_eq!(
        store
            .workflow_workspace(&request.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert_eq!(
        store
            .orchestration_task_by_id(&request.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Pending
    );
}

#[tokio::test]
async fn accepted_escalated_workflow_can_keep_waiting_after_a_stall() {
    let (dir, store, request) = prepared().await;
    let context_hash = "a".repeat(64);
    let (launch, _) = store
        .reserve_workflow_launch(&request, &context_hash)
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&launch.dispatch_id, &launch.terminal_handle, &context_hash)
        .await
        .unwrap();
    store
        .workflow_launch_attention(&launch.id, "Worker requested human help")
        .await
        .unwrap();
    assert_eq!(
        store
            .stall_expired_orchestration_dispatches("2999-01-01 00:00:00")
            .await
            .unwrap()
            .len(),
        1
    );

    // Simulate an existing database with the old acceptance guard; migration
    // must replace it rather than preserving CREATE TRIGGER IF NOT EXISTS.
    sqlx::query("DROP TRIGGER workflowDispatchAcceptance")
        .execute(store.pool())
        .await
        .unwrap();
    let remaining: Vec<String> = sqlx::query_scalar(
        "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'workflowDispatchAcceptance'",
    )
    .fetch_all(store.pool())
    .await
    .unwrap();
    assert!(
        remaining.is_empty(),
        "trigger remained after DROP: {remaining:?}"
    );
    sqlx::query("CREATE TRIGGER IF NOT EXISTS workflowDispatchAcceptance BEFORE UPDATE OF status ON orchestrationDispatchContexts
        WHEN NEW.status = 'dispatched' AND OLD.status = 'stalled'
        BEGIN SELECT RAISE(ABORT, 'stale acceptance trigger'); END")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .resume_stalled_orchestration_dispatch(&request.task_id)
        .await
        .is_err());
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    reopened
        .resume_stalled_orchestration_dispatch(&request.task_id)
        .await
        .unwrap();
    assert_eq!(
        reopened
            .orchestration_dispatch_by_id(&launch.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Dispatched
    );
    assert_eq!(
        reopened
            .orchestration_task_by_id(&request.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Dispatched
    );
    assert_eq!(
        reopened.workflow_launch(&launch.id).await.unwrap().status,
        WorkflowLaunchStatus::Attention
    );
}

#[tokio::test]
async fn unaccepted_attention_workflow_cannot_bypass_initial_acceptance() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    store
        .workflow_launch_attention(&launch.id, "Host did not confirm startup")
        .await
        .unwrap();
    assert!(sqlx::query(
        "UPDATE orchestrationDispatchContexts SET status = 'dispatched' WHERE id = ?"
    )
    .bind(&launch.dispatch_id)
    .execute(store.pool())
    .await
    .is_err());
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&launch.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::AwaitingAcceptance
    );
    // A fabricated stalled state without an acceptance receipt cannot use
    // the recovery exception to dispatch this worker either.
    sqlx::query("UPDATE orchestrationDispatchContexts SET status = 'stalled' WHERE id = ?")
        .bind(&launch.dispatch_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .resume_stalled_orchestration_dispatch(&request.task_id)
        .await
        .is_err());
}
