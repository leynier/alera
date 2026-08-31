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
