use std::sync::Arc;

use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;
use tokio::sync::Notify;

use super::delegation_tests::delegate_payload;
use super::test_support::{human, CreationGate, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn cancellation_during_workspace_preparation_keeps_workspace_and_never_launches_child() {
    let harness = TestHarness::new().await;
    let gate = Arc::new(CreationGate {
        entered: Notify::new(),
        resume: Notify::new(),
    });
    *harness.targets.pause_creation.lock().unwrap() = Some(gate.clone());
    let service = harness.service.clone();
    let delegation = tokio::spawn(async move {
        service
            .handle(
                "delegate",
                &delegate_payload(
                    "preparing",
                    json!({"newWorkspace": {
                        "projectId": "project-a", "hostId": "local", "mode": "worktree",
                    }}),
                ),
                &human("desktop"),
            )
            .await
    });
    tokio::time::timeout(TEST_DEADLINE, gate.entered.notified())
        .await
        .unwrap();
    let tasks = harness
        .service
        .handle(
            "tasks.list",
            &json!({"statuses": ["preparing"]}),
            &human("mobile:phone"),
        )
        .await
        .unwrap();
    let task_id = tasks["tasks"][0]["taskId"]
        .as_str()
        .expect("preparation must be persisted before creating the workspace")
        .to_owned();
    harness
        .service
        .handle(
            "cancel",
            &json!({"requestId": "cancel-preparing", "taskId": task_id}),
            &human("mobile:phone"),
        )
        .await
        .unwrap();
    gate.resume.notify_one();
    let result = tokio::time::timeout(TEST_DEADLINE, delegation)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(result["status"], "cancelled");
    harness.task_status(&task_id, Status::Cancelled).await;
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(harness.store.list_all_workspaces().await.unwrap().len(), 3);
    let task = harness
        .store
        .chat_orchestration_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.workspace_id.as_deref(), Some("created-1"));
    assert!(task.child_chat_id.is_none());
    harness.finish().await;
}

#[tokio::test]
async fn cancelling_a_queued_task_removes_only_owned_input_and_keeps_live_human_work() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    let active = harness
        .send_human(&child, "human-active", "Keep this human turn running.")
        .await;
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let task = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("owned-queued", json!({"chat": {"chatId": child}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    harness
        .send_human(&child, "human-queued", "Preserve this queued human work.")
        .await;
    let cancel_payload = json!({"requestId": "cancel-owned", "taskId": task["taskId"], "reason": "No longer needed."});
    let cancelled = harness
        .service
        .handle("cancel", &cancel_payload, &human("mobile:phone"))
        .await
        .unwrap();
    assert_eq!(
        harness
            .service
            .handle("cancel", &cancel_payload, &human("mobile:phone"))
            .await
            .unwrap(),
        cancelled
    );
    assert!(control.interrupts.lock().unwrap().is_empty());
    let snapshot = harness.runtime.snapshot(&child).await.unwrap();
    assert_eq!(snapshot["session"]["activeTurnId"], active["turnId"]);
    let queue = snapshot["queue"].as_array().unwrap();
    assert_eq!(queue.len(), 1);
    assert_eq!(queue[0]["clientMessageId"], "human-queued");
    harness
        .task_status(task["taskId"].as_str().unwrap(), Status::Cancelled)
        .await;
    control.complete(1, "Human work completed normally.");
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(2))
        .await
        .unwrap();
    assert_eq!(
        control.turns.lock().unwrap()[1].input,
        "Preserve this queued human work."
    );
    harness.finish().await;
}

#[tokio::test]
async fn recursive_cancellation_interrupts_owned_turns_and_leaves_unrelated_tasks_alive() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Own a descendant tree.")
        .await;
    let caller = harness.agent(&parent).await;
    let root = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("root-task", json!({"workspace": {"workspaceId": "ws-a"}})),
            &caller,
        )
        .await
        .unwrap();
    let root_child = root["childChatId"].as_str().unwrap();
    let child_caller = harness.agent(root_child).await;
    let grandchild = harness
        .service
        .handle(
            "delegate",
            &delegate_payload(
                "grandchild-task",
                json!({"workspace": {"workspaceId": "ws-a"}}),
            ),
            &child_caller,
        )
        .await
        .unwrap();
    let grandchild_chat = grandchild["childChatId"].as_str().unwrap();
    let grandchild_control = harness.control(grandchild_chat).await;
    tokio::time::timeout(TEST_DEADLINE, grandchild_control.wait_turns(1))
        .await
        .unwrap();
    let unrelated = harness
        .service
        .handle(
            "delegate",
            &delegate_payload(
                "unrelated-task",
                json!({"workspace": {"workspaceId": "ws-a"}}),
            ),
            &human("desktop"),
        )
        .await
        .unwrap();
    let unrelated_control = harness
        .control(unrelated["childChatId"].as_str().unwrap())
        .await;
    tokio::time::timeout(TEST_DEADLINE, unrelated_control.wait_turns(1))
        .await
        .unwrap();
    let response = harness
        .service
        .handle(
            "cancel",
            &json!({"requestId": "cancel-tree", "taskId": root["taskId"]}),
            &caller,
        )
        .await
        .unwrap();
    let mut cancelled = response["cancelledTaskIds"].as_array().unwrap().clone();
    cancelled.sort_by_key(|value| value.as_str().unwrap().to_owned());
    let mut expected = vec![root["taskId"].clone(), grandchild["taskId"].clone()];
    expected.sort_by_key(|value| value.as_str().unwrap().to_owned());
    assert_eq!(cancelled, expected);
    harness
        .task_status(root["taskId"].as_str().unwrap(), Status::Cancelled)
        .await;
    harness
        .task_status(grandchild["taskId"].as_str().unwrap(), Status::Cancelled)
        .await;
    assert_eq!(
        harness
            .control(root_child)
            .await
            .interrupts
            .lock()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(grandchild_control.interrupts.lock().unwrap().len(), 1);
    assert!(unrelated_control.interrupts.lock().unwrap().is_empty());
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(unrelated["taskId"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Running
    );
    assert!(harness
        .control(&parent)
        .await
        .interrupts
        .lock()
        .unwrap()
        .is_empty());
    harness.finish().await;
}
