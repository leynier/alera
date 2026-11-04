use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::authorization::OrchestrationCaller;
use super::delegation_tests::delegate_payload;
use super::task_next::RUNNING_TASK_NEXT;
use super::test_support::{human, TestHarness};

async fn delegate(
    harness: &TestHarness,
    caller: &OrchestrationCaller,
    id: &str,
    notify: &str,
    parent: Option<&str>,
) -> Value {
    let mut payload = delegate_payload(id, json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!(notify);
    if let Some(parent) = parent {
        payload["parentChatId"] = json!(parent);
    }
    harness
        .service
        .handle("delegate", &payload, caller)
        .await
        .unwrap()
}

async fn read(harness: &TestHarness, caller: &OrchestrationCaller, task: &str) -> Value {
    harness
        .service
        .handle("task", &json!({"taskId": task}), caller)
        .await
        .unwrap()
}

async fn busy_agent(harness: &TestHarness) -> (String, OrchestrationCaller) {
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "go", "Delegate work.").await;
    let caller = harness.agent(&chat).await;
    (chat, caller)
}

#[tokio::test]
async fn only_the_parent_agent_a_running_task_wakes_is_told_to_end_its_turn() {
    let harness = TestHarness::new().await;
    let (parent, agent) = busy_agent(&harness).await;
    let woken = delegate(&harness, &agent, "woken", "always", None).await;
    assert_eq!(woken["next"], RUNNING_TASK_NEXT);
    let task = woken["taskId"].as_str().unwrap();
    assert_eq!(
        read(&harness, &agent, task).await["next"],
        RUNNING_TASK_NEXT
    );

    let silent = delegate(&harness, &agent, "silent", "never", None).await;
    assert!(silent.get("next").is_none());

    // A person and another agent read the same task without the hint.
    assert!(read(&harness, &human("desktop"), task)
        .await
        .get("next")
        .is_none());
    let (_, other) = busy_agent(&harness).await;
    assert!(read(&harness, &other, task).await.get("next").is_none());
    let person = delegate(
        &harness,
        &human("desktop"),
        "person",
        "always",
        Some(&parent),
    )
    .await;
    assert!(person.get("next").is_none());

    // A task that needs input or settled does not wake the parent as running.
    let child = woken["childChatId"].as_str().unwrap();
    let control = harness.control(child).await;
    control.request_input(1, "question");
    harness.task_status(task, Status::NeedsInput).await;
    assert!(read(&harness, &agent, task).await.get("next").is_none());
    harness
        .service
        .handle(
            "respond",
            &json!({"requestId": "answer", "chatId": child, "runtimeRequestId": "question",
                "response": {"type": "userInput", "answers": {"choice": "a"}}}),
            &agent,
        )
        .await
        .ok();
    control.complete(1, "Done.");
    harness.task_status(task, Status::Completed).await;
    assert!(read(&harness, &agent, task).await.get("next").is_none());
    harness.finish().await;
}

#[tokio::test]
async fn a_timed_out_wait_says_to_end_the_turn_only_when_every_open_task_wakes_the_caller() {
    let harness = TestHarness::new().await;
    let (_, agent) = busy_agent(&harness).await;
    let woken = delegate(&harness, &agent, "woken", "always", None).await;
    let silent = delegate(&harness, &agent, "silent", "never", None).await;
    let wait = |ids: Vec<&Value>| json!({"taskIds": ids, "waitSeconds": 0});
    let only_woken = harness
        .service
        .handle("wait", &wait(vec![&woken["taskId"]]), &agent)
        .await
        .unwrap();
    assert_eq!(only_woken["timedOut"], true);
    assert_eq!(only_woken["next"], RUNNING_TASK_NEXT);
    let mixed = harness
        .service
        .handle(
            "wait",
            &wait(vec![&woken["taskId"], &silent["taskId"]]),
            &agent,
        )
        .await
        .unwrap();
    assert_eq!(mixed["timedOut"], true);
    assert!(mixed.get("next").is_none());
    harness.finish().await;
}
