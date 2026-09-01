use super::*;

async fn inspect_workflow(
    store: &RuntimeStore,
    request: &LaunchWorkflowTask,
) -> TaskWorkflowInspection {
    store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: request.run_id.clone(),
            task_id: request.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap()
        .workflow
        .unwrap()
}

async fn snapshot_workflow_state(store: &RuntimeStore, request: &LaunchWorkflowTask) -> String {
    store
        .orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
            run_id: request.run_id.clone(),
            after_task_id: None,
            revision: None,
            limit: None,
        })
        .await
        .unwrap()
        .tasks
        .into_iter()
        .find(|task| task.id == request.task_id)
        .unwrap()
        .workflow_state
        .unwrap()
}

async fn board_bucket(store: &RuntimeStore) -> OrchestrationBoardBucket {
    store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap()
        .items[0]
        .bucket
}

#[tokio::test]
async fn workflow_prepared_attempts_project_the_execution_workspace_before_launch() {
    let (_dir, store, request) = prepared().await;
    let workspace = store
        .workflow_workspace(&request.workspace_id)
        .await
        .unwrap();

    let ready = inspect_workflow(&store, &request).await;
    assert_eq!(ready.state, "ready");
    assert_eq!(snapshot_workflow_state(&store, &request).await, "ready");
    assert_eq!(ready.execution_workspace_id, request.workspace_id);
    assert_eq!(
        ready.worktree.as_deref(),
        Some(workspace.identity.workspace.path.as_str())
    );
    assert_eq!(ready.branch, workspace.identity.workspace.branch);
    assert_eq!(
        ready.base_sha.as_deref(),
        Some(workspace.identity.base_sha.as_str())
    );
    assert!(ready.error.is_none());

    store
        .transition_workflow_workspace(
            &request.workspace_id,
            request.revision,
            WorkflowWorkspacePhase::Ready,
            WorkflowWorkspacePhase::Attention,
            None,
            Some("Project setup failed"),
        )
        .await
        .unwrap();
    let attention = inspect_workflow(&store, &request).await;
    assert_eq!(attention.state, "attention");
    assert_eq!(attention.execution_workspace_id, request.workspace_id);
    assert_eq!(attention.error.as_deref(), Some("Project setup failed"));
    assert_eq!(snapshot_workflow_state(&store, &request).await, "attention");
}

#[tokio::test]
async fn workflow_retry_workspace_supersedes_attention_from_its_failed_launch() {
    let (dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&launch.id).await.unwrap();
    store
        .mark_workflow_launch_started(&launch.id)
        .await
        .unwrap();
    store
        .settle_workflow_launch_without_session(&launch.terminal_handle, "host restarted")
        .await
        .unwrap();
    assert_eq!(
        board_bucket(&store).await,
        OrchestrationBoardBucket::Attention
    );

    let previous = store
        .workflow_workspace(&request.workspace_id)
        .await
        .unwrap();
    let other_task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'verify'",
    )
    .bind(&request.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let mut unrelated = previous.identity.clone();
    unrelated.workspace.id = uuid::Uuid::new_v4().to_string();
    unrelated.workspace.path = dir
        .path()
        .join(&unrelated.workspace.id)
        .to_string_lossy()
        .into_owned();
    unrelated.task_id = Some(other_task.clone());
    unrelated.attempt = previous.identity.attempt + 1;
    sqlx::query(
        "INSERT INTO workflowWorkspaces(id, run_id, revision, task_id, attempt, path, identity, phase)
         VALUES(?, ?, ?, ?, ?, ?, ?, 'ready')",
    )
    .bind(&unrelated.workspace.id)
    .bind(&request.run_id)
    .bind(request.revision)
    .bind(&other_task)
    .bind(unrelated.attempt)
    .bind(&unrelated.workspace.path)
    .bind(serde_json::to_string(&unrelated).unwrap())
    .execute(store.pool())
    .await
    .unwrap();
    assert_eq!(
        board_bucket(&store).await,
        OrchestrationBoardBucket::Attention
    );

    let mut candidate = store.find_workspace("workspace").await.unwrap().unwrap();
    candidate.id = uuid::Uuid::new_v4().to_string();
    candidate.instance_id = uuid::Uuid::new_v4().to_string();
    candidate.path = dir
        .path()
        .join(&candidate.id)
        .to_string_lossy()
        .into_owned();
    candidate.branch = Some(format!("alera/workflows/{}", candidate.id));
    candidate.kind = WorkspaceKind::Linked;
    let retry = store
        .reserve_workflow_workspace(
            &PrepareWorkflowWorkspace {
                request_id: "prepare-retry".into(),
                run_id: request.run_id,
                revision: request.revision,
                task_id: Some(request.task_id),
                retry_of: Some(previous.identity.workspace.id),
            },
            candidate,
        )
        .await
        .unwrap();
    for (old, new) in [
        (
            WorkflowWorkspacePhase::Reserved,
            WorkflowWorkspacePhase::Creating,
        ),
        (
            WorkflowWorkspacePhase::Creating,
            WorkflowWorkspacePhase::Created,
        ),
        (
            WorkflowWorkspacePhase::Created,
            WorkflowWorkspacePhase::Ready,
        ),
    ] {
        store
            .transition_workflow_workspace(
                &retry.identity.workspace.id,
                retry.identity.revision,
                old,
                new,
                None,
                None,
            )
            .await
            .unwrap();
    }
    assert_eq!(board_bucket(&store).await, OrchestrationBoardBucket::Active);
}

#[tokio::test]
async fn workflow_launch_projects_active_attempts_without_masking_a_ready_result() {
    let (_dir, store, request) = prepared().await;
    let frozen = store.validate_workflow_launch(&request).await.unwrap();
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
        .await
        .unwrap();
    for expected in ["reserved", "starting", "started"] {
        let workflow = inspect_workflow(&store, &request).await;
        assert_eq!(workflow.state, expected);
        assert_eq!(workflow.execution_workspace_id, request.workspace_id);
        assert_eq!(
            workflow.worktree.as_deref(),
            Some(frozen.workspace.workspace.path.as_str())
        );
        assert_eq!(
            workflow.branch.as_deref(),
            frozen.workspace.workspace.branch.as_deref()
        );
        assert_eq!(workflow.base_sha.as_deref(), Some(launch.base_sha.as_str()));
        assert_eq!(snapshot_workflow_state(&store, &request).await, expected);
        match expected {
            "reserved" => {
                store.claim_workflow_launch(&launch.id).await.unwrap();
            }
            "starting" => {
                store
                    .mark_workflow_launch_started(&launch.id)
                    .await
                    .unwrap();
            }
            _ => {}
        }
    }
    sqlx::query("UPDATE orchestrationTasks SET status = 'completed', result = ? WHERE id = ?")
        .bind(r#"{"summary":"Done","completionKind":"success","artifacts":[],"validation":[]}"#)
        .bind(&request.task_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert_eq!(
        inspect_workflow(&store, &request).await.state,
        "result_ready"
    );
    assert_eq!(
        snapshot_workflow_state(&store, &request).await,
        "result_ready"
    );
}

#[tokio::test]
async fn workflow_stalls_override_the_started_launch_in_task_projections() {
    let (_dir, store, request) = prepared().await;
    let (launch, _) = store
        .reserve_workflow_launch(&request, &"a".repeat(64))
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

    let stalled = store
        .stall_expired_orchestration_dispatches("2999-01-01 00:00:00")
        .await
        .unwrap();
    assert_eq!(stalled.len(), 1);
    assert_eq!(
        store.workflow_launch(&launch.id).await.unwrap().status,
        WorkflowLaunchStatus::Started
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
    assert_eq!(inspect_workflow(&store, &request).await.state, "stalled");
    assert_eq!(snapshot_workflow_state(&store, &request).await, "stalled");
}
