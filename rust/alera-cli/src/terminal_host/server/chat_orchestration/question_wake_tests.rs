use std::time::Duration;

use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;
use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

const PREFIX: &str = "chat-orchestration-question:";

struct Busy {
    parent: String,
    agent: OrchestrationCaller,
}

/// A parent agent whose own turn keeps running, so question messages wait
/// in its queue.
async fn busy_parent(harness: &TestHarness) -> Busy {
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate and keep working.")
        .await;
    let agent = harness.agent(&parent).await;
    Busy { parent, agent }
}

async fn delegate(harness: &TestHarness, caller: &OrchestrationCaller, notify: &str, parent: Option<&str>) -> (String, String) {
    let mut payload = delegate_payload(&format!("ask-{notify}"), json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!(notify);
    if let Some(parent) = parent {
        payload["parentChatId"] = json!(parent);
    }
    let response = harness
        .service
        .handle("delegate", &payload, caller)
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    harness.control(&child).await.wait_turns(1).await;
    (response["taskId"].as_str().unwrap().to_owned(), child)
}

async fn queued_questions(harness: &TestHarness, parent: &str) -> Vec<Value> {
    harness.runtime.snapshot(parent).await.unwrap()["queue"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|entry| entry["clientMessageId"].as_str().is_some_and(|id| id.starts_with(PREFIX)))
        .cloned()
        .collect()
}

async fn wait_for_questions(harness: &TestHarness, parent: &str, count: usize) -> Vec<Value> {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let queued = queued_questions(harness, parent).await;
            if queued.len() == count {
                return queued;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("parent did not hold {count} question messages"))
}

async fn child_request(harness: &TestHarness, child: &str) -> String {
    harness.runtime.snapshot(child).await.unwrap()["pendingRequests"][0]["requestId"]
        .as_str()
        .unwrap()
        .to_owned()
}

async fn input_owner(harness: &TestHarness, task: &str) -> Value {
    harness
        .service
        .handle("task", &json!({"taskId": task}), &human("desktop"))
        .await
        .unwrap()["task"]["inputOwner"]
        .clone()
}

#[tokio::test]
async fn a_question_reaches_the_agent_parent_once_without_flagging_the_person() {
    let harness = TestHarness::new().await;
    let busy = busy_parent(&harness).await;
    let (task, child) = delegate(&harness, &busy.agent, "always", None).await;
    harness.control(&child).await.request_input(1, "native-question");
    harness.task_status(&task, Status::NeedsInput).await;
    let queued = wait_for_questions(&harness, &busy.parent, 1).await;
    let request = child_request(&harness, &child).await;
    assert_eq!(
        queued[0]["clientMessageId"],
        format!("{PREFIX}{}:{child}:{request}", busy.parent)
    );
    assert_eq!(
        queued[0]["origin"],
        json!({"kind": "orchestrationWake", "taskIds": [task], "requestIds": [request]})
    );
    let text = queued[0]["text"].as_str().unwrap();
    assert!(text.contains("Question choice: Which target?"), "{text}");
    assert!(text.contains("chat_respond"));
    assert_eq!(input_owner(&harness, &task).await, "parent");
    assert!(!harness
        .store
        .agent_chat_attention(&busy.parent)
        .await
        .unwrap()
        .child_needs_input);
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(queued_questions(&harness, &busy.parent).await.len(), 1);
    assert!(harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&busy.parent))
        .await
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn an_approval_still_flags_the_person_and_sends_nothing() {
    let harness = TestHarness::new().await;
    let busy = busy_parent(&harness).await;
    let (task, child) = delegate(&harness, &busy.agent, "always", None).await;
    harness.control(&child).await.request_approval(1, "native-approval");
    harness.task_status(&task, Status::NeedsInput).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(queued_questions(&harness, &busy.parent).await.is_empty());
    assert_eq!(input_owner(&harness, &task).await, "person");
    assert!(harness
        .store
        .agent_chat_attention(&busy.parent)
        .await
        .unwrap()
        .child_needs_input);
    harness.finish().await;
}

#[tokio::test]
async fn an_answered_question_is_withdrawn_without_interrupting_the_parent() {
    let harness = TestHarness::new().await;
    let busy = busy_parent(&harness).await;
    let (task, child) = delegate(&harness, &busy.agent, "always", None).await;
    let control = harness.control(&child).await;
    control.request_input(1, "first");
    control.request_input(1, "second");
    harness.task_status(&task, Status::NeedsInput).await;
    wait_for_questions(&harness, &busy.parent, 2).await;
    let request = child_request(&harness, &child).await;
    harness
        .service
        .handle(
            "respond",
            &json!({"requestId": "answer", "chatId": child, "runtimeRequestId": request,
                "response": {"type": "userInput", "answers": {"choice": "main"}}}),
            &busy.agent,
        )
        .await
        .unwrap();
    wait_for_questions(&harness, &busy.parent, 1).await;
    let parent_control = harness.control(&busy.parent).await;
    assert!(parent_control.interrupts.lock().unwrap().is_empty());
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn a_cancelled_task_withdraws_its_pending_question() {
    let harness = TestHarness::new().await;
    let busy = busy_parent(&harness).await;
    let (task, child) = delegate(&harness, &busy.agent, "always", None).await;
    harness.control(&child).await.request_input(1, "native-question");
    wait_for_questions(&harness, &busy.parent, 1).await;
    harness
        .service
        .handle(
            "cancel",
            &json!({"requestId": "cancel-asking", "taskId": task}),
            &busy.agent,
        )
        .await
        .unwrap();
    harness.task_status(&task, Status::Cancelled).await;
    wait_for_questions(&harness, &busy.parent, 0).await;
    harness.finish().await;
}

#[tokio::test]
async fn notify_never_and_person_owned_tasks_keep_flagging_and_send_nothing() {
    let harness = TestHarness::new().await;
    let busy = busy_parent(&harness).await;
    let (silent, silent_child) = delegate(&harness, &busy.agent, "never", None).await;
    harness
        .control(&silent_child)
        .await
        .request_input(1, "silent-question");
    harness.task_status(&silent, Status::NeedsInput).await;
    let (person, person_child) =
        delegate(&harness, &human("desktop"), "always", Some(&busy.parent)).await;
    harness
        .control(&person_child)
        .await
        .request_input(1, "person-question");
    harness.task_status(&person, Status::NeedsInput).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(queued_questions(&harness, &busy.parent).await.is_empty());
    assert_eq!(input_owner(&harness, &silent).await, "person");
    assert_eq!(input_owner(&harness, &person).await, "person");
    assert!(harness
        .store
        .agent_chat_attention(&busy.parent)
        .await
        .unwrap()
        .child_needs_input);
    harness.finish().await;
}
