use super::*;
use crate::runtime::run_plan_tests::{control, desktop};

fn cancel_command(run: &str, sequence: i64) -> RunControl {
    RunControl {
        request_id: "cancel".into(),
        run_id: run.into(),
        expected_sequence: sequence,
        action: RunControlAction::Cancel,
        reason: None,
        task_ids: None,
    }
}

async fn sequence(store: &RuntimeStore, run: &str) -> i64 {
    sqlx::query_scalar("SELECT control_sequence FROM orchestrationCoordinatorRuns WHERE id = ?")
        .bind(run)
        .fetch_one(store.pool())
        .await
        .unwrap()
}

/// Settles the coordinator target a cancelled run always carries, leaving
/// only its attempt workers.
async fn settle_coordinator(store: &RuntimeStore) {
    for target in store.workflow_cancellation_page().await.unwrap() {
        if target.launch_id.is_none() {
            store
                .settle_workflow_cancellation(&target, None)
                .await
                .unwrap();
        }
    }
}

#[tokio::test]
async fn cancellation_targets_the_run_coordinator_and_fences_its_relaunch() {
    let (_dir, store, request) = fixture(false).await;
    let (created, fresh) = store
        .create_run(
            CreateRun {
                request_id: "create".into(),
                workspace_id: request.workspace_id.clone(),
                objective: "Coordinate".into(),
                recipe_source: Some(request.proposal.recipe_source.clone()),
                isolation: None,
                coordinator_profile_id: "profile".into(),
                role_profiles: request.proposal.role_profiles.clone(),
                worker_profile_id: None,
                max_concurrent: None,
                approval_required: true,
                stall_policy: None,
            },
            valid_profile,
            &desktop(),
        )
        .await
        .unwrap();
    assert!(fresh);
    let plan = created;
    let coordinator = store
        .workflow_coordinator(&plan.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        plan.coordinator_tab_id.as_deref(),
        Some(coordinator.tab_id.as_str())
    );
    assert_eq!(coordinator.status, "reserved");
    control(&store, &plan.run_id, RunControlAction::Cancel)
        .await
        .unwrap();
    assert!(store
        .require_workflow_coordinator_spawnable(&coordinator.tab_id)
        .await
        .is_err());
    let targets = store.workflow_cancellation_page().await.unwrap();
    assert_eq!(targets.len(), 1);
    assert!(targets[0].launch_id.is_none());
    assert_eq!(targets[0].terminal_handle, coordinator.tab_id);
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
    let run = store
        .orchestration_coordinator_run_by_id(&plan.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Cancelled);
    assert!(run.completed_at.is_some());
}

#[tokio::test]
async fn workflow_cancellation_is_durable_fences_launches_and_retains_resources() {
    let (dir, store, launch) = prepared().await;
    let (record, _) = store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap();
    let start = sequence(&store, &launch.run_id).await;
    let request = cancel_command(&launch.run_id, start);
    let actor = desktop();
    let (one, two) = tokio::join!(
        store.control_run(&request, &actor),
        store.control_run(&request, &actor)
    );
    assert_eq!(one.unwrap().sequence, start + 1);
    assert_eq!(two.unwrap().sequence, start + 1);
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
    settle_coordinator(&store).await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .control_run(&request, &desktop())
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
    // Replaying the original receipt does not silently retry a later failure.
    reopened.control_run(&request, &desktop()).await.unwrap();
    assert!(reopened
        .workflow_cancellation_page()
        .await
        .unwrap()
        .is_empty());
    let retry = RetryRunCancellation {
        request_id: "retry-cancellation".into(),
        run_id: launch.run_id.clone(),
        expected_sequence: start + 1,
    };
    reopened
        .retry_run_cancellation(&retry, &desktop())
        .await
        .unwrap();
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
    let run = reopened
        .orchestration_coordinator_run_by_id(&launch.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Cancelled);
    assert!(run.completed_at.is_some(), "the cancellation settled");
    assert!(control(&reopened, &launch.run_id, RunControlAction::Resume)
        .await
        .is_err());
    assert!(reopened
        .retry_run_cancellation(
            &RetryRunCancellation {
                request_id: "nothing-to-retry".into(),
                run_id: launch.run_id.clone(),
                expected_sequence: start + 2,
            },
            &desktop(),
        )
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_cancellation_preserves_completed_results() {
    let (_dir, store, launch) = prepared().await;
    sqlx::query(
        "UPDATE orchestrationTasks SET status='completed',result='retained result' WHERE id=?",
    )
    .bind(&launch.task_id)
    .execute(store.pool())
    .await
    .unwrap();
    let stale = cancel_command(&launch.run_id, 99);
    assert!(store.control_run(&stale, &desktop()).await.is_err());
    control(&store, &launch.run_id, RunControlAction::Cancel)
        .await
        .unwrap();
    let task = store
        .orchestration_task_by_id(&launch.task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Completed);
    assert_eq!(task.result.as_deref(), Some("retained result"));
    settle_coordinator(&store).await;
    assert!(store.workflow_cancellation_page().await.unwrap().is_empty());
    let run = store
        .orchestration_coordinator_run_by_id(&launch.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(run.status, OrchestrationCoordinatorStatus::Cancelled);
    assert!(run.completed_at.is_some(), "the cancellation settled");
}

#[tokio::test]
async fn workflow_cancellation_can_close_an_unapproved_plan() {
    let (_dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    control(&store, &plan.run_id, RunControlAction::Cancel)
        .await
        .unwrap();
    let pending: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM orchestrationTasks WHERE run_id=? AND status <> 'cancelled'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(pending, 0);
    let gates: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM runGates WHERE run_id=? AND status = 'pending'")
            .bind(&plan.run_id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(gates, 0);
}
