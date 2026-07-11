use super::*;

#[tokio::test]
async fn message_limits_are_enforced_at_the_storage_boundary() {
    let (_dir, store) = store().await;
    let mut exact = message("a", "b", OrchestrationMessageType::Status);
    exact.body = "x".repeat(ORCHESTRATION_BODY_MAX_BYTES);
    store.insert_orchestration_message(exact).await.unwrap();

    let mut oversized_body = message("a", "b", OrchestrationMessageType::Status);
    oversized_body.body = "x".repeat(ORCHESTRATION_BODY_MAX_BYTES + 1);
    assert!(store
        .insert_orchestration_message(oversized_body)
        .await
        .unwrap_err()
        .to_string()
        .contains("body"));

    let mut oversized_lifecycle = message("a", "b", OrchestrationMessageType::WorkerDone);
    oversized_lifecycle.body = "x".repeat(ORCHESTRATION_LIFECYCLE_BODY_MAX_BYTES + 1);
    assert!(store
        .insert_orchestration_message(oversized_lifecycle)
        .await
        .unwrap_err()
        .to_string()
        .contains("body"));

    let mut oversized_payload = message("a", "b", OrchestrationMessageType::Status);
    oversized_payload.payload = Some("x".repeat(ORCHESTRATION_PAYLOAD_MAX_BYTES + 1));
    assert!(store
        .insert_orchestration_message(oversized_payload)
        .await
        .unwrap_err()
        .to_string()
        .contains("payload"));

    let mut oversized_subject = message("a", "b", OrchestrationMessageType::Status);
    oversized_subject.subject = "x".repeat(ORCHESTRATION_SUBJECT_MAX_BYTES + 1);
    assert!(store
        .insert_orchestration_message(oversized_subject)
        .await
        .unwrap_err()
        .to_string()
        .contains("subject"));

    let mut oversized_thread = message("a", "b", OrchestrationMessageType::Status);
    oversized_thread.thread_id = Some("x".repeat(ORCHESTRATION_THREAD_ID_MAX_BYTES + 1));
    assert!(store
        .insert_orchestration_message(oversized_thread)
        .await
        .unwrap_err()
        .to_string()
        .contains("thread id"));

    let mut oversized_handle = message("a", "b", OrchestrationMessageType::Status);
    oversized_handle.from_handle = "x".repeat(ORCHESTRATION_HANDLE_MAX_BYTES + 1);
    assert!(store
        .insert_orchestration_message(oversized_handle)
        .await
        .unwrap_err()
        .to_string()
        .contains("from handle"));

    assert_eq!(store.orchestration_inbox(10).await.unwrap().len(), 1);
}
