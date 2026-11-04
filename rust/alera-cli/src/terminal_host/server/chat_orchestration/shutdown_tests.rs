use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{
    ChatOrchestrationTask, ChatOrchestrationTaskStatus as Status, ChatOrchestrationWakeStatus,
};
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::paused_runtime_fixture::{CommandGate, PausedChatRuntime};
use super::test_support::{error_code, human, CreationGate, TestHarness, TEST_DEADLINE};
use super::wakes::deliver_next_wake;

async fn dispose_test_actor(harness: &TestHarness) {
    let directory = tempfile::tempdir().unwrap();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &directory,
        Default::default(),
        Default::default(),
    )
    .await;
    actor.agent_chat_runtime = Some(harness.runtime.clone());
    actor.chat_orchestration = Some(harness.service.clone());
    tokio::time::timeout(TEST_DEADLINE, actor.dispose())
        .await
        .expect("host actor did not dispose before the fixture deadline");
    assert!(actor.disposed);
    assert!(harness.service.jobs.is_closed());
    assert_eq!(harness.service.jobs.retained_handles(), 0);
    actor.dispose().await;
    assert!(actor.disposed);
}

async fn linked_task(harness: &TestHarness, response: &Value) -> ChatOrchestrationTask {
    harness
        .control(response["childChatId"].as_str().unwrap())
        .await
        .wait_turns(1)
        .await;
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let task = harness
                .store
                .chat_orchestration_task(response["taskId"].as_str().unwrap())
                .await
                .unwrap()
                .unwrap();
            if task.child_turn_id.is_some() {
                break task;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("monitor did not link the provider's actual turn")
}

async fn committed_result(harness: &TestHarness, task: &ChatOrchestrationTask, result: &str) {
    let child = task.child_chat_id.as_deref().unwrap();
    harness.control(child).await.complete(1, result);
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let turn = harness
                .store
                .chat_orchestration_child_turn(child, task.child_turn_id.as_deref().unwrap())
                .await
                .unwrap()
                .unwrap();
            if turn.turn_status.as_deref() == Some("completed")
                && turn.final_assistant_text.as_deref() == Some(result)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("native completion did not commit before the fixture deadline");
}

#[tokio::test]
async fn graceful_dispose_quiesces_monitor_snapshots_before_actor_shutdown_and_recovers_durably() {
    let mut harness = TestHarness::new().await;
    let gate = CommandGate::for_operation(None, "runtime", "Snapshot");
    gate.set_armed(false);
    let observed = PausedChatRuntime::new(harness.service.runtime.clone(), gate.clone());
    harness.service = harness.service.clone().with_runtime(observed.clone());
    let mut tasks = Vec::new();
    let mut requests = Vec::new();
    for (id, workspace) in [
        ("first-running", "ws-a"),
        ("running", "ws-a"),
        ("remote", "ws-b"),
    ] {
        let payload = delegate_payload(id, json!({"workspace":{"workspaceId":workspace}}));
        let response = harness
            .service
            .handle("delegate", &payload, &human("desktop"))
            .await
            .unwrap();
        tasks.push(linked_task(&harness, &response).await);
        requests.push((payload, response));
    }
    gate.set_armed(true);
    tokio::time::timeout(TEST_DEADLINE, gate.arrived.notified())
        .await
        .unwrap();
    // A monitor snapshot crossing actor shutdown produced childUnavailable
    // with an actor save conflict in the original four-worker reproduction.
    dispose_test_actor(&harness).await;
    assert!(harness.service.shutdown().await);
    assert_eq!(harness.service.jobs.retained_handles(), 0);
    harness.satellites.shutdown().await;
    let child = tasks[1].child_chat_id.as_deref().unwrap();
    let closed_record = harness.store.agent_chat(child).await.unwrap().unwrap();
    let snapshots = observed.snapshot_calls.load(Ordering::Acquire);
    let launches = harness.factory.launches.lock().unwrap().len();
    gate.release.notify_one();
    harness.service.resume_task_monitors(&tasks);
    assert_eq!(
        error_code(
            &harness
                .service
                .handle(
                    "delegate",
                    &delegate_payload(
                        "after-shutdown",
                        json!({"newWorkspace":{"projectId":"project-a", "hostId":"local", "mode":"shared"}}),
                    ),
                    &human("desktop"),
                )
                .await
                .unwrap_err()
        ),
        "chat_orchestration_shutdown"
    );
    tokio::time::sleep(Duration::from_millis(250)).await;
    assert_eq!(observed.snapshot_calls.load(Ordering::Acquire), snapshots);
    assert_eq!(harness.factory.launches.lock().unwrap().len(), launches);
    assert!(harness.targets.created.lock().unwrap().is_empty());
    assert_eq!(
        harness
            .store
            .agent_chat(child)
            .await
            .unwrap()
            .unwrap()
            .cursor,
        closed_record.cursor
    );
    for task in &tasks {
        let durable = harness
            .store
            .chat_orchestration_task(&task.task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(durable.status, Status::Running);
        assert!(durable.error_code.is_none());
    }
    let harness = harness.restart().await;
    harness.runtime.recover_after_restart().await.unwrap();
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert_eq!(recovery.settled.len(), 2);
    assert_eq!(recovery.remote.len(), 1);
    assert_eq!(recovery.remote[0].task_id, tasks[2].task_id);
    assert_eq!(recovery.remote[0].host_id.as_deref(), Some("ssh-b"));
    for (task, status) in
        tasks
            .iter()
            .zip([Status::Interrupted, Status::Interrupted, Status::Running])
    {
        let recovered = harness
            .store
            .chat_orchestration_task(&task.task_id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(recovered.status, status);
    }
    for (payload, response) in requests {
        assert_eq!(
            harness
                .service
                .handle("delegate", &payload, &human("desktop"))
                .await
                .unwrap(),
            response
        );
    }
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(harness
        .store
        .recover_chat_orchestration()
        .await
        .unwrap()
        .settled
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn shutdown_stops_a_sealed_wake_before_send_and_preserves_its_restart_delivery() {
    let mut harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "approval-required").await;
    let gate = CommandGate::for_operation(Some(&parent), &format!("chat:{parent}"), "Send");
    let observed = PausedChatRuntime::new(harness.service.runtime.clone(), gate.clone());
    harness.service = harness.service.clone().with_runtime(observed.clone());
    let mut payload = delegate_payload(
        "wake-at-dispose",
        json!({"workspace":{"workspaceId":"ws-a"}}),
    );
    payload["parentChatId"] = json!(parent);
    payload["notify"] = json!("always");
    let response = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    let task = linked_task(&harness, &response).await;
    committed_result(&harness, &task, "Wake result survives disposal.").await;
    tokio::time::timeout(TEST_DEADLINE, gate.arrived.notified())
        .await
        .unwrap();
    let sealed = harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
        .await
        .unwrap();
    assert_eq!(sealed.len(), 1);
    assert_eq!(sealed[0].status, ChatOrchestrationWakeStatus::Sealed);
    let client_message_id = sealed[0].client_message_id.clone();
    let child_brief = (
        task.child_chat_id.clone().unwrap(),
        format!("chat-orchestration-task:{}", task.task_id),
    );
    assert_eq!(
        *observed.sent_messages.lock().unwrap(),
        vec![child_brief.clone()]
    );
    dispose_test_actor(&harness).await;
    assert_eq!(harness.service.jobs.retained_handles(), 0);
    let snapshots = observed.snapshot_calls.load(Ordering::Acquire);
    let launches = harness.factory.launches.lock().unwrap().len();
    gate.release.notify_one();
    harness.service.deliver_task_wake(&task).await;
    tokio::time::sleep(Duration::from_millis(250)).await;
    assert_eq!(*observed.sent_messages.lock().unwrap(), vec![child_brief]);
    assert_eq!(observed.snapshot_calls.load(Ordering::Acquire), snapshots);
    assert_eq!(harness.factory.launches.lock().unwrap().len(), launches);
    assert!(!harness
        .factory
        .launches
        .lock()
        .unwrap()
        .iter()
        .any(|launch| launch.chat_id == parent));
    let harness = harness.restart().await;
    harness.runtime.recover_after_restart().await.unwrap();
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert!(recovery.settled.is_empty());
    assert_eq!(recovery.wakes.len(), 1);
    assert_eq!(recovery.wakes[0].client_message_id, client_message_id);
    assert_eq!(
        recovery.wakes[0].status,
        ChatOrchestrationWakeStatus::Sealed
    );
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events
    )
    .await
    .unwrap());
    let parent_control = harness.control(&parent).await;
    parent_control.wait_turns(1).await;
    assert_eq!(harness.factory.launches.lock().unwrap().len(), 1);
    let delivered = harness
        .store
        .chat_orchestration_wake(&parent, sealed[0].generation)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(delivered.status, ChatOrchestrationWakeStatus::Delivered);
    assert_eq!(delivered.client_message_id, client_message_id);
    parent_control.complete(1, "Wake consumed once.");
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
            if snapshot["session"]["activeTurnId"].is_null() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("parent wake did not settle before the fixture deadline");
    assert!(!deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events,
    )
    .await
    .unwrap());
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    assert_eq!(harness.factory.launches.lock().unwrap().len(), 1);
    assert!(harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
        .await
        .unwrap()
        .is_empty());
    let task = harness
        .store
        .chat_orchestration_task(&task.task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.status, Status::Completed);
    assert_eq!(
        task.result_text.as_deref(),
        Some("Wake result survives disposal.")
    );
    harness.finish().await;
}

#[tokio::test]
async fn shutdown_aborts_admitted_preparation_without_failing_the_task_or_losing_its_receipt() {
    let harness = TestHarness::new().await;
    let gate = Arc::new(CreationGate {
        entered: tokio::sync::Notify::new(),
        resume: tokio::sync::Notify::new(),
    });
    *harness.targets.pause_creation.lock().unwrap() = Some(gate.clone());
    let payload = delegate_payload(
        "preparing-at-dispose",
        json!({"newWorkspace":{"projectId":"project-a", "hostId":"local", "mode":"shared"}}),
    );
    let service = harness.service.clone();
    let pending_payload = payload.clone();
    let pending = tokio::spawn(async move {
        service
            .handle("delegate", &pending_payload, &human("desktop"))
            .await
    });
    tokio::time::timeout(TEST_DEADLINE, gate.entered.notified())
        .await
        .unwrap();
    let before = harness
        .store
        .list_chat_orchestration_tasks(&Default::default())
        .await
        .unwrap();
    assert_eq!(before.tasks.len(), 1);
    let task_id = before.tasks[0].task_id.clone();
    assert_eq!(before.tasks[0].status, Status::Preparing);
    dispose_test_actor(&harness).await;
    let error = tokio::time::timeout(TEST_DEADLINE, pending)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    assert_eq!(error_code(&error), "chat_orchestration_shutdown");
    gate.resume.notify_one();
    tokio::time::sleep(Duration::from_millis(250)).await;
    let durable = harness
        .store
        .chat_orchestration_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(durable.status, Status::Preparing);
    assert!(durable.error_code.is_none());
    assert!(durable.child_chat_id.is_none());
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(harness.targets.created.lock().unwrap().len(), 1);
    let harness = harness.restart().await;
    harness.runtime.recover_after_restart().await.unwrap();
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert_eq!(recovery.settled.len(), 1);
    assert_eq!(recovery.settled[0].task_id, task_id);
    assert_eq!(recovery.settled[0].status, Status::Interrupted);
    let replay = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(replay["taskId"], task_id);
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(harness.targets.created.lock().unwrap().is_empty());
    harness.finish().await;
}
