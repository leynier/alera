use super::*;

fn cancel_command(run: &str) -> ControlWorkflowExecution {
    ControlWorkflowExecution {
        request_id: "cancel".into(),
        run_id: run.into(),
        revision: 1,
        expected_sequence: 0,
        action: WorkflowExecutionAction::Cancel,
    }
}

#[tokio::test]
async fn workflow_cancellation_fences_unsubmitted_correction_coordinators() {
    let (_dir, store, mut request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request.clone(), valid_profile)
        .await
        .unwrap();
    request.run_id = Some(plan.run_id.clone());
    request.expected_revision = Some(1);
    request.request_id = "correction".into();
    request.proposal.tasks.clear();
    let correction = store
        .create_workflow_proposal(request.clone(), valid_profile)
        .await
        .unwrap();
    let (coordinator, _) = store
        .reserve_workflow_coordinator(&correction)
        .await
        .unwrap();
    request.request_id = "not-started-correction".into();
    let waiting = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    store
        .control_workflow_execution(&cancel_command(&plan.run_id))
        .await
        .unwrap();
    assert!(store.reserve_workflow_coordinator(&waiting).await.is_err());
    let targets = store.workflow_cancellation_page().await.unwrap();
    assert_eq!(targets.len(), 1);
    assert_eq!(targets[0].terminal_handle, coordinator.tab_id);
    store
        .require_workflow_cancellation_target(&targets[0])
        .await
        .unwrap();
    store
        .settle_workflow_cancellation(&targets[0], None)
        .await
        .unwrap();
}

#[tokio::test]
async fn workflow_cancellation_is_durable_fences_launches_and_retains_resources() {
    let (dir, store, launch) = prepared().await;
    let (record, _) = store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap();
    let request = cancel_command(&launch.run_id);
    let (one, two) = tokio::join!(
        store.control_workflow_execution(&request),
        store.control_workflow_execution(&request)
    );
    assert_eq!(one.unwrap().sequence, 1);
    assert_eq!(two.unwrap().sequence, 1);
    assert!(store.claim_workflow_launch(&record.id).await.is_err());
    assert_eq!(
        store
            .orchestration_task_by_id(&launch.task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Cancelled
    );
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&record.dispatch_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Cancelled
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .control_workflow_execution(&request)
            .await
            .unwrap()
            .status,
        "cancelled"
    );
    let targets = reopened.workflow_cancellation_page().await.unwrap();
    assert_eq!(targets.len(), 1);
    let target = &targets[0];
    assert_eq!(target.terminal_handle, record.terminal_handle);
    assert!(reopened
        .find_workspace(&target.workspace_id)
        .await
        .unwrap()
        .is_some());
    assert!(reopened.workflow_launch(&record.id).await.is_ok());
    let snapshot = reopened
        .workflow_run_controls(&launch.run_id, Some(1))
        .await
        .unwrap();
    assert!(!snapshot.can_control);
    assert!(!snapshot.can_cancel);
    assert_eq!(snapshot.cancellation_pending, 1);
    let mut forged = target.clone();
    forged.workspace_id = "unrelated".into();
    assert!(reopened
        .settle_workflow_cancellation(&forged, None)
        .await
        .is_err());
    reopened
        .settle_workflow_cancellation(target, Some("live identity changed"))
        .await
        .unwrap();
    assert!(reopened
        .workflow_cancellation_page()
        .await
        .unwrap()
        .is_empty());
    assert!(
        reopened
            .workflow_run_controls(&launch.run_id, Some(1))
            .await
            .unwrap()
            .can_cancel
    );
    // Replaying the original receipt does not silently retry a later failure.
    reopened.control_workflow_execution(&request).await.unwrap();
    assert!(reopened
        .workflow_cancellation_page()
        .await
        .unwrap()
        .is_empty());
    let mut retry = request.clone();
    retry.request_id = "retry cancellation".into();
    retry.expected_sequence = 1;
    reopened.control_workflow_execution(&retry).await.unwrap();
    assert_eq!(
        reopened.workflow_cancellation_page().await.unwrap().len(),
        1
    );
    reopened
        .settle_workflow_cancellation(target, None)
        .await
        .unwrap();
    reopened
        .settle_workflow_cancellation(target, None)
        .await
        .unwrap();
    assert!(reopened
        .workflow_cancellation_page()
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        reopened
            .orchestration_coordinator_run_by_id(&launch.run_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationCoordinatorStatus::Stopped
    );
    retry.request_id = "must not resume".into();
    retry.expected_sequence = 2;
    retry.action = WorkflowExecutionAction::Start;
    assert!(reopened.control_workflow_execution(&retry).await.is_err());
}

#[tokio::test]
async fn workflow_cancellation_rejects_stale_revisions_and_preserves_completed_results() {
    let (_dir, store, launch) = prepared().await;
    sqlx::query(
        "UPDATE orchestrationTasks SET status='completed',result='retained result' WHERE id=?",
    )
    .bind(&launch.task_id)
    .execute(store.pool())
    .await
    .unwrap();
    let mut request = cancel_command(&launch.run_id);
    request.revision = 2;
    assert!(store.control_workflow_execution(&request).await.is_err());
    request.revision = 1;
    store.control_workflow_execution(&request).await.unwrap();
    let task = store
        .orchestration_task_by_id(&launch.task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Completed);
    assert_eq!(task.result.as_deref(), Some("retained result"));
    assert!(store.workflow_cancellation_page().await.unwrap().is_empty());
    assert_eq!(
        store
            .orchestration_coordinator_run_by_id(&launch.run_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationCoordinatorStatus::Stopped
    );
}

#[tokio::test]
async fn workflow_cancellation_can_close_an_unapproved_plan_without_materializing_tasks() {
    let (_dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    store
        .control_workflow_execution(&cancel_command(&plan.run_id))
        .await
        .unwrap();
    let snapshot = store
        .workflow_run_controls(&plan.run_id, Some(1))
        .await
        .unwrap();
    assert_eq!(snapshot.status, "cancelled");
    assert!(!snapshot.can_control);
    assert!(snapshot.stages.iter().all(|stage| !stage.can_review));
    let tasks: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks WHERE run_id=?")
        .bind(&plan.run_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(tasks, 0);
}

#[tokio::test]
async fn workflow_cancellation_includes_its_coordinator_but_not_other_proposals() {
    let (_dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request.clone(), valid_profile)
        .await
        .unwrap();
    let (coordinator, _) = store.reserve_workflow_coordinator(&draft).await.unwrap();
    request.request_id = "unrelated-proposal".into();
    let other = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (unrelated, _) = store.reserve_workflow_coordinator(&other).await.unwrap();
    let plan = store
        .submit_workflow_proposal(&draft.id, tasks)
        .await
        .unwrap();
    store
        .control_workflow_execution(&cancel_command(&plan.run_id))
        .await
        .unwrap();
    let targets = store.workflow_cancellation_page().await.unwrap();
    assert_eq!(targets.len(), 1);
    assert_eq!(targets[0].proposal_id.as_deref(), Some(draft.id.as_str()));
    assert!(targets[0].launch_id.is_none());
    assert_eq!(targets[0].terminal_handle, coordinator.tab_id);
    assert_ne!(targets[0].terminal_handle, unrelated.tab_id);
    store
        .require_workflow_cancellation_target(&targets[0])
        .await
        .unwrap();
    store
        .settle_workflow_cancellation(&targets[0], None)
        .await
        .unwrap();
    assert!(store
        .require_workflow_cancellation_target(&targets[0])
        .await
        .is_err());
    assert_eq!(
        store
            .workflow_run_controls(&plan.run_id, Some(1))
            .await
            .unwrap()
            .cancellation_pending,
        0
    );
}
