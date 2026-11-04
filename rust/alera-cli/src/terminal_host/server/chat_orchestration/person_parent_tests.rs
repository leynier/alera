use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use crate::terminal_host::server::agent_chat_runtime::ChatOp;

use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn person_delegation_links_a_parent_without_impersonating_its_agent() {
    for scope in ["desktop", "cli", "mobile:phone"] {
        let mut harness = TestHarness::new().await;
        let parent = harness.create_chat("ws-a", "full-access").await;
        let mut payload = delegate_payload(scope, json!({"workspace":{"workspaceId":"ws-b"}}));
        payload["parentChatId"] = json!(parent);
        payload["actor"] = json!("agent:forged");
        let response = harness
            .service
            .handle("delegate", &payload, &human(scope))
            .await
            .unwrap();
        let task_id = response["taskId"].as_str().unwrap();
        let child = response["childChatId"].as_str().unwrap();
        assert_eq!(response["parentChatId"], parent);
        assert_eq!(response["actor"], scope);
        assert_eq!(response["runtimeMode"], "approval-required");
        assert_eq!(response["rootTaskId"], task_id);
        assert_eq!(response["depth"], 0);
        let snapshot = harness.service.runtime.snapshot(child).await.unwrap();
        assert_eq!(snapshot["items"][0]["actor"], scope);
        assert_eq!(
            snapshot["items"][0]["normalized"]["origin"]["taskIds"],
            json!([task_id])
        );
        assert!(snapshot["items"][0]["normalized"]["origin"]["senderChatId"].is_null());
        assert_eq!(
            harness
                .satellites
                .record("ws-b", child)
                .await
                .metadata
                .unwrap()["parentChatId"],
            parent
        );
        assert!(harness.runtime.snapshot(&parent).await.unwrap()["turns"]
            .as_array()
            .unwrap()
            .is_empty());
        assert!(!harness
            .factory
            .launches
            .lock()
            .unwrap()
            .iter()
            .any(|launch| launch.chat_id == parent));
        let tasks = harness
            .service
            .handle("tasks.list", &json!({"parentChatId":parent}), &human(scope))
            .await
            .unwrap();
        assert_eq!(tasks["tasks"].as_array().unwrap().len(), 1);
        assert_eq!(tasks["tasks"][0]["taskId"], task_id);
        let summary = harness.runtime.list(Some("ws-a"), false).await.unwrap();
        let parent_summary = summary
            .iter()
            .find(|chat| chat["chatId"] == parent)
            .unwrap();
        assert_eq!(parent_summary["openChildTaskCount"], 1);
        let (change, _) = harness.events.recv().await.unwrap();
        assert_eq!(change["parentChatId"], parent);
        assert_eq!(
            harness
                .service
                .handle("delegate", &payload, &human(scope))
                .await
                .unwrap(),
            response
        );
        let other = harness.create_chat("ws-a", "approval-required").await;
        payload["parentChatId"] = json!(other);
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("delegate", &payload, &human(scope))
                    .await
                    .unwrap_err()
            ),
            "request_conflict"
        );
        harness.finish().await;
    }
}

#[tokio::test]
async fn person_parent_must_exist_and_be_unarchived_before_task_admission() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(
            &parent,
            "archive-parent",
            "Persist a sent parent before archiving.",
        )
        .await;
    harness
        .service
        .runtime
        .command(&parent, ChatOp::Close, human("desktop").ctx, None)
        .await
        .unwrap();
    for (id, code) in [
        ("missing", "chat_not_found"),
        (parent.as_str(), "chat_archived"),
    ] {
        let mut payload = delegate_payload(id, json!({"workspace":{"workspaceId":"ws-b"}}));
        payload["parentChatId"] = json!(id);
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("delegate", &payload, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            code
        );
    }
    let tasks = harness
        .service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap();
    assert!(tasks["tasks"].as_array().unwrap().is_empty());
    assert!(harness
        .factory
        .launches
        .lock()
        .unwrap()
        .iter()
        .all(|launch| launch.chat_id == parent));
    harness.finish().await;
}

#[tokio::test]
async fn bound_agent_cannot_spoof_another_parent_even_for_a_message_without_reply() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Delegate only for this chat.")
        .await;
    let caller = harness.agent(&parent).await;
    let other = harness.create_chat("ws-a", "approval-required").await;
    let mut payload = delegate_payload(
        "spoof-delegate",
        json!({"workspace":{"workspaceId":"ws-b"}}),
    );
    payload["parentChatId"] = json!(other);
    assert_eq!(
        error_code(
            &harness
                .service
                .handle("delegate", &payload, &caller)
                .await
                .unwrap_err()
        ),
        "not_in_lineage"
    );
    for expect_reply in [false, true] {
        let payload = json!({"requestId":format!("spoof-send-{expect_reply}"), "parentChatId":other,
            "chatId":other, "message":"Do not send.", "expectReply":expect_reply});
        assert_eq!(
            error_code(
                &harness
                    .service
                    .handle("send", &payload, &caller)
                    .await
                    .unwrap_err()
            ),
            "not_in_lineage"
        );
    }
    payload["parentChatId"] = json!(parent);
    let child = harness
        .service
        .handle("delegate", &payload, &caller)
        .await
        .unwrap();
    assert_eq!(child["parentChatId"], parent);
    let snapshot = harness
        .service
        .runtime
        .snapshot(child["childChatId"].as_str().unwrap())
        .await
        .unwrap();
    assert_eq!(snapshot["items"][0]["actor"], format!("agent:{parent}"));
    assert_eq!(
        snapshot["items"][0]["normalized"]["origin"]["senderChatId"],
        parent
    );
    harness.finish().await;
}

#[tokio::test]
async fn person_message_parent_is_linked_only_when_a_reply_task_is_requested() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "approval-required").await;
    let child = harness.create_chat("ws-b", "approval-required").await;
    let without_reply = json!({"requestId":"no-reply", "parentChatId":"missing-parent",
        "chatId":child,"message":"An untracked message.","expectReply":false});
    let sent = harness
        .service
        .handle("send", &without_reply, &human("mobile:phone"))
        .await
        .unwrap();
    assert!(sent.get("taskId").is_none());
    let payload = json!({"requestId":"reply", "parentChatId":parent,
        "chatId":child,"message":"Track the reply.","expectReply":true});
    let tracked = harness
        .service
        .handle("send", &payload, &human("mobile:phone"))
        .await
        .unwrap();
    let tasks = harness
        .service
        .handle(
            "tasks.list",
            &json!({"parentChatId":parent}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(tasks["tasks"].as_array().unwrap().len(), 1);
    assert_eq!(tasks["tasks"][0]["taskId"], tracked["taskId"]);
    assert_eq!(tasks["tasks"][0]["actor"], "mobile:phone");
    let snapshot = harness.service.runtime.snapshot(&child).await.unwrap();
    assert_eq!(tracked["delivery"], "queued");
    let queued = snapshot["queue"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["text"] == "Track the reply.")
        .unwrap();
    assert_eq!(queued["origin"]["taskIds"], json!([tracked["taskId"]]));
    assert!(queued["origin"]["senderChatId"].is_null());
    assert_eq!(queued["actor"], "mobile:phone");
    let control = harness.control(&child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Untracked message settled.");
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(2))
        .await
        .unwrap();
    let snapshot = harness.service.runtime.snapshot(&child).await.unwrap();
    let delivered = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["text"] == "Track the reply.")
        .unwrap();
    assert_eq!(
        delivered["normalized"]["origin"]["taskIds"],
        json!([tracked["taskId"]])
    );
    assert!(delivered["normalized"]["origin"]["senderChatId"].is_null());
    assert_eq!(delivered["actor"], "mobile:phone");
    assert_eq!(control.turns.lock().unwrap()[1].input, "Track the reply.");
    harness.finish().await;
}

#[tokio::test]
async fn person_delegation_from_an_active_child_preserves_root_task_lineage() {
    let harness = TestHarness::new().await;
    let top = harness.create_chat("ws-a", "approval-required").await;
    let mut first = delegate_payload("top", json!({"workspace":{"workspaceId":"ws-a"}}));
    first["parentChatId"] = json!(top);
    let first = harness
        .service
        .handle("delegate", &first, &human("desktop"))
        .await
        .unwrap();
    let parent = first["childChatId"].as_str().unwrap();
    tokio::time::timeout(TEST_DEADLINE, harness.control(parent).await.wait_turns(1))
        .await
        .unwrap();
    let mut second = delegate_payload("nested", json!({"workspace":{"workspaceId":"ws-b"}}));
    second["parentChatId"] = json!(parent);
    let second = harness
        .service
        .handle("delegate", &second, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(second["parentTaskId"], first["taskId"]);
    assert_eq!(second["rootTaskId"], first["taskId"]);
    assert_eq!(second["depth"], 1);
    harness.finish().await;
}

#[tokio::test]
async fn settled_person_task_wakes_only_its_real_remote_parent() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-b", "auto").await;
    harness
        .send_human(&parent, "parent", "Keep working until the child settles.")
        .await;
    let parent_control = harness.control(&parent).await;
    let other = harness.create_chat("ws-a", "approval-required").await;
    let mut payload = delegate_payload("wake-parent", json!({"workspace":{"workspaceId":"ws-a"}}));
    payload.as_object_mut().unwrap().remove("notify");
    payload["parentChatId"] = json!(parent);
    let response = harness
        .service
        .handle("delegate", &payload, &human("mobile:phone"))
        .await
        .unwrap();
    let task_id = response["taskId"].as_str().unwrap();
    let child = response["childChatId"].as_str().unwrap();
    let child_control = harness.control(child).await;
    tokio::time::timeout(TEST_DEADLINE, child_control.wait_turns(1))
        .await
        .unwrap();
    child_control.complete(1, "Owned child result.");
    harness.task_status(task_id, Status::Completed).await;
    assert_eq!(parent_control.turns.lock().unwrap().len(), 1);
    assert!(harness
        .store
        .list_chat_orchestration_wakes_awaiting_delivery(Some(&other))
        .await
        .unwrap()
        .is_empty());
    parent_control.complete(1, "Ready for the child result.");
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let woke = parent_control.turns.lock().unwrap().len() >= 2;
            if woke
                || harness.service.runtime.snapshot(&parent).await.unwrap()["session"]
                    ["activeTurnId"]
                    .is_null()
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    super::wakes::deliver_next_wake(
        &harness.store,
        harness.service.runtime.as_ref(),
        &parent,
        &harness.service.events,
    )
    .await
    .unwrap();
    tokio::time::timeout(TEST_DEADLINE, parent_control.wait_turns(2))
        .await
        .unwrap();
    let snapshot = harness.service.runtime.snapshot(&parent).await.unwrap();
    let wake = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["normalized"]["origin"]["kind"] == "orchestrationWake")
        .unwrap();
    assert_eq!(wake["normalized"]["origin"]["taskIds"], json!([task_id]));
    assert!(parent_control.interrupts.lock().unwrap().is_empty());
    assert!(harness.runtime.snapshot(&other).await.unwrap()["items"]
        .as_array()
        .unwrap()
        .is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn standalone_person_tasks_keep_no_parent_or_sender_chat() {
    let harness = TestHarness::new().await;
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("standalone", json!({"workspace":{"workspaceId":"ws-a"}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert!(response["parentChatId"].is_null());
    assert!(response["parentTaskId"].is_null());
    let snapshot = harness
        .runtime
        .snapshot(response["childChatId"].as_str().unwrap())
        .await
        .unwrap();
    assert!(snapshot["items"][0]["normalized"]["origin"]["senderChatId"].is_null());
    assert_eq!(snapshot["items"][0]["actor"], "desktop");
    harness.finish().await;
}

#[tokio::test]
async fn person_child_input_updates_its_parent_attention_summary() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "approval-required").await;
    let mut payload = delegate_payload("input", json!({"workspace":{"workspaceId":"ws-b"}}));
    payload["parentChatId"] = json!(parent);
    let task = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    let child = task["childChatId"].as_str().unwrap();
    let control = harness.control(child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.request_input(1, "question");
    harness
        .task_status(task["taskId"].as_str().unwrap(), Status::NeedsInput)
        .await;
    let summaries = harness.runtime.list(Some("ws-a"), false).await.unwrap();
    let summary = summaries
        .iter()
        .find(|chat| chat["chatId"] == parent)
        .unwrap();
    assert_eq!(summary["openChildTaskCount"], 1);
    assert_eq!(summary["childNeedsInput"], true);
    harness.finish().await;
}

#[tokio::test]
async fn sibling_parent_chats_in_one_workspace_list_only_their_own_tasks_by_default() {
    let harness = TestHarness::new().await;
    let mut parents = Vec::new();
    for name in ["first", "second"] {
        let parent = harness.create_chat("ws-a", "auto").await;
        harness
            .send_human(&parent, name, "Delegate for this chat.")
            .await;
        let caller = harness.agent(&parent).await;
        let mut payload = delegate_payload(
            &format!("sibling-{name}"),
            json!({"workspace":{"workspaceId":"ws-b"}}),
        );
        payload["parentChatId"] = json!(parent);
        harness
            .service
            .handle("delegate", &payload, &caller)
            .await
            .unwrap();
        parents.push((parent, caller));
    }
    for (parent, caller) in &parents {
        let own = harness
            .service
            .handle("tasks.list", &json!({}), caller)
            .await
            .unwrap();
        let tasks = own["tasks"].as_array().unwrap();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0]["parentChatId"], json!(parent));
        assert_eq!(tasks[0]["readOnly"], false);
    }
    let (first, _) = &parents[0];
    let (_, second_caller) = &parents[1];
    let sibling = harness
        .service
        .handle("tasks.list", &json!({"parentChatId": first}), second_caller)
        .await
        .unwrap();
    assert_eq!(sibling["tasks"][0]["readOnly"], true);
    let everyone = harness
        .service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap();
    assert_eq!(everyone["tasks"].as_array().unwrap().len(), 2);
    harness.finish().await;
}
