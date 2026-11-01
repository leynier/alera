use std::time::Duration;

use alera_core::runtime::{ChatOrchestrationTaskKind, ChatOrchestrationTaskStatus as Status};
use alera_provider_protocol::EventKind;
use serde_json::{json, Value};

use super::continuation_fixture::{
    continue_on_its_own, delegated, followup_of, stays_running, task,
};
use super::delegation_tests::delegate_payload;
use super::test_support::{human, wait_idle, TestHarness, TEST_DEADLINE};

fn wake_task_ids(snapshot: &Value) -> Vec<Vec<String>> {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["normalized"]["origin"]["kind"] == "orchestrationWake")
        .map(|item| {
            item["normalized"]["origin"]["taskIds"]
                .as_array()
                .unwrap()
                .iter()
                .map(|id| id.as_str().unwrap().to_owned())
                .collect()
        })
        .collect()
}

async fn wait_for_wake_with(harness: &TestHarness, parent: &str, task_id: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(parent).await.unwrap();
            if wake_task_ids(&snapshot)
                .iter()
                .any(|ids| ids.iter().any(|id| id == task_id))
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("no wake for {task_id}"));
}

#[tokio::test]
async fn a_task_is_held_while_awaited_native_work_runs_then_settles_from_the_wake_turn() {
    let harness = TestHarness::new().await;
    let held = delegated(&harness).await;
    held.control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "helper", "awaited": true}),
    );
    held.control.complete(1, "Started a helper.");
    stays_running(&harness, &held.task).await;
    held.control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "helper", "status": "completed", "wakesParent": true,
            "description": "Helper", "summary": "Helper result."}),
    );
    held.control.wait_turns(2).await;
    held.control
        .complete(2, "Final answer with the helper's result.");
    harness.task_status(&held.task, Status::Completed).await;
    let settled = task(&harness, &held.task).await;
    assert_eq!(
        settled.result_text.as_deref(),
        Some("Final answer with the helper's result.")
    );
    assert_ne!(
        settled.child_turn_id,
        settled.launch_options.as_ref().unwrap()["chainStartTurnId"]
            .as_str()
            .map(ToOwned::to_owned)
    );
    harness.finish().await;
}

#[tokio::test]
async fn an_agent_started_continuation_moves_the_task_along() {
    let harness = TestHarness::new().await;
    let held = delegated(&harness).await;
    held.control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "helper", "awaited": true}),
    );
    held.control.complete(1, "Waiting on background work.");
    stays_running(&harness, &held.task).await;
    held.control.event(
        EventKind::TaskCompleted,
        1,
        json!({"taskId": "helper", "status": "completed"}),
    );
    continue_on_its_own(&held.control, 2, "Done after the background work.");
    harness.task_status(&held.task, Status::Completed).await;
    assert_eq!(
        task(&harness, &held.task).await.result_text.as_deref(),
        Some("Done after the background work.")
    );
    harness.finish().await;
}

#[tokio::test]
async fn the_childs_own_delegation_holds_the_task_until_its_wake_turn_ends() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let held = delegated(&harness).await;
    let child_agent = harness.agent(&held.child).await;
    let mut payload = delegate_payload("grandchild", json!({"workspace": {"workspaceId": "ws-a"}}));
    payload["notify"] = json!("always");
    let grandchild = harness
        .service
        .handle("delegate", &payload, &child_agent)
        .await
        .unwrap();
    let grandchild_control = harness
        .control(grandchild["childChatId"].as_str().unwrap())
        .await;
    grandchild_control.wait_turns(1).await;
    held.control.complete(1, "Delegated a grandchild.");
    stays_running(&harness, &held.task).await;
    grandchild_control.complete(1, "Grandchild result.");
    held.control.wait_turns(2).await;
    held.control.complete(2, "Merged the grandchild's result.");
    harness.task_status(&held.task, Status::Completed).await;
    assert_eq!(
        task(&harness, &held.task).await.result_text.as_deref(),
        Some("Merged the grandchild's result.")
    );
    harness.finish().await;
}

#[tokio::test]
async fn a_continuation_after_settle_opens_a_followup_that_wakes_the_parent_again() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let held = delegated(&harness).await;
    held.control.complete(1, "First result.");
    harness.task_status(&held.task, Status::Completed).await;
    wait_for_wake_with(&harness, &held.parent, &held.task).await;
    let parent_control = harness.control(&held.parent).await;
    parent_control.complete(1, "Read the first result.");
    wait_idle(&harness, &held.parent).await;

    continue_on_its_own(&held.control, 2, "Late result.");
    let followup = followup_of(&harness, &held.child, &held.task).await;
    assert_eq!(followup.kind, ChatOrchestrationTaskKind::Followup);
    assert_eq!(followup.parent_task_id.as_deref(), Some(held.task.as_str()));
    harness
        .task_status(&followup.task_id, Status::Completed)
        .await;
    assert_eq!(
        task(&harness, &followup.task_id)
            .await
            .result_text
            .as_deref(),
        Some("Late result.")
    );
    wait_for_wake_with(&harness, &held.parent, &followup.task_id).await;
    let value = harness
        .service
        .handle(
            "task",
            &json!({"taskId": followup.task_id}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(value["task"]["followupOf"], held.task);
    assert_eq!(value["task"]["kind"], "followup");
    harness.finish().await;
}

#[tokio::test]
async fn a_persons_message_to_the_child_opens_a_followup() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let held = delegated(&harness).await;
    held.control.complete(1, "First result.");
    harness.task_status(&held.task, Status::Completed).await;
    wait_for_wake_with(&harness, &held.parent, &held.task).await;
    harness
        .control(&held.parent)
        .await
        .complete(1, "Read the first result.");
    harness
        .send_human(&held.child, "person", "One more thing.")
        .await;
    let followup = followup_of(&harness, &held.child, &held.task).await;
    held.control.wait_turns(2).await;
    held.control.complete(2, "Answered the person.");
    harness
        .task_status(&followup.task_id, Status::Completed)
        .await;
    wait_for_wake_with(&harness, &held.parent, &followup.task_id).await;
    harness.finish().await;
}

#[tokio::test]
async fn cancelling_a_followup_interrupts_its_turn() {
    let harness = TestHarness::new().await;
    harness.start_wake_pump();
    let held = delegated(&harness).await;
    held.control.complete(1, "First result.");
    harness.task_status(&held.task, Status::Completed).await;
    harness
        .send_human(&held.child, "person", "Keep going.")
        .await;
    let followup = followup_of(&harness, &held.child, &held.task).await;
    held.control.wait_turns(2).await;
    harness
        .service
        .handle(
            "cancel",
            &json!({"requestId": "stop-followup", "taskId": followup.task_id}),
            &human("desktop"),
        )
        .await
        .unwrap();
    harness
        .task_status(&followup.task_id, Status::Cancelled)
        .await;
    let interrupts = held.control.interrupts.lock().unwrap().clone();
    assert_eq!(interrupts.len(), 1);
    assert_eq!(
        interrupts[0].turn_id.as_deref(),
        Some("native-turn-2"),
        "{interrupts:?}"
    );
    harness.finish().await;
}

#[tokio::test]
async fn a_held_task_settles_from_its_chain_after_restart() {
    let harness = TestHarness::new().await;
    let held = delegated(&harness).await;
    held.control.event(
        EventKind::TaskStarted,
        1,
        json!({"taskId": "helper", "awaited": true}),
    );
    held.control.complete(1, "Answer from the first turn.");
    stays_running(&harness, &held.task).await;
    let first_turn = task(&harness, &held.task).await.child_turn_id;
    held.control.event(
        EventKind::TurnStarted,
        2,
        json!({"agentStarted": {"origin": "backgroundContinuation"}}),
    );
    held.control.event(
        EventKind::TaskStarted,
        2,
        json!({"taskId": "second-helper", "awaited": true}),
    );
    held.control
        .event(EventKind::TurnCompleted, 2, json!({"state": "completed"}));
    tokio::time::timeout(TEST_DEADLINE, async {
        while task(&harness, &held.task).await.child_turn_id == first_turn {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    stays_running(&harness, &held.task).await;
    let harness = harness.restart().await;
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    let settled = recovery
        .settled
        .iter()
        .find(|settled| settled.task_id == held.task)
        .unwrap();
    assert_eq!(settled.status, Status::Completed);
    assert_eq!(
        settled.result_text.as_deref(),
        Some("Answer from the first turn.")
    );
    harness.finish().await;
}
