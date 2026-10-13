use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn sql_reopen_reconciles_local_tasks_and_preserves_remote_host_authority() {
    let harness = TestHarness::new().await;
    let mut tasks = Vec::new();
    for (id, workspace) in [
        ("completed", "ws-a"),
        ("running", "ws-a"),
        ("remote", "ws-b"),
        ("cancelled", "ws-a"),
    ] {
        let response = harness
            .service
            .handle(
                "delegate",
                &delegate_payload(id, json!({"workspace": {"workspaceId": workspace}})),
                &human("desktop"),
            )
            .await
            .unwrap();
        let child = response["childChatId"].as_str().unwrap();
        let control = harness.control(child).await;
        tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
            .await
            .unwrap();
        tasks.push(response);
    }
    let old_token_path =
        harness.factory.launches.lock().unwrap()[0].env["ALERA_CHAT_CREDENTIAL_FILE"].clone();
    let old_token = std::fs::read_to_string(old_token_path).unwrap();
    let harness = harness.restart().await;
    let completed_chat = tasks[0]["childChatId"].as_str().unwrap();
    let record = harness
        .store
        .agent_chat(completed_chat)
        .await
        .unwrap()
        .unwrap();
    let task = harness
        .store
        .chat_orchestration_task(tasks[0]["taskId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    let turn_id = task.child_turn_id.unwrap();
    let mut snapshot = record.snapshot;
    for turn in snapshot["turns"].as_array_mut().unwrap() {
        if turn["turnId"] == turn_id {
            turn["status"] = json!("completed");
        }
    }
    snapshot["cursor"] = json!(record.cursor + 1);
    snapshot["session"]["activeTurnId"] = serde_json::Value::Null;
    snapshot["session"]["status"] = json!("ready");
    let assistant = json!({"itemId": "committed-final", "type": "assistant_message",
        "turnId": turn_id, "status": "completed", "streaming": false,
        "createdAt": chrono::Utc::now().to_rfc3339(), "updatedAt": chrono::Utc::now().to_rfc3339(),
        "generation": 1, "text": "Result committed before the crash.", "normalized": {}});
    harness.store.commit_agent_chat(completed_chat, record.cursor, &snapshot,
        &json!({"turns": snapshot["turns"], "session": snapshot["session"], "items": [assistant]}), None)
        .await.unwrap();
    harness
        .store
        .request_chat_orchestration_cancel(tasks[3]["taskId"].as_str().unwrap())
        .await
        .unwrap();
    let recovery = harness.store.recover_chat_orchestration().await.unwrap();
    assert_eq!(recovery.settled.len(), 3);
    assert_eq!(recovery.remote.len(), 1);
    assert_eq!(
        recovery.remote[0].task_id,
        tasks[2]["taskId"].as_str().unwrap()
    );
    assert_eq!(recovery.remote[0].host_id.as_deref(), Some("ssh-b"));
    let completed = harness
        .store
        .chat_orchestration_task(tasks[0]["taskId"].as_str().unwrap())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(completed.status, Status::Completed);
    assert_eq!(
        completed.result_text.as_deref(),
        Some("Result committed before the crash.")
    );
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(tasks[1]["taskId"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Interrupted
    );
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(tasks[2]["taskId"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Running
    );
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(tasks[3]["taskId"].as_str().unwrap())
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Cancelled
    );
    assert!(harness
        .service
        .credential_hook()
        .verify(&old_token)
        .await
        .is_err());
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert!(harness
        .store
        .recover_chat_orchestration()
        .await
        .unwrap()
        .settled
        .is_empty());
    harness.finish().await;
}
