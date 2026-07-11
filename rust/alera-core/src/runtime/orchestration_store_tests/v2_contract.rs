use super::*;

use super::support::{store, task};

#[tokio::test]
async fn startup_failures_have_an_independent_three_attempt_budget() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("boot", vec![]))
        .await
        .unwrap();
    for attempt in 1..=3 {
        let dispatch = store
            .create_scoped_orchestration_dispatch(
                &created.id,
                &format!("worker_{attempt}"),
                None,
                "workspace_1",
                "coord",
                None,
                "return-immediately",
                "keep-open",
            )
            .await
            .unwrap();
        let failed = store
            .fail_orchestration_startup(&dispatch.id, "acceptance timeout")
            .await
            .unwrap();
        assert_eq!(failed.status, OrchestrationDispatchStatus::StartupFailed);
        let current = store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(current.startup_failure_count, attempt);
        assert_eq!(
            current.status,
            if attempt < 3 {
                OrchestrationTaskStatus::Ready
            } else {
                OrchestrationTaskStatus::Stalled
            }
        );
    }
}

#[tokio::test]
async fn expired_unaccepted_dispatch_consumes_startup_budget() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("accept", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &created.id,
            "worker",
            None,
            "workspace_1",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    sqlx::query(
        "UPDATE orchestrationDispatchContexts SET dispatched_at = '2020-01-01 00:00:00' WHERE id = ?",
    )
    .bind(&dispatch.id)
    .execute(store.pool())
    .await
    .unwrap();

    let expired = store
        .expire_unaccepted_orchestration_dispatches("2021-01-01 00:00:00")
        .await
        .unwrap();

    assert_eq!(expired.len(), 1);
    assert_eq!(
        expired[0].status,
        OrchestrationDispatchStatus::StartupFailed
    );
    let task = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Ready);
    assert_eq!(task.startup_failure_count, 1);
}

#[tokio::test]
async fn pending_spawn_timeout_cannot_reopen_an_actively_dispatched_task() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("boot race", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &created.id,
            "active-worker",
            None,
            "workspace_1",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();

    assert!(store
        .record_orchestration_task_startup_failure(&created.id, "stale spawn timeout")
        .await
        .is_err());
    let current = store
        .orchestration_task_by_id(&created.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(current.status, OrchestrationTaskStatus::Dispatched);
    assert_eq!(current.startup_failure_count, 0);
    assert_eq!(
        store
            .active_orchestration_dispatch_for_task(&created.id)
            .await
            .unwrap()
            .unwrap()
            .id,
        dispatch.id
    );
}

#[tokio::test]
async fn latest_dispatch_retains_acceptance_after_fast_completion() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("fast", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &created.id,
            "fast-worker",
            None,
            "workspace_1",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&dispatch.id, "fast-worker", "")
        .await
        .unwrap();
    store
        .complete_orchestration_dispatch(&dispatch.id, "fast-worker", r#"{"summary":"done"}"#)
        .await
        .unwrap();

    assert!(store
        .active_orchestration_dispatch_for_handle("fast-worker")
        .await
        .unwrap()
        .is_none());
    let latest = store
        .latest_orchestration_dispatch_for_handle("fast-worker")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(latest.status, OrchestrationDispatchStatus::Completed);
    assert!(latest.accepted_at.is_some());
}

#[tokio::test]
async fn cancellation_is_atomic_and_propagates_to_unstarted_descendants() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&root.id, "worker")
        .await
        .unwrap();
    let cancelled = store
        .cancel_orchestration_task(&root.id, "no longer needed")
        .await
        .unwrap();
    assert_eq!(cancelled.status, OrchestrationTaskStatus::Cancelled);
    assert_eq!(
        store
            .orchestration_task_by_id(&child.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Cancelled
    );
    assert_eq!(
        store
            .orchestration_dispatch_by_id(&dispatch.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationDispatchStatus::Cancelled
    );
}

#[tokio::test]
async fn task_created_after_dependency_cancellation_is_cancelled_immediately() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    store
        .cancel_orchestration_task(&root.id, "no longer needed")
        .await
        .unwrap();

    let child = store
        .create_orchestration_task(task("late child", vec![root.id]))
        .await
        .unwrap();

    assert_eq!(child.status, OrchestrationTaskStatus::Cancelled);
    assert_eq!(child.result.as_deref(), Some("dependency cancelled"));
    assert!(child.cancelled_at.is_some());
    assert!(child.completed_at.is_some());
}

#[tokio::test]
async fn cancelling_completed_task_does_not_cancel_descendants() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    store
        .update_orchestration_task_status(&root.id, OrchestrationTaskStatus::Completed, None)
        .await
        .unwrap();

    assert!(store
        .cancel_orchestration_task(&root.id, "too late")
        .await
        .is_err());
    assert_eq!(
        store
            .orchestration_task_by_id(&child.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Ready
    );
}

#[tokio::test]
async fn cancellation_closes_pending_gates_without_reopening_task() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("gated", vec![]))
        .await
        .unwrap();
    let gate = store
        .create_orchestration_gate(&created.id, "Proceed?", &[])
        .await
        .unwrap();

    let cancelled = store
        .cancel_orchestration_task(&created.id, "stop")
        .await
        .unwrap();

    assert_eq!(cancelled.status, OrchestrationTaskStatus::Cancelled);
    assert_eq!(
        store
            .orchestration_gate_by_id(&gate.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationGateStatus::Timeout
    );
    assert!(store
        .resolve_orchestration_gate(&gate.id, "yes")
        .await
        .is_err());
    assert_eq!(
        store
            .orchestration_task_by_id(&created.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Cancelled
    );
}

#[tokio::test]
async fn coordinator_runs_are_unique_per_workspace_not_globally() {
    let (_dir, store) = store().await;
    let first = store
        .create_scoped_orchestration_coordinator_run("one", Some("a"), 2000, "ws_1", 4)
        .await
        .unwrap();
    let second = store
        .create_scoped_orchestration_coordinator_run("two", Some("b"), 2000, "ws_2", 4)
        .await
        .unwrap();
    assert_ne!(first.id, second.id);
    assert!(store
        .create_scoped_orchestration_coordinator_run("duplicate", Some("c"), 2000, "ws_1", 4)
        .await
        .is_err());
}

#[tokio::test]
async fn dispatch_activity_refreshes_its_coordinator_run() {
    let (_dir, store) = store().await;
    let run = store
        .create_scoped_orchestration_coordinator_run("run", Some("coord"), 2000, "ws_1", 4)
        .await
        .unwrap();
    let mut new_task = task("active", vec![]);
    new_task.run_id = Some(run.id.clone());
    let created = store.create_orchestration_task(new_task).await.unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &created.id,
            "worker",
            Some(&run.id),
            "ws_1",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&dispatch.id, "worker", "")
        .await
        .unwrap();
    sqlx::query(
        "UPDATE orchestrationCoordinatorRuns SET last_activity_at = '2020-01-01 00:00:00' WHERE id = ?",
    )
    .bind(&run.id)
    .execute(store.pool())
    .await
    .unwrap();

    assert!(store
        .record_orchestration_activity(&dispatch.id)
        .await
        .unwrap());
    let refreshed = store
        .orchestration_coordinator_run_by_id(&run.id)
        .await
        .unwrap()
        .unwrap();
    assert_ne!(refreshed.last_activity_at, "2020-01-01 00:00:00");
}

#[tokio::test]
async fn dispatch_failure_obsoletes_its_queued_messages() {
    let (_dir, store) = store().await;
    let created = store
        .create_orchestration_task(task("retry", vec![]))
        .await
        .unwrap();
    let dispatch = store
        .create_orchestration_dispatch(&created.id, "worker")
        .await
        .unwrap();
    let mut queued = message("coord", "worker", OrchestrationMessageType::Status);
    queued.task_id = Some(created.id.clone());
    queued.dispatch_id = Some(dispatch.id.clone());
    let queued = store.insert_orchestration_message(queued).await.unwrap();

    store
        .fail_orchestration_dispatch(&dispatch.id, "retry")
        .await
        .unwrap();

    assert_eq!(
        store
            .orchestration_message_by_id(&queued.id)
            .await
            .unwrap()
            .unwrap()
            .state,
        "obsolete"
    );
    assert!(store
        .undelivered_unread_orchestration_messages("worker")
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn outbox_refreshes_expired_message_state() {
    let (_dir, store) = store().await;
    let mut expired = message("worker", "coord", OrchestrationMessageType::Status);
    expired.expires_at = Some("2020-01-01 00:00:00".to_string());
    let expired = store.insert_orchestration_message(expired).await.unwrap();

    let outbox = store
        .all_orchestration_messages_from_handle("worker", 10)
        .await
        .unwrap();

    assert_eq!(outbox[0].id, expired.id);
    assert_eq!(outbox[0].state, "expired");
}

#[tokio::test]
async fn dedicated_completion_is_idempotent_and_promotes_dependencies() {
    let (_dir, store) = store().await;
    let root = store
        .create_orchestration_task(task("root", vec![]))
        .await
        .unwrap();
    let child = store
        .create_orchestration_task(task("child", vec![root.id.clone()]))
        .await
        .unwrap();
    let dispatch = store
        .create_scoped_orchestration_dispatch(
            &root.id,
            "worker",
            None,
            "workspace_1",
            "coord",
            None,
            "return-immediately",
            "keep-open",
        )
        .await
        .unwrap();
    store
        .accept_orchestration_dispatch(&dispatch.id, "worker", "")
        .await
        .unwrap();
    let first = store
        .complete_orchestration_dispatch(&dispatch.id, "worker", r#"{"summary":"done"}"#)
        .await
        .unwrap();
    let second = store
        .complete_orchestration_dispatch(&dispatch.id, "worker", r#"{"summary":"done"}"#)
        .await
        .unwrap();
    assert_eq!(first, second);
    assert_eq!(
        store
            .orchestration_task_by_id(&child.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        OrchestrationTaskStatus::Ready
    );
}
