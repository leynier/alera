use alera_core::runtime::{ChatOrchestrationTaskStatus as Status, ChatOrchestrationWakeStatus};
use serde_json::{json, Value};

use crate::terminal_host::server::agent_chat_runtime::commands::SendInput;

use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};
use super::wakes::deliver_next_wake;

async fn children(harness: &TestHarness, parent: &str, count: usize) -> Vec<(String, String)> {
    let caller = harness.agent(parent).await;
    let mut children = Vec::new();
    for index in 0..count {
        let mut payload = delegate_payload(
            &format!("cohort-{index}"),
            json!({"workspace": {"workspaceId": "ws-a"}}),
        );
        payload["notify"] = json!("always");
        let response = harness
            .service
            .handle("delegate", &payload, &caller)
            .await
            .unwrap();
        let child = response["childChatId"].as_str().unwrap().to_owned();
        let control = harness.control(&child).await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        children.push((response["taskId"].as_str().unwrap().to_owned(), child));
    }
    children
}

async fn wait_idle(harness: &TestHarness, chat: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            if harness.runtime.snapshot(chat).await.unwrap()["session"]["activeTurnId"].is_null() {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn simultaneous_results_merge_and_acknowledgement_withdraws_only_its_entry() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Stay active while children finish.")
        .await;
    let parent_control = harness.control(&parent).await;
    let tasks = children(&harness, &parent, 3).await;
    for (task, child) in &tasks {
        harness.control(child).await.complete(1, "Child result.");
        harness.task_status(task, Status::Completed).await;
    }
    assert!(parent_control.interrupts.lock().unwrap().is_empty());
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    let wakes = harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
        .await
        .unwrap();
    assert_eq!(wakes.len(), 1);
    assert_eq!(wakes[0].status, ChatOrchestrationWakeStatus::Pending);
    assert_eq!(wakes[0].entries.len(), 3);
    harness
        .service
        .handle(
            "task",
            &json!({"taskId": tasks[1].0}),
            &human("mobile:phone"),
        )
        .await
        .unwrap();
    assert_eq!(
        harness
            .store
            .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
            .await
            .unwrap()[0]
            .entries
            .len(),
        3
    );
    harness
        .service
        .handle(
            "task",
            &json!({"taskId": tasks[1].0, "acknowledge": true}),
            &human("mobile:phone"),
        )
        .await
        .unwrap();
    assert_eq!(
        harness
            .store
            .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
            .await
            .unwrap()[0]
            .entries
            .len(),
        2
    );
    assert!(!deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events
    )
    .await
    .unwrap());
    parent_control.complete(1, "Parent is ready.");
    wait_idle(&harness, &parent).await;
    assert!(deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events
    )
    .await
    .unwrap());
    tokio::time::timeout(TEST_DEADLINE, parent_control.wait_turns(2))
        .await
        .unwrap();
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    let wake = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["normalized"]["origin"]["kind"] == "orchestrationWake")
        .unwrap();
    let mut task_ids: Vec<&str> = wake["normalized"]["origin"]["taskIds"]
        .as_array()
        .unwrap()
        .iter()
        .map(|id| id.as_str().unwrap())
        .collect();
    task_ids.sort_unstable();
    let mut expected = vec![tasks[0].0.as_str(), tasks[2].0.as_str()];
    expected.sort_unstable();
    assert_eq!(task_ids, expected);
    assert_eq!(
        wake["clientMessageId"],
        format!("chat-orchestration-wake:{parent}:1")
    );
    assert!(parent_control.interrupts.lock().unwrap().is_empty());
    assert_eq!(snapshot["workspaceId"], "ws-a");
    assert!(harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&parent))
        .await
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn sealed_wake_replays_after_sql_reopen_without_a_second_parent_turn() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Prepare a durable wake.")
        .await;
    let parent_control = harness.control(&parent).await;
    let tasks = children(&harness, &parent, 1).await;
    harness
        .control(&tasks[0].1)
        .await
        .complete(1, "Durable child result.");
    harness.task_status(&tasks[0].0, Status::Completed).await;
    parent_control.complete(1, "Parent turn finished.");
    wait_idle(&harness, &parent).await;
    let sealed = harness
        .store
        .seal_chat_orchestration_wake(&parent)
        .await
        .unwrap()
        .unwrap();
    let task_ids: Vec<String> = sealed
        .entries
        .iter()
        .map(|entry| entry.task_id.clone())
        .collect();
    harness
        .runtime
        .send(
            &parent,
            SendInput {
                client_message_id: sealed.client_message_id.clone(),
            text: format!(
                "Orchestration updates are available for task IDs: {}. Read each task for its result.",
                task_ids.join(", ")
            ),
                attachments: Vec::new(),
            delivery: "queue".into(),
                model: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: Some(json!({"kind": "orchestrationWake", "taskIds": task_ids})),
            },
            human("desktop").ctx,
        )
        .await
        .unwrap();
    tokio::time::timeout(TEST_DEADLINE, parent_control.wait_turns(2))
        .await
        .unwrap();
    parent_control.complete(2, "Wake was already consumed.");
    wait_idle(&harness, &parent).await;
    let harness = harness.restart().await;
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert_eq!(recovery.wakes.len(), 1);
    assert_eq!(
        recovery.wakes[0].client_message_id,
        sealed.client_message_id
    );
    assert!(deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events
    )
    .await
    .unwrap());
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    let deliveries = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["clientMessageId"] == sealed.client_message_id)
        .count();
    assert_eq!(deliveries, 1);
    assert!(snapshot["session"]["activeTurnId"].is_null());
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(
        harness
            .store
            .chat_orchestration_wake(&parent, sealed.generation)
            .await
            .unwrap()
            .unwrap()
            .status,
        ChatOrchestrationWakeStatus::Delivered
    );
    assert_eq!(
        harness
            .service
            .handle("task", &json!({"taskId": tasks[0].0}), &human("desktop"))
            .await
            .unwrap()["task"]["result"]["text"],
        Value::String("Durable child result.".into())
    );
    harness.finish().await;
}
