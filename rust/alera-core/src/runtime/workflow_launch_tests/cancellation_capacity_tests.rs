use super::*;

#[tokio::test]
async fn cancelled_workflow_attempt_holds_capacity_until_settlement() {
    let (dir, store, mut proposal) = fixture(false).await;
    proposal.proposal.max_concurrent = 1;
    let mut other = proposal.proposal.tasks[0].clone();
    other.id = "other".into();
    other.title = "Other independent task".into();
    proposal.proposal.tasks.insert(1, other);
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    ready_workspace(&dir, &store, &plan, None).await;
    let first_task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'fix'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let other_task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'other'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let first_workspace = ready_workspace(&dir, &store, &plan, Some(first_task.clone())).await;
    let first_request = LaunchWorkflowTask {
        request_id: "launch-first".into(),
        run_id: plan.run_id.clone(),
        revision: plan.revision,
        task_id: first_task.clone(),
        workspace_id: first_workspace.identity.workspace.id.clone(),
    };
    let (launch, _) = store
        .reserve_workflow_launch(&first_request, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(
            &launch.dispatch_id,
            &launch.terminal_handle,
            &"a".repeat(64),
        )
        .await
        .unwrap();
    store
        .cancel_orchestration_task(&first_task, "cancelled by user")
        .await
        .unwrap();
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&launch.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Cancelled
    );
    assert_eq!(
        store
            .workflow_workspace(&first_workspace.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Ready
    );

    let mut blocked_candidate = store.find_workspace("workspace").await.unwrap().unwrap();
    blocked_candidate.id = uuid::Uuid::new_v4().to_string();
    blocked_candidate.instance_id = uuid::Uuid::new_v4().to_string();
    blocked_candidate.path = dir
        .path()
        .join(&blocked_candidate.id)
        .to_string_lossy()
        .into_owned();
    blocked_candidate.branch = Some(format!("alera/workflows/{}", blocked_candidate.id));
    blocked_candidate.kind = WorkspaceKind::Linked;
    let blocked = store
        .reserve_workflow_workspace(
            &PrepareWorkflowWorkspace {
                request_id: "prepare-other-blocked".into(),
                run_id: plan.run_id.clone(),
                revision: plan.revision,
                task_id: Some(other_task.clone()),
                retry_of: None,
            },
            blocked_candidate,
        )
        .await
        .unwrap_err();
    assert!(blocked.to_string().contains("concurrency"));

    sqlx::query("UPDATE workflowWorkspaces SET phase = 'attention' WHERE id = ?")
        .bind(&first_workspace.identity.workspace.id)
        .execute(store.pool())
        .await
        .unwrap();
    let other_workspace = ready_workspace(&dir, &store, &plan, Some(other_task.clone())).await;
    sqlx::query("UPDATE workflowWorkspaces SET phase = 'ready' WHERE id = ?")
        .bind(&first_workspace.identity.workspace.id)
        .execute(store.pool())
        .await
        .unwrap();
    let other_request = LaunchWorkflowTask {
        request_id: "launch-other".into(),
        run_id: plan.run_id.clone(),
        revision: plan.revision,
        task_id: other_task,
        workspace_id: other_workspace.identity.workspace.id,
    };
    assert!(store
        .validate_workflow_launch(&other_request)
        .await
        .unwrap_err()
        .to_string()
        .contains("concurrency"));

    store
        .settle_workflow_launch_without_session(
            &launch.terminal_handle,
            "The cancelled worker was terminated.",
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .workflow_workspace(&first_workspace.identity.workspace.id)
            .await
            .unwrap()
            .phase,
        WorkflowWorkspacePhase::Attention
    );
    assert!(store.validate_workflow_launch(&other_request).await.is_ok());
}
