use super::*;

#[tokio::test]
async fn workflow_launch_refuses_stale_approval_and_keeps_uncertain_attempt_reserved() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    sqlx::query("UPDATE workflowRuns SET status = 'cancelled' WHERE run_id = ?")
        .bind(&request.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store.claim_workflow_launch(&launch.id).await.is_err());
    let attention = store
        .workflow_launch_attention(&launch.id, "Host restarted before launch confirmation")
        .await
        .unwrap();
    assert_eq!(attention.status, WorkflowLaunchStatus::Attention);
    assert!(store.claim_workflow_launch(&launch.id).await.is_err());
    assert_eq!(
        store
            .workflow_workspace(&request.workspace_id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Ready
    );
    assert!(
        !store
            .reserve_workflow_launch(&request, &"a".repeat(64))
            .await
            .unwrap()
            .1
    );
}

#[tokio::test]
async fn workflow_launch_refuses_foreign_attempt_and_unintegrated_dependencies() {
    let (_dir, store, request) = prepared().await;
    let mut changed = request.clone();
    changed.workspace_id = "workspace".into();
    assert!(store.validate_workflow_launch(&changed).await.is_err());
    changed = request.clone();
    changed.task_id = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'verify'",
    )
    .bind(&request.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert!(store
        .validate_workflow_launch(&changed)
        .await
        .unwrap_err()
        .to_string()
        .contains("integrated"));
    assert!(store
        .reserve_workflow_launch(&request, "not-a-hash")
        .await
        .is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowLaunches")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}
