use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use crate::terminal_host::host_error::HostError;

use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

async fn published_failure(harness: &mut TestHarness, task_id: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let (change, durable_status) = harness.events.recv().await.unwrap();
            assert_eq!(change["taskId"], task_id);
            if durable_status == Status::Failed {
                break;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(
        harness
            .store
            .chat_orchestration_task(task_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        Status::Failed
    );
}

#[tokio::test]
async fn external_workspace_failure_commits_failed_task_and_receipt_before_publication() {
    let mut harness = TestHarness::new().await;
    *harness.targets.creation_error.lock().unwrap() = Some(HostError::conflict(
        "host_unavailable",
        "The authoritative host is offline.",
        json!({}),
    ));
    let payload = delegate_payload(
        "offline-host",
        json!({"newWorkspace": {
            "projectId": "project-a", "hostId": "ssh-offline", "mode": "worktree",
        }}),
    );
    let error = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "host_unavailable");
    let tasks = harness
        .service
        .handle("tasks.list", &json!({}), &human("mobile:phone"))
        .await
        .unwrap();
    let task_id = tasks["tasks"][0]["taskId"].as_str().unwrap();
    assert_eq!(tasks["tasks"][0]["status"], "failed");
    assert_eq!(
        tasks["tasks"][0]["error"]["code"],
        "workspace_preparation_failed"
    );
    published_failure(&mut harness, task_id).await;
    let replay = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(replay["taskId"], task_id);
    assert_eq!(replay["status"], "failed");
    assert_eq!(harness.targets.created.lock().unwrap().len(), 1);
    assert_eq!(harness.store.list_all_workspaces().await.unwrap().len(), 2);
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn child_creation_failure_keeps_the_prepared_workspace_and_replays_the_failed_task() {
    let mut harness = TestHarness::new().await;
    let mut payload = delegate_payload(
        "unavailable-provider",
        json!({"newWorkspace": {
            "projectId": "project-a", "hostId": "local", "mode": "shared",
        }}),
    );
    payload["agent"]["providerInstanceId"] = json!("missing-provider-instance");
    let error = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "providerUnavailable");
    let tasks = harness
        .service
        .handle("tasks.list", &json!({}), &human("desktop"))
        .await
        .unwrap();
    let task_id = tasks["tasks"][0]["taskId"].as_str().unwrap();
    assert_eq!(tasks["tasks"][0]["status"], "failed");
    assert_eq!(tasks["tasks"][0]["error"]["code"], "chat_creation_failed");
    assert_eq!(tasks["tasks"][0]["workspaceId"], "created-1");
    published_failure(&mut harness, task_id).await;
    let replay = harness
        .service
        .handle("delegate", &payload, &human("desktop"))
        .await
        .unwrap();
    assert_eq!(replay["taskId"], task_id);
    assert_eq!(replay["status"], "failed");
    assert_eq!(harness.targets.created.lock().unwrap().len(), 1);
    assert_eq!(harness.store.list_all_workspaces().await.unwrap().len(), 3);
    assert!(harness
        .store
        .list_agent_chats("created-1", false)
        .await
        .unwrap()
        .is_empty());
    harness.finish().await;
}
