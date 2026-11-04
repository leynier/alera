use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::{json, Value};

use super::delegation_tests::delegate_payload;
use super::models::OrchestrationRequest;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

async fn delegated(harness: &TestHarness, request_id: &str) -> Value {
    harness
        .service
        .handle(
            "delegate",
            &delegate_payload(request_id, json!({"workspace":{"workspaceId":"ws-a"}})),
            &human("desktop"),
        )
        .await
        .unwrap()
}

async fn settle(harness: &TestHarness, task: &Value) {
    let control = harness.control(task["childChatId"].as_str().unwrap()).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    control.complete(1, "Settled task result.");
    harness
        .task_status(task["taskId"].as_str().unwrap(), Status::Completed)
        .await;
}

async fn receipt_count(harness: &TestHarness) -> i64 {
    sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM chatOrchestrationReceipts WHERE verb = 'task'",
    )
    .fetch_one(harness.store.pool())
    .await
    .unwrap()
}

#[tokio::test]
async fn concurrent_duplicate_acknowledgements_replay_one_caller_receipt_without_changing_status() {
    let harness = TestHarness::new().await;
    let task = delegated(&harness, "duplicate-ack").await;
    settle(&harness, &task).await;
    let settled = harness
        .store
        .chat_orchestration_task(task["taskId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    let caller = human("desktop");
    let payload = json!({"requestId":"ack", "taskId":task["taskId"], "acknowledge":true});
    let normalized = json!({"requestId":" ack ", "taskId":task["taskId"], "acknowledge":true});
    let (first, duplicate) = tokio::join!(
        harness.service.handle("task", &payload, &caller),
        harness.service.handle("task", &normalized, &caller),
    );
    let first = first.unwrap();
    assert_eq!(first, duplicate.unwrap());
    assert_eq!(first["task"]["status"], "completed");
    assert_eq!(first["task"]["resultDelivery"], "acknowledged");
    assert_eq!(first["task"]["result"]["text"], "Settled task result.");
    assert_eq!(receipt_count(&harness).await, 1);
    let before = harness
        .store
        .chat_orchestration_task(task["taskId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(before.revision, settled.revision);
    assert_eq!(before.status, settled.status);
    assert_eq!(
        harness
            .service
            .handle("task", &payload, &caller)
            .await
            .unwrap(),
        first
    );
    let after = harness
        .store
        .chat_orchestration_task(task["taskId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(before.updated_at, after.updated_at);
    assert_eq!(before.status, after.status);
    harness.finish().await;
}

#[tokio::test]
async fn acknowledgement_request_conflicts_on_changed_task_but_is_scoped_to_the_caller() {
    let harness = TestHarness::new().await;
    let first = delegated(&harness, "first").await;
    let second = delegated(&harness, "second").await;
    settle(&harness, &first).await;
    settle(&harness, &second).await;
    let first_ack = json!({"requestId":"same-id", "taskId":first["taskId"], "acknowledge":true});
    let second_ack = json!({"requestId":"same-id", "taskId":second["taskId"], "acknowledge":true});
    harness
        .service
        .handle("task", &first_ack, &human("desktop"))
        .await
        .unwrap();
    let error = harness
        .service
        .handle("task", &second_ack, &human("desktop"))
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "request_conflict");
    assert_eq!(error.wire_response(0)["errorCode"], "request_conflict");
    let unread = harness
        .service
        .handle(
            "task",
            &json!({"taskId":second["taskId"]}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(unread["task"]["resultDelivery"], "pending");
    let mobile = harness
        .service
        .handle("task", &second_ack, &human("mobile:phone"))
        .await
        .unwrap();
    assert_eq!(mobile["task"]["taskId"], second["taskId"]);
    assert_eq!(mobile["task"]["resultDelivery"], "acknowledged");
    assert_eq!(receipt_count(&harness).await, 2);
    harness.finish().await;
}

#[tokio::test]
async fn task_queries_are_read_only_and_legacy_acknowledgements_do_not_claim_receipts() {
    let harness = TestHarness::new().await;
    let first = delegated(&harness, "read").await;
    settle(&harness, &first).await;
    let id = first["taskId"].as_str().unwrap();
    let before = harness
        .store
        .chat_orchestration_task(id)
        .await
        .unwrap()
        .unwrap();
    let count = receipt_count(&harness).await;
    for payload in [
        json!({"taskId":id}),
        json!({"taskId":id,"acknowledge":false,"requestId":"read-id"}),
    ] {
        let read = harness
            .service
            .handle("task", &payload, &human("desktop"))
            .await
            .unwrap();
        assert_eq!(read["task"]["resultDelivery"], "pending");
    }
    let after = harness
        .store
        .chat_orchestration_task(id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        serde_json::to_value(before).unwrap(),
        serde_json::to_value(after).unwrap()
    );
    assert_eq!(receipt_count(&harness).await, count);
    let legacy = json!({"taskId":id,"acknowledge":true});
    let ack = harness
        .service
        .handle("task", &legacy, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(ack["task"]["resultDelivery"], "acknowledged");
    assert_eq!(
        harness
            .service
            .handle("task", &legacy, &human("desktop"))
            .await
            .unwrap(),
        ack
    );
    assert_eq!(receipt_count(&harness).await, count);
    harness
        .service
        .handle(
            "task",
            &json!({"taskId":id,"acknowledge":true,"requestId":"read-id"}),
            &human("desktop"),
        )
        .await
        .unwrap();
    assert_eq!(receipt_count(&harness).await, count + 1);
    harness.finish().await;
}

#[tokio::test]
async fn bound_acknowledgement_rechecks_lineage_before_receipt_replay_and_ignores_spoofed_identity()
{
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "parent", "Acknowledge only my own child results.")
        .await;
    let caller = harness.agent(&parent).await;
    let owned = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("owned", json!({"workspace":{"workspaceId":"ws-a"}})),
            &caller,
        )
        .await
        .unwrap();
    let unrelated = delegated(&harness, "unrelated").await;
    settle(&harness, &owned).await;
    settle(&harness, &unrelated).await;
    let ack = json!({"taskId":owned["taskId"], "acknowledge":true, "requestId":"bound-ack"});
    harness.service.handle("task", &ack, &caller).await.unwrap();
    let spoof = json!({"taskId":unrelated["taskId"], "acknowledge":true, "requestId":"bound-ack", "actor":"desktop", "scope":"desktop"});
    assert_eq!(
        error_code(
            &harness
                .service
                .handle("task", &spoof, &caller)
                .await
                .unwrap_err()
        ),
        "not_in_lineage"
    );
    let query = harness
        .service
        .handle("task", &json!({"taskId":unrelated["taskId"]}), &caller)
        .await
        .unwrap();
    assert_eq!(query["task"]["resultDelivery"], "pending");
    assert_eq!(receipt_count(&harness).await, 1);
    harness.finish().await;
}

#[tokio::test]
async fn unsettled_acknowledgements_do_not_change_status_or_consume_a_request_id() {
    let harness = TestHarness::new().await;
    let task = delegated(&harness, "running").await;
    let payload = json!({"taskId":task["taskId"], "acknowledge":true, "requestId":"settle-first"});
    let error = harness
        .service
        .handle("task", &payload, &human("desktop"))
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "task_not_settled");
    assert_eq!(receipt_count(&harness).await, 0);
    let query = harness
        .service
        .handle("task", &json!({"taskId":task["taskId"]}), &human("desktop"))
        .await
        .unwrap();
    assert_eq!(query["task"]["status"], "running");
    assert_eq!(query["task"]["resultDelivery"], "pending");
    settle(&harness, &task).await;
    let result = harness
        .service
        .handle("task", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(result["task"]["status"], "completed");
    assert_eq!(result["task"]["resultDelivery"], "acknowledged");
    assert_eq!(receipt_count(&harness).await, 1);
    harness.finish().await;
}

#[test]
fn malformed_provided_ack_request_ids_cannot_silently_fall_back_to_legacy() {
    for request_id in [json!(null), json!(""), json!(" "), json!(true), json!(3)] {
        assert!(OrchestrationRequest::parse(
            "task",
            &json!({"taskId":"task", "acknowledge":true,"requestId":request_id})
        )
        .is_err());
    }
    let OrchestrationRequest::Task { request_id, .. } =
        OrchestrationRequest::parse("task", &json!({"taskId":"task","acknowledge":true})).unwrap()
    else {
        panic!("expected task");
    };
    assert!(request_id.is_none());
}
