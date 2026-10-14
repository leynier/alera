use std::time::Duration;

use alera_core::runtime::{ChatOrchestrationTask, ChatOrchestrationTaskStatus as Status};
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::test_support::{human, TestHarness, TEST_DEADLINE};

const COMMITTED_RESULT: &str = "Result committed before the crash.";

fn host_process_runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

#[test]
fn sql_reopen_reconciles_local_tasks_and_preserves_remote_host_authority() {
    let before_crash = host_process_runtime();
    let (directory, tasks, old_token) = before_crash.block_on(prepare_crash());
    // A process crash removes actors and monitors without graceful shutdown
    // revoking credentials or settling tasks before startup recovery runs.
    before_crash.shutdown_timeout(TEST_DEADLINE);

    host_process_runtime().block_on(async {
        let harness = TestHarness::open(directory).await;
        assert!(harness
            .service
            .credential_hook()
            .verify(&old_token)
            .await
            .is_ok());
        harness.runtime.recover_after_restart().await.unwrap();
        let recovery = harness.store.recover_chat_orchestration().await.unwrap();
        assert_eq!(recovery.settled.len(), 3);
        assert_eq!(recovery.remote.len(), 1);
        assert_eq!(recovery.remote[0].task_id, tasks[2].task_id);
        assert_eq!(recovery.remote[0].host_id.as_deref(), Some("ssh-b"));
        assert!(recovery.revoked_credentials > 0);

        for (task, expected) in tasks.iter().zip([
            Status::Completed,
            Status::Interrupted,
            Status::Running,
            Status::Cancelled,
        ]) {
            let recovered = harness
                .store
                .chat_orchestration_task(&task.task_id)
                .await
                .unwrap()
                .unwrap();
            assert_eq!(recovered.status, expected);
            if expected == Status::Completed {
                assert_eq!(recovered.result_text.as_deref(), Some(COMMITTED_RESULT));
            }
        }
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
    });
}

async fn prepare_crash() -> (tempfile::TempDir, Vec<ChatOrchestrationTask>, String) {
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
        harness.control(child).await.wait_turns(1).await;
        let task = tokio::time::timeout(TEST_DEADLINE, async {
            loop {
                let task = harness
                    .store
                    .chat_orchestration_task(response["taskId"].as_str().unwrap())
                    .await
                    .unwrap()
                    .unwrap();
                if task.child_turn_id.is_some() {
                    break task;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("task monitor did not link the actual child turn before the fixture deadline");
        assert_eq!(task.status, Status::Running);
        tasks.push(task);
    }
    // Keep the ledger in the window between the child's durable commit and
    // monitor settlement, which is the state startup recovery must reconcile.
    assert!(harness.service.shutdown().await);
    let completed_chat = tasks[0].child_chat_id.as_deref().unwrap();
    let completed_turn = tasks[0].child_turn_id.as_deref().unwrap();
    harness
        .control(completed_chat)
        .await
        .complete(1, COMMITTED_RESULT);
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let turn = harness
                .store
                .chat_orchestration_child_turn(completed_chat, completed_turn)
                .await
                .unwrap()
                .unwrap();
            if turn.turn_status.as_deref() == Some("completed")
                && turn.final_assistant_text.as_deref() == Some(COMMITTED_RESULT)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("provider completion was not committed before the fixture deadline");
    harness
        .store
        .request_chat_orchestration_cancel(&tasks[3].task_id)
        .await
        .unwrap();
    for (task, expected) in tasks.iter().zip([
        Status::Running,
        Status::Running,
        Status::Running,
        Status::CancelRequested,
    ]) {
        assert_eq!(
            harness
                .store
                .chat_orchestration_task(&task.task_id)
                .await
                .unwrap()
                .unwrap()
                .status,
            expected
        );
    }
    let old_token_path = harness
        .factory
        .launches
        .lock()
        .unwrap()
        .iter()
        .find(|launch| Some(&launch.chat_id) == tasks[1].child_chat_id.as_ref())
        .unwrap()
        .env["ALERA_CHAT_CREDENTIAL_FILE"]
        .clone();
    let old_token = std::fs::read_to_string(old_token_path).unwrap();
    assert!(harness
        .service
        .credential_hook()
        .verify(&old_token)
        .await
        .is_ok());
    (harness.directory, tasks, old_token)
}
