use std::time::Duration;

use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use crate::terminal_host::server::agent_chat_runtime::commands::ChatOp;

use super::test_support::{children, human, wait_idle, TestHarness, TEST_DEADLINE};

async fn awaiting(harness: &TestHarness, parent: &str) -> usize {
    harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(parent))
        .await
        .unwrap()
        .len()
}

fn wake_items(snapshot: &Value) -> usize {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["normalized"]["origin"]["kind"] == "orchestrationWake")
        .count()
}

async fn wait_for_wake(harness: &TestHarness, parent: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(parent).await.unwrap();
            if wake_items(&snapshot) > 0 && awaiting(harness, parent).await == 0 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("parent {parent} was not woken"));
}

/// A parent whose turn runs while its only child completes.
async fn busy_parent_with_a_finished_child(harness: &TestHarness) -> (String, String) {
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate and keep working.")
        .await;
    let tasks = children(harness, &parent, 1).await;
    let (task, child) = tasks[0].clone();
    harness.control(&child).await.complete(1, "Child result.");
    harness.task_status(&task, Status::Completed).await;
    (parent, task)
}

#[tokio::test]
async fn a_wake_waits_for_the_busy_parent_then_arrives_once_it_ends_its_turn() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let (parent, _) = busy_parent_with_a_finished_child(&harness).await;
    let parent_control = harness.control(&parent).await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    assert_eq!(awaiting(&harness, &parent).await, 1);
    assert!(harness.service.wake_pump.is_owed(&parent));

    parent_control.complete(1, "Parent turn done.");
    wait_for_wake(&harness, &parent).await;
    parent_control.wait_turns(2).await;
    assert!(parent_control.interrupts.lock().unwrap().is_empty());
    tokio::time::timeout(TEST_DEADLINE, async {
        while harness.service.wake_pump.is_owed(&parent) {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    harness.finish().await;
}

#[tokio::test]
async fn a_wake_waits_while_the_parent_has_background_work() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let (parent, _) = busy_parent_with_a_finished_child(&harness).await;
    let parent_control = harness.control(&parent).await;
    parent_control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "helper", "awaited": true}),
    );
    parent_control.complete(1, "Waiting on a helper.");
    wait_idle(&harness, &parent).await;
    // The helper keeps the session running, so nothing is delivered yet.
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(
        harness.runtime.snapshot(&parent).await.unwrap()["session"]["status"],
        "running"
    );
    assert_eq!(awaiting(&harness, &parent).await, 1);
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);

    parent_control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "helper", "status": "completed"}),
    );
    wait_for_wake(&harness, &parent).await;
    harness.finish().await;
}

#[tokio::test]
async fn awaiting_wakes_are_delivered_after_restart() {
    let harness = TestHarness::new().await;
    let (busy, _) = busy_parent_with_a_finished_child(&harness).await;
    let (idle, _) = busy_parent_with_a_finished_child(&harness).await;
    harness
        .control(&idle)
        .await
        .complete(1, "Idle before restart.");
    wait_idle(&harness, &idle).await;
    assert_eq!(awaiting(&harness, &busy).await, 1);
    assert_eq!(awaiting(&harness, &idle).await, 1);

    let harness = harness.restart().await;
    harness.runtime.recover_after_restart().await.unwrap();
    harness.start_wake_pump();
    wait_for_wake(&harness, &idle).await;
    // The busy parent's turn did not survive the restart, so it is idle now.
    wait_for_wake(&harness, &busy).await;
    harness.finish().await;
}

#[tokio::test]
async fn a_parent_stopped_within_the_grace_is_not_woken() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let (parent, _) = busy_parent_with_a_finished_child(&harness).await;
    let parent_control = harness.control(&parent).await;
    // An interrupt that is not a person's stop leaves the cohort, so the wake
    // only waits out the grace.
    harness
        .runtime
        .command(
            &parent,
            ChatOp::Interrupt { turn_id: None },
            human("desktop").ctx,
            None,
        )
        .await
        .unwrap();
    wait_idle(&harness, &parent).await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(awaiting(&harness, &parent).await, 1);
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    wait_for_wake(&harness, &parent).await;

    // A person's stop drops the cohort within the grace: no wake at all.
    let (stopped, _) = busy_parent_with_a_finished_child(&harness).await;
    let stopped_control = harness.control(&stopped).await;
    harness
        .service
        .handle(
            "interrupt",
            &json!({"requestId": "stop", "chatId": stopped}),
            &human("desktop"),
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert_eq!(awaiting(&harness, &stopped).await, 0);
    assert_eq!(stopped_control.turns.lock().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn shutdown_aborts_the_pump() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    assert!(harness.service.jobs.retained_handles() >= 1);
    assert!(harness.service.shutdown().await);
    assert_eq!(harness.service.jobs.retained_handles(), 0);
    harness.runtime.shutdown().await;
    harness.satellites.shutdown().await;
    harness.store.pool().close().await;
}
