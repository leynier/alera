use super::{
    NewOrchestrationTask, OrchestrationDispatchStatus, OrchestrationGateStatus,
    OrchestrationTaskStatus, RuntimeStore,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

/// A dispatched task whose lease has expired, i.e. a stalled worker.
async fn stalled_task(store: &RuntimeStore) -> String {
    let task = store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "implement it".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: None,
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    store
        .create_orchestration_dispatch(&task.id, "worker-1")
        .await
        .unwrap();
    // A threshold in the future expires everything currently dispatched.
    let stalled = store
        .stall_expired_orchestration_dispatches("2999-01-01 00:00:00")
        .await
        .unwrap();
    assert_eq!(stalled.len(), 1);
    task.id
}

#[tokio::test]
async fn a_stall_gate_leaves_the_dispatch_and_the_task_alone() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;

    let gate = store
        .create_orchestration_stall_gate(&task_id, "still alive?", &["Keep Waiting".to_string()])
        .await
        .unwrap();
    assert_eq!(gate.status, OrchestrationGateStatus::Pending);

    // The worker may still be running, so nothing about it may be reported as
    // finished: the task stays stalled and the dispatch keeps its status.
    let task = store
        .orchestration_task_by_id(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Stalled);
    let dispatch = store
        .active_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(dispatch.status, OrchestrationDispatchStatus::Stalled);
}

#[tokio::test]
async fn an_ordinary_gate_still_refuses_a_stalled_task() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;

    let error = store
        .create_orchestration_gate(&task_id, "choose", &[])
        .await
        .unwrap_err();
    assert!(
        error.to_string().contains("cannot be gated"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn opening_a_stall_gate_twice_reuses_the_pending_one() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;

    let first = store
        .create_orchestration_stall_gate(&task_id, "still alive?", &[])
        .await
        .unwrap();
    let second = store
        .create_orchestration_stall_gate(&task_id, "still alive?", &[])
        .await
        .unwrap();
    assert_eq!(first.id, second.id);
}

#[tokio::test]
async fn a_stall_gate_needs_a_stalled_task() {
    let (_dir, store) = store().await;
    let task = store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "implement it".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: None,
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();

    assert!(store
        .create_orchestration_stall_gate(&task.id, "still alive?", &[])
        .await
        .is_err());
}

#[tokio::test]
async fn resolved_stall_gates_are_reported_until_the_task_leaves_stalled() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;
    let gate = store
        .create_orchestration_stall_gate(&task_id, "still alive?", &[])
        .await
        .unwrap();
    assert!(store.resolved_stall_gates().await.unwrap().is_empty());

    store
        .resolve_orchestration_gate(&gate.id, "Keep Waiting")
        .await
        .unwrap();
    let pending = store.resolved_stall_gates().await.unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].resolution.as_deref(), Some("Keep Waiting"));

    store
        .resume_stalled_orchestration_dispatch(&task_id)
        .await
        .unwrap();
    // Once the task is out of stalled the decision has been acted on.
    assert!(store.resolved_stall_gates().await.unwrap().is_empty());
}

#[tokio::test]
async fn resuming_restarts_the_lease_instead_of_re_stalling() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;

    store
        .resume_stalled_orchestration_dispatch(&task_id)
        .await
        .unwrap();

    let task = store
        .orchestration_task_by_id(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, OrchestrationTaskStatus::Dispatched);
    assert_eq!(task.stalled_at, None);
    let dispatch = store
        .active_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(dispatch.status, OrchestrationDispatchStatus::Dispatched);
    assert!(store
        .stalled_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn a_stalled_dispatch_is_reported_only_while_it_is_stalled() {
    let (_dir, store) = store().await;
    let task_id = stalled_task(&store).await;

    assert!(store
        .stalled_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .is_some());

    store
        .recover_stalled_orchestration_task(
            &task_id,
            OrchestrationTaskStatus::Ready,
            Some("coord"),
            "worker inspected and stopped",
            true,
        )
        .await
        .unwrap();
    assert!(store
        .stalled_orchestration_dispatch_for_task(&task_id)
        .await
        .unwrap()
        .is_none());
}
