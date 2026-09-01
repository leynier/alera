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
