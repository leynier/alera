use alera_core::runtime::{
    ChatOrchestrationTaskStatus as Status, ChatOrchestrationWake, ChatOrchestrationWakeStatus,
};
use serde_json::{json, Value};

use crate::terminal_host::server::agent_chat_runtime::commands::SendInput;

use super::test_support::{children, human, wait_idle, TestHarness, TEST_DEADLINE};
use super::wake_text::{wake_text, WakeTask};
use super::wakes::deliver_next_wake;

/// The text `deliver_next_wake` sends for `wake`.
pub(super) async fn sealed_wake_text(
    harness: &TestHarness,
    wake: &ChatOrchestrationWake,
) -> String {
    let mut tasks = Vec::new();
    for entry in &wake.entries {
        let task = harness
            .store
            .chat_orchestration_task(&entry.task_id)
            .await
            .unwrap();
        tasks.push(WakeTask::from_entry(entry, task.as_ref()));
    }
    wake_text(&tasks)
}

fn wakes(snapshot: &Value) -> Vec<Value> {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["normalized"]["origin"]["kind"] == "orchestrationWake")
        .cloned()
        .collect()
}

async fn deliver(harness: &TestHarness, parent: &str) -> bool {
    deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        parent,
        &harness.service.events,
    )
    .await
    .unwrap()
}

/// A parent that finished its own turn after its two children finished.
async fn idle_parent_with_results(harness: &TestHarness) -> (String, Vec<(String, String)>) {
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate two reviews.")
        .await;
    let tasks = children(harness, &parent, 2).await;
    harness
        .control(&tasks[0].1)
        .await
        .complete(1, "First review: no issues.");
    harness.task_status(&tasks[0].0, Status::Completed).await;
    harness
        .control(&tasks[1].1)
        .await
        .complete(1, "Second review: one bug.");
    harness.task_status(&tasks[1].0, Status::Completed).await;
    harness
        .control(&parent)
        .await
        .complete(1, "Waiting for reviews.");
    wait_idle(harness, &parent).await;
    (parent, tasks)
}

#[tokio::test]
async fn a_wake_inlines_each_settled_result() {
    let harness = TestHarness::new().await;
    let (parent, tasks) = idle_parent_with_results(&harness).await;
    assert!(deliver(&harness, &parent).await);
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    let wake = wakes(&snapshot).pop().unwrap();
    let text = wake["text"].as_str().unwrap();
    assert!(text.contains(&format!(
        "Delegated task {} (Child) [completed]:\nFirst review: no issues.",
        tasks[0].0
    )));
    assert!(text.contains(&format!(
        "Delegated task {} (Child) [completed]:\nSecond review: one bug.",
        tasks[1].0
    )));
    let first = text.find(&tasks[0].0).unwrap();
    let second = text.find(&tasks[1].0).unwrap();
    assert!(first < second, "entries keep their order");
    harness.finish().await;
}

#[tokio::test]
async fn a_wake_replays_with_the_same_text_after_restart() {
    let harness = TestHarness::new().await;
    let (parent, _) = idle_parent_with_results(&harness).await;
    let sealed = harness
        .store
        .seal_chat_orchestration_wake(&parent)
        .await
        .unwrap()
        .unwrap();
    let text = sealed_wake_text(&harness, &sealed).await;
    let harness = harness.restart().await;
    assert_eq!(sealed_wake_text(&harness, &sealed).await, text);
    assert!(deliver(&harness, &parent).await);
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    let delivered = wakes(&snapshot);
    assert_eq!(delivered.len(), 1);
    assert_eq!(delivered[0]["text"], json!(text));
    harness.finish().await;
}

#[tokio::test]
async fn a_cohort_sent_with_older_text_counts_as_delivered() {
    let harness = TestHarness::new().await;
    let (parent, tasks) = idle_parent_with_results(&harness).await;
    let sealed = harness
        .store
        .seal_chat_orchestration_wake(&parent)
        .await
        .unwrap()
        .unwrap();
    let task_ids: Vec<String> = tasks.iter().map(|(task, _)| task.clone()).collect();
    // What an older binary sent for the same cohort.
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
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: Some(json!({"kind": "orchestrationWake", "taskIds": task_ids})),
            },
            human("desktop").ctx,
        )
        .await
        .unwrap();
    let parent_control = harness.control(&parent).await;
    tokio::time::timeout(TEST_DEADLINE, parent_control.wait_turns(2))
        .await
        .unwrap();
    parent_control.complete(2, "Read the results.");
    wait_idle(&harness, &parent).await;
    assert!(deliver(&harness, &parent).await);
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
    let snapshot = harness.runtime.snapshot(&parent).await.unwrap();
    assert_eq!(wakes(&snapshot).len(), 1);
    assert_eq!(parent_control.turns.lock().unwrap().len(), 2);
    harness.finish().await;
}
