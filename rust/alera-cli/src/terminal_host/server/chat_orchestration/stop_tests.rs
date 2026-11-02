use std::time::Duration;

use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use crate::terminal_host::server::agent_chat_runtime::commands::{CallerCtx, ChatOp};

use super::authorization::OrchestrationCaller;
use super::delegation_tests::delegate_payload;
use super::stop::DelegatedTasksStop;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

/// Delegates a child that wakes its parent, and waits for its first turn.
async fn delegate(
    harness: &TestHarness,
    caller: &OrchestrationCaller,
    request_id: &str,
    parent: Option<&str>,
) -> (String, String) {
    let mut payload = delegate_payload(request_id, json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!("always");
    if let Some(parent) = parent {
        payload["parentChatId"] = json!(parent);
    }
    let response = harness
        .service
        .handle("delegate", &payload, caller)
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    (response["taskId"].as_str().unwrap().to_owned(), child)
}

async fn wakes(harness: &TestHarness, parent: &str) -> usize {
    harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(parent))
        .await
        .unwrap()
        .len()
}

#[tokio::test]
async fn a_person_stopping_a_chat_cancels_its_delegated_tasks_and_drops_their_wakes() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate, then get stopped.")
        .await;
    let parent_control = harness.control(&parent).await;
    let caller = harness.agent(&parent).await;
    let (done, done_child) = delegate(&harness, &caller, "done", None).await;
    let (running, running_child) = delegate(&harness, &caller, "running", None).await;
    harness
        .control(&done_child)
        .await
        .complete(1, "Finished first.");
    harness.task_status(&done, Status::Completed).await;
    assert_eq!(wakes(&harness, &parent).await, 1);

    let stopped = harness
        .service
        .handle(
            "interrupt",
            &json!({"requestId": "stop-parent", "chatId": parent}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(stopped["interrupted"], true);
    assert_eq!(parent_control.interrupts.lock().unwrap().len(), 1);
    harness.task_status(&running, Status::Cancelled).await;
    assert_eq!(
        harness
            .control(&running_child)
            .await
            .interrupts
            .lock()
            .unwrap()
            .len(),
        1
    );
    // Neither the finished child nor the stopped one starts the parent again.
    assert_eq!(wakes(&harness, &parent).await, 0);
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(wakes(&harness, &parent).await, 0);
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn stop_reaches_the_delegated_tasks_of_a_chat_with_no_turn_running() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    let person = human("desktop");
    let (task, _) = delegate(&harness, &person, "idle-parent", Some(&parent)).await;
    let stopped = harness
        .service
        .handle(
            "interrupt",
            &json!({"requestId": "stop-idle", "chatId": parent}),
            &person,
        )
        .await
        .unwrap();
    assert_eq!(stopped["interrupted"], false);
    harness.task_status(&task, Status::Cancelled).await;
    harness.finish().await;
}

#[tokio::test]
async fn a_caller_that_stops_the_descendants_itself_opts_out() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    let person = human("desktop");
    let (task, _) = delegate(&harness, &person, "kept", Some(&parent)).await;
    harness
        .service
        .stop_chat(
            &parent,
            ChatOp::Interrupt { turn_id: None },
            person.ctx.clone(),
            None,
            false,
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(50)).await;
    let kept = harness
        .store
        .chat_orchestration_task(&task)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(kept.status, Status::Running);

    // The app's own `agentChat.interrupt` of a person reaches the tasks too.
    let payload = json!({"requestId": "ui-stop", "chatId": parent});
    let runtime = CallerCtx::runtime();
    assert!(DelegatedTasksStop::for_request(
        Some(&harness.service),
        "agentChat.interrupt",
        &payload,
        &runtime
    )
    .is_none());
    assert!(DelegatedTasksStop::for_request(
        Some(&harness.service),
        "agentChat.send",
        &payload,
        &person.ctx
    )
    .is_none());
    DelegatedTasksStop::for_request(
        Some(&harness.service),
        "agentChat.interrupt",
        &payload,
        &person.ctx,
    )
    .unwrap()
    .run()
    .await;
    harness.task_status(&task, Status::Cancelled).await;
    harness.finish().await;
}

#[tokio::test]
async fn a_child_that_does_not_stop_in_time_is_recorded_and_the_next_one_still_stops() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    let person = human("desktop");
    let (hung, hung_child) = delegate(&harness, &person, "hung", Some(&parent)).await;
    let (next, _) = delegate(&harness, &person, "next", Some(&parent)).await;
    harness
        .control(&hung_child)
        .await
        .hang_interrupt
        .store(true, std::sync::atomic::Ordering::SeqCst);
    let service = harness
        .service
        .clone()
        .with_child_stop_deadline(Duration::from_secs(1));
    let stopped = tokio::time::timeout(
        TEST_DEADLINE,
        service.stop_delegated_tasks(&parent, "desktop"),
    )
    .await
    .expect("the cascade waited on the hung child")
    .unwrap();
    let errors = stopped["errors"].as_array().unwrap();
    assert!(
        errors
            .iter()
            .any(|error| error["taskId"] == hung.as_str() && error["code"] == "stopTimedOut"),
        "{errors:?}"
    );
    assert!(stopped["cancelledTaskIds"]
        .as_array()
        .unwrap()
        .iter()
        .any(|task| task == next.as_str()));
    harness.task_status(&next, Status::Cancelled).await;
    harness.finish().await;
}
