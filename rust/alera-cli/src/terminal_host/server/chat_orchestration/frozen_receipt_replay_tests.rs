use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::paused_runtime_fixture::PausedChatRuntime;
use super::service::ChatOrchestrationService;
use super::test_support::{error_code, human, TestHarness};

async fn live_parent(harness: &TestHarness) -> String {
    let parent = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&parent, "parent", "Remain live while the child settles.")
        .await;
    harness.control(&parent).await.wait_turns(1).await;
    parent
}

async fn settle(harness: &TestHarness, task_id: &str, child: &str) {
    let control = harness.control(child).await;
    control.wait_turns(1).await;
    control.complete(1, "Settled receipt result.");
    harness.task_status(task_id, Status::Completed).await;
}

fn frozen(harness: &TestHarness, chat: &str) -> ChatOrchestrationService {
    harness
        .service
        .clone()
        .with_runtime(PausedChatRuntime::with_pending_operation(
            harness.service.runtime.clone(),
            chat,
            "uncertain",
        ))
}

async fn task_count(service: &ChatOrchestrationService) -> usize {
    service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap()["tasks"]
        .as_array()
        .unwrap()
        .len()
}

#[tokio::test]
async fn frozen_delegate_replays_matching_receipt_conflicts_changed_digest_and_rejects_new_key() {
    for freeze_parent in [true, false] {
        let harness = TestHarness::new().await;
        let parent = live_parent(&harness).await;
        let mut payload = delegate_payload(
            "delegate-once",
            if freeze_parent {
                json!({"newWorkspace":{"projectId":"project-b", "hostId":"local", "mode":"shared"}})
            } else {
                let destination = harness.create_chat("ws-a", "approval-required").await;
                json!({"chat":{"chatId":destination}})
            },
        );
        payload["parentChatId"] = json!(parent);
        let response = harness
            .service
            .handle("delegate", &payload, &human("desktop"))
            .await
            .unwrap();
        let child = response["childChatId"].as_str().unwrap();
        settle(&harness, response["taskId"].as_str().unwrap(), child).await;
        let service = frozen(&harness, if freeze_parent { &parent } else { child });
        let tasks = task_count(&service).await;
        let workspaces = harness.targets.created.lock().unwrap().len();
        let launches = harness.factory.launches.lock().unwrap().len();
        assert_eq!(
            service
                .handle("delegate", &payload, &human("desktop"))
                .await
                .unwrap(),
            response
        );
        let mut changed = payload.clone();
        changed["task"] = json!("Changed work must conflict before freeze admission.");
        assert_eq!(
            error_code(
                &service
                    .handle("delegate", &changed, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "request_conflict"
        );
        let mut new = payload;
        new["requestId"] = json!("delegate-new");
        assert_eq!(
            error_code(
                &service
                    .handle("delegate", &new, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "nativeOperationUncertain"
        );
        assert_eq!(task_count(&service).await, tasks);
        assert_eq!(harness.targets.created.lock().unwrap().len(), workspaces);
        assert_eq!(harness.factory.launches.lock().unwrap().len(), launches);
        assert_eq!(harness.control(child).await.turns.lock().unwrap().len(), 1);
        harness.finish().await;
    }
}

#[tokio::test]
async fn frozen_tracked_send_replays_receipt_before_parent_or_destination_admission() {
    for freeze_parent in [true, false] {
        let harness = TestHarness::new().await;
        let parent = live_parent(&harness).await;
        let child = harness.create_chat("ws-b", "approval-required").await;
        let payload = json!({"requestId":"send-once", "chatId":child, "parentChatId":parent,
            "message":"Tracked work.", "expectReply":true});
        let response = harness
            .service
            .handle("send", &payload, &human("desktop"))
            .await
            .unwrap();
        settle(&harness, response["taskId"].as_str().unwrap(), &child).await;
        let service = frozen(&harness, if freeze_parent { &parent } else { &child });
        let tasks = task_count(&service).await;
        let launches = harness.factory.launches.lock().unwrap().len();
        assert_eq!(
            service
                .handle("send", &payload, &human("desktop"))
                .await
                .unwrap(),
            response
        );
        let mut changed = payload.clone();
        changed["message"] = json!("Changed message.");
        assert_eq!(
            error_code(
                &service
                    .handle("send", &changed, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "request_conflict"
        );
        let mut new = payload;
        new["requestId"] = json!("send-new");
        assert_eq!(
            error_code(
                &service
                    .handle("send", &new, &human("desktop"))
                    .await
                    .unwrap_err()
            ),
            "nativeOperationUncertain"
        );
        assert_eq!(task_count(&service).await, tasks);
        assert!(harness.targets.created.lock().unwrap().is_empty());
        assert_eq!(harness.factory.launches.lock().unwrap().len(), launches);
        assert_eq!(harness.control(&child).await.turns.lock().unwrap().len(), 1);
        harness.finish().await;
    }
}

#[tokio::test]
async fn frozen_untracked_send_replays_its_receipt_without_new_native_input() {
    let harness = TestHarness::new().await;
    let child = harness.create_chat("ws-a", "approval-required").await;
    let payload =
        json!({"requestId":"untracked-once", "chatId":child, "message":"Untracked work."});
    let response = harness
        .service
        .handle("send", &payload, &human("desktop"))
        .await
        .unwrap();
    let control = harness.control(&child).await;
    control.wait_turns(1).await;
    control.complete(1, "Untracked work settled.");
    let service = frozen(&harness, &child);
    let launches = harness.factory.launches.lock().unwrap().len();
    assert_eq!(
        service
            .handle("send", &payload, &human("desktop"))
            .await
            .unwrap(),
        response
    );
    let mut changed = payload.clone();
    changed["message"] = json!("Changed untracked work.");
    assert_eq!(
        error_code(
            &service
                .handle("send", &changed, &human("desktop"))
                .await
                .unwrap_err()
        ),
        "request_conflict"
    );
    let mut new = payload;
    new["requestId"] = json!("untracked-new");
    assert_eq!(
        error_code(
            &service
                .handle("send", &new, &human("desktop"))
                .await
                .unwrap_err()
        ),
        "nativeOperationUncertain"
    );
    assert_eq!(control.turns.lock().unwrap().len(), 1);
    assert_eq!(harness.factory.launches.lock().unwrap().len(), launches);
    assert_eq!(task_count(&service).await, 0);
    harness.finish().await;
}

#[tokio::test]
async fn frozen_receipt_replay_still_requires_the_original_bound_caller_authority() {
    let harness = TestHarness::new().await;
    let parent = live_parent(&harness).await;
    let caller = harness.agent(&parent).await;
    let payload = delegate_payload("bound-once", json!({"workspace":{"workspaceId":"ws-b"}}));
    let response = harness
        .service
        .handle("delegate", &payload, &caller)
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap();
    settle(&harness, response["taskId"].as_str().unwrap(), child).await;
    let service = frozen(&harness, &parent);
    assert_eq!(
        service.handle("delegate", &payload, &caller).await.unwrap(),
        response
    );
    let mut spoof = payload.clone();
    spoof["parentChatId"] = json!("other-parent");
    spoof["scope"] = json!("desktop");
    assert_eq!(
        error_code(
            &service
                .handle("delegate", &spoof, &caller)
                .await
                .unwrap_err()
        ),
        "not_in_lineage"
    );
    service
        .credential_hook()
        .revoke_chat(&parent, "closed")
        .await
        .unwrap();
    assert_eq!(
        error_code(
            &service
                .handle("delegate", &payload, &caller)
                .await
                .unwrap_err()
        ),
        "chat_credential_invalid"
    );
    assert_eq!(task_count(&service).await, 1);
    assert_eq!(harness.control(child).await.turns.lock().unwrap().len(), 1);
    assert!(harness.targets.created.lock().unwrap().is_empty());
    harness.finish().await;
}
