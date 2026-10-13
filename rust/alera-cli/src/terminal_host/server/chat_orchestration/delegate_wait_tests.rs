use alera_core::runtime::{ChatOrchestrationNotify, ChatOrchestrationTaskStatus as Status};
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

fn wait_payload(id: &str, seconds: u64) -> Value {
    let mut payload = delegate_payload(id, json!({"workspace": {"workspaceId": "ws-a"}}));
    payload.as_object_mut().unwrap().remove("notify");
    payload["mode"] = json!("wait");
    payload["waitSeconds"] = json!(seconds);
    payload
}

async fn prepared_child(harness: &mut TestHarness) -> (String, String) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let (change, _) = harness.events.recv().await.unwrap();
            let id = change["taskId"].as_str().unwrap();
            let task = harness
                .store
                .chat_orchestration_task(id)
                .await
                .unwrap()
                .unwrap();
            if let Some(child) = task.child_chat_id {
                return (task.task_id, child);
            }
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn delegate_wait_returns_and_acknowledges_a_settled_result_without_a_parent_wake() {
    let mut harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Wait for the child's result.")
        .await;
    let caller = harness.agent(&parent).await;
    let service = harness.service.clone();
    let delegation = tokio::spawn(async move {
        service
            .handle("delegate", &wait_payload("bounded-result", 50), &caller)
            .await
    });
    let (task_id, child) = prepared_child(&mut harness).await;
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Result returned in the bounded wait.");
    let result = tokio::time::timeout(TEST_DEADLINE, delegation)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(result["taskId"], task_id);
    assert_eq!(result["status"], "completed");
    assert_eq!(
        result["result"]["text"],
        "Result returned in the bounded wait."
    );
    assert_eq!(result["resultDelivery"], "acknowledged");
    assert!(harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        harness.control(&parent).await.turns.lock().unwrap().len(),
        1
    );
    harness.finish().await;
}

#[tokio::test]
async fn zero_second_delegate_wait_restores_notifications_and_later_completion_offers_one_wake() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(
            &parent,
            "parent",
            "Stay busy while a bounded wait times out.",
        )
        .await;
    let caller = harness.agent(&parent).await;
    let result = tokio::time::timeout(
        TEST_DEADLINE,
        harness
            .service
            .handle("delegate", &wait_payload("bounded-timeout", 0), &caller),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(result["timedOut"], true);
    let task_id = result["taskId"].as_str().unwrap();
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(task_id)
            .await
            .unwrap()
            .unwrap()
            .notify,
        ChatOrchestrationNotify::Always
    );
    let control = harness
        .control(result["childChatId"].as_str().unwrap())
        .await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Completion after timeout.");
    harness.task_status(task_id, Status::Completed).await;
    for _ in 0..2 {
        harness
            .service
            .handle("task", &json!({"taskId": task_id}), &human("desktop"))
            .await
            .unwrap();
        let wakes = harness
            .store
            .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
            .await
            .unwrap();
        assert_eq!(wakes.len(), 1);
        assert_eq!(wakes[0].entries.len(), 1);
        assert_eq!(wakes[0].entries[0].task_id, task_id);
    }
    assert!(harness
        .control(&parent)
        .await
        .interrupts
        .lock()
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn delegate_wait_returns_needs_input_without_spending_the_fifty_second_budget() {
    let mut harness = TestHarness::new().await;
    let service = harness.service.clone();
    let delegation = tokio::spawn(async move {
        service
            .handle(
                "delegate",
                &wait_payload("needs-input", 50),
                &human("desktop"),
            )
            .await
    });
    let (_, child) = prepared_child(&mut harness).await;
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.request_input(1, "native-wait-question");
    let result = tokio::time::timeout(TEST_DEADLINE, delegation)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(result["status"], "needs_input");
    assert_eq!(result["timedOut"], false);
    assert_eq!(result["attention"], true);
    harness.finish().await;
}
