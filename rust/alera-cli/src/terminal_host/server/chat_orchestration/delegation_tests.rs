use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

pub(super) fn delegate_payload(request_id: &str, target: Value) -> Value {
    json!({"requestId": request_id, "task": "Inspect only the child brief.",
        "title": "Child", "role": "reviewer", "notify": "never",
        "agent": {"providerInstanceId": "codex", "model": "test-model"},
        "target": target})
}

#[tokio::test]
async fn existing_chat_target_preserves_identity_project_and_authoritative_host() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-b", "approval-required").await;
    let before = harness
        .service
        .runtime
        .list(Some("ws-b"), false)
        .await
        .unwrap();
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("existing", json!({"chat": {"chatId": child}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(response["childChatId"], child);
    assert_eq!(response["workspaceId"], "ws-b");
    assert_eq!(response["projectId"], "project-b");
    assert_eq!(response["hostId"], "ssh-b");
    assert_eq!(
        harness
            .service
            .runtime
            .list(Some("ws-b"), false)
            .await
            .unwrap()
            .len(),
        before.len()
    );
    assert!(harness.targets.created.lock().unwrap().is_empty());
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    assert_eq!(
        control.turns.lock().unwrap()[0].input,
        "Inspect only the child brief."
    );
    harness.finish().await;
}

#[tokio::test]
async fn new_child_in_an_existing_workspace_receives_brief_without_parent_history() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(
            &parent,
            "parent-secret",
            "Parent history must remain private.",
        )
        .await;
    let caller = harness.agent(&parent).await;
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("new-chat", json!({"workspace": {"workspaceId": "ws-b"}})),
            &caller,
        )
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap();
    assert_ne!(child, parent);
    assert_eq!(response["runtimeMode"], "auto");
    let control = harness.control(child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    assert_eq!(
        control.turns.lock().unwrap()[0].input,
        "Inspect only the child brief."
    );
    let snapshot = harness.service.runtime.snapshot(child).await.unwrap();
    let items = snapshot["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["text"], "Inspect only the child brief.");
    assert_eq!(items[0]["normalized"]["origin"]["senderChatId"], parent);
    let child_record = harness.satellites.record("ws-b", child).await;
    assert!(harness.store.agent_chat(child).await.unwrap().is_none());
    assert_eq!(child_record.metadata.unwrap()["parentChatId"], parent);
    assert_eq!(snapshot["workspaceId"], "ws-b");
    assert!(harness.targets.created.lock().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn explicit_workspace_strategies_preserve_every_creation_field() {
    let harness = TestHarness::new().await;
    for mode in ["worktree", "shared"] {
        let target = json!({"newWorkspace": {
            "projectId": "cross-project", "hostId": "ssh-target", "mode": mode,
            "branch": "feature/chat", "sourceBranch": "develop", "reuseExistingBranch": true,
            "name": "Review", "parentWorkspaceId": "ws-a", "setup": "deferred",
        }});
        let response = harness
            .service
            .handle(
                "delegate",
                &delegate_payload(mode, target.clone()),
                &human("mobile:phone"),
            )
            .await
            .unwrap();
        let recorded = harness
            .targets
            .created
            .lock()
            .unwrap()
            .last()
            .unwrap()
            .clone();
        assert_eq!(
            serde_json::to_value(recorded).unwrap(),
            target["newWorkspace"]
        );
        assert_eq!(response["projectId"], "cross-project");
        assert_eq!(response["hostId"], "ssh-target");
        let child = response["childChatId"].as_str().unwrap();
        assert_eq!(
            harness.service.runtime.snapshot(child).await.unwrap()["workspaceId"],
            response["workspaceId"]
        );
    }
    assert_eq!(harness.targets.created.lock().unwrap().len(), 2);
    harness.finish().await;
}

#[tokio::test]
async fn delegate_receipt_replay_and_conflict_never_create_another_workspace_or_chat() {
    let harness = TestHarness::new().await;
    let payload = delegate_payload(
        "one-creation",
        json!({"newWorkspace": {
            "projectId": "project-a", "hostId": "local", "mode": "worktree",
        }}),
    );
    let first = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    let replay = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(replay["taskId"], first["taskId"]);
    let mut changed = payload.clone();
    changed["task"] = json!("A conflicting task.");
    let conflict = harness
        .service
        .handle("delegate", &changed, &human("desktop"))
        .await
        .unwrap_err();
    assert_eq!(error_code(&conflict), "request_conflict");
    assert_eq!(harness.targets.created.lock().unwrap().len(), 1);
    assert_eq!(harness.store.list_all_workspaces().await.unwrap().len(), 3);
    assert_eq!(
        harness
            .store
            .list_agent_chats(first["workspaceId"].as_str().unwrap(), false)
            .await
            .unwrap()
            .len(),
        1
    );
    let tasks = harness
        .service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap();
    assert_eq!(tasks["tasks"].as_array().unwrap().len(), 1);
    harness.finish().await;
}

#[tokio::test]
async fn concurrent_delegate_replays_admit_one_workspace_and_one_child() {
    let harness = TestHarness::new().await;
    let payload = delegate_payload(
        "concurrent-creation",
        json!({"newWorkspace": {
            "projectId": "project-a", "hostId": "local", "mode": "shared",
        }}),
    );
    let caller = human("desktop");
    let (first, second) = tokio::join!(
        harness.service.handle("delegate", &payload, &caller),
        harness.service.handle("delegate", &payload, &caller),
    );
    assert_eq!(first.unwrap()["taskId"], second.unwrap()["taskId"]);
    assert_eq!(harness.targets.created.lock().unwrap().len(), 1);
    assert_eq!(harness.store.list_all_workspaces().await.unwrap().len(), 3);
    assert_eq!(
        harness
            .store
            .list_agent_chats("created-1", false)
            .await
            .unwrap()
            .len(),
        1
    );
    harness.finish().await;
}

#[tokio::test]
async fn send_receipts_are_scoped_to_the_authenticated_caller_and_settle_on_actual_turn() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    let payload = json!({"requestId": "send-once", "chatId": child,
        "message": "Send exactly once.", "expectReply": true,
        "actor": "agent:forged", "scope": "chat:forged"});
    let first = harness
        .service
        .handle("send", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(
        harness
            .service
            .handle("send", &payload, &human("desktop"))
            .await
            .unwrap(),
        first
    );
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    assert_eq!(control.turns.lock().unwrap().len(), 1);
    let snapshot = harness.runtime.snapshot(&child).await.unwrap();
    assert_eq!(snapshot["items"][0]["actor"], "desktop");
    let task_id = first["taskId"].as_str().unwrap();
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Running
    );
    control.complete(1, "The task actually settled.");
    harness.task_status(task_id, Status::Completed).await;
    let task = harness
        .service
        .handle("task", &json!({"taskId": task_id}), &human("mobile:phone"))
        .await
        .unwrap();
    assert_eq!(task["task"]["result"]["text"], "The task actually settled.");
    harness.finish().await;
}

#[tokio::test]
async fn desktop_and_mobile_request_ids_do_not_collide_in_child_message_receipts() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    let desktop = json!({"requestId": "same-id", "chatId": child, "message": "Desktop message."});
    let mobile = json!({"requestId": "same-id", "chatId": child, "message": "Mobile message."});
    let first = harness
        .service
        .handle("send", &desktop, &human("desktop"))
        .await
        .unwrap();
    let second = harness
        .service
        .handle("send", &mobile, &human("mobile:phone"))
        .await
        .unwrap();
    harness
        .service
        .handle(
            "send",
            &json!({"requestId": "another-id", "chatId": child,
        "message": "Another desktop message."}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(
        harness
            .service
            .handle("send", &desktop, &human("desktop"))
            .await
            .unwrap(),
        first
    );
    assert_eq!(
        harness
            .service
            .handle("send", &mobile, &human("mobile:phone"))
            .await
            .unwrap(),
        second
    );
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Desktop completed.");
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(2))
        .await
        .unwrap();
    control.complete(2, "Mobile completed.");
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(3))
        .await
        .unwrap();
    let turns = control.turns.lock().unwrap().clone();
    assert_eq!(turns[0].input, "Desktop message.");
    assert_eq!(turns[1].input, "Mobile message.");
    assert_eq!(turns[2].input, "Another desktop message.");
    harness.finish().await;
}
