use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use crate::terminal_host::server::agent_chat_runtime::SendInput;

use super::delegation_tests::delegate_payload;
use super::paused_runtime_fixture::{CommandGate, PausedChatRuntime};
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

async fn ready(harness: &TestHarness, chat_id: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.service.runtime.snapshot(chat_id).await.unwrap();
            if snapshot["session"]["status"] == "ready"
                && snapshot["session"]["activeTurnId"].is_null()
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

#[tokio::test]
async fn cancellation_carries_its_ceiling_and_human_override_blocks_delayed_send_after_restart() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(
            &parent,
            "parent",
            "Delegate work with a cancellable admission.",
        )
        .await;
    let caller = harness.agent(&parent).await;
    let send_gate = CommandGate::for_operation(None, &caller.ctx.scope, "SendWithinCeiling");
    let sending_service = harness.service.clone().with_runtime(PausedChatRuntime::new(
        harness.service.runtime.clone(),
        send_gate.clone(),
    ));
    let sending_caller = caller.clone();
    let delegation = tokio::spawn(async move {
        sending_service
            .handle(
                "delegate",
                &delegate_payload(
                    "delayed-admission",
                    json!({"workspace": {"workspaceId": "ws-a"}}),
                ),
                &sending_caller,
            )
            .await
    });
    tokio::time::timeout(TEST_DEADLINE, send_gate.arrived.notified())
        .await
        .unwrap();
    let tasks = harness
        .service
        .handle(
            "tasks.list",
            &json!({"parentChatId": parent}),
            &human("desktop"),
        )
        .await
        .unwrap();
    let task_id = tasks["tasks"][0]["taskId"].as_str().unwrap().to_owned();
    let child = tasks["tasks"][0]["childChatId"]
        .as_str()
        .unwrap()
        .to_owned();
    let client_id = format!("chat-orchestration-task:{task_id}");
    ready(&harness, &child).await;
    let cancel_gate = CommandGate::for_operation(Some(&child), "runtime", "CancelMessage");
    let cancelling_service = harness.service.clone().with_runtime(PausedChatRuntime::new(
        harness.service.runtime.clone(),
        cancel_gate.clone(),
    ));
    let cancelling = cancelling_service.clone();
    let cancelling_task = task_id.clone();
    let cancellation = tokio::spawn(async move {
        cancelling
            .handle(
                "cancel",
                &json!({"requestId": "bound-cancel", "taskId": cancelling_task}),
                &caller,
            )
            .await
    });
    tokio::time::timeout(TEST_DEADLINE, cancel_gate.arrived.notified())
        .await
        .unwrap();
    cancelling_service
        .handle(
            "configure",
            &json!({"requestId": "human-elevation", "chatId": child,
        "runtimeMode": "full-access"}),
            &human("desktop"),
        )
        .await
        .unwrap();
    ready(&harness, &child).await;
    cancel_gate.release.notify_one();
    let denied = tokio::time::timeout(TEST_DEADLINE, cancellation)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(denied["errors"].as_array().unwrap().len(), 1);
    assert!(denied["errors"][0]["error"]
        .as_str()
        .unwrap()
        .contains("ceiling"));
    assert_eq!(
        cancel_gate.operations.lock().unwrap()[0]["WithinCeiling"]["runtime_mode_ceiling"],
        "auto"
    );
    let pending = harness
        .store
        .chat_orchestration_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.status, Status::CancelRequested);
    assert_eq!(
        pending.launch_options.as_ref().unwrap()["cancellationPolicy"],
        "bound"
    );
    assert_eq!(
        pending.launch_options.as_ref().unwrap()["cancellationRuntimeModeCeiling"],
        "auto"
    );
    assert!(!harness
        .store
        .is_agent_chat_message_cancelled(&child, &client_id)
        .await
        .unwrap());
    let current = harness.control(&child).await;
    assert!(current.turns.lock().unwrap().is_empty());
    assert!(current.interrupts.lock().unwrap().is_empty());
    let human_cancel = cancelling_service
        .handle(
            "cancel",
            &json!({"requestId": "human-cancel", "taskId": task_id}),
            &human("mobile:phone"),
        )
        .await
        .unwrap();
    assert!(human_cancel["errors"].as_array().unwrap().is_empty());
    harness.task_status(&task_id, Status::Cancelled).await;
    assert!(harness
        .store
        .is_agent_chat_message_cancelled(&child, &client_id)
        .await
        .unwrap());
    send_gate.release.notify_one();
    let delayed = tokio::time::timeout(TEST_DEADLINE, delegation)
        .await
        .unwrap()
        .unwrap();
    match delayed {
        Ok(response) => assert_eq!(response["status"], "cancelled"),
        Err(error) => assert!(matches!(
            error_code(&error),
            "mode_ceiling" | "request_resolved"
        )),
    }
    assert!(current.turns.lock().unwrap().is_empty());
    assert!(
        harness.service.runtime.snapshot(&child).await.unwrap()["items"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let harness = harness.restart().await;
    let persisted = harness
        .store
        .chat_orchestration_task(&task_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(persisted.status, Status::Cancelled);
    assert_eq!(
        persisted.launch_options.as_ref().unwrap()["cancellationPolicy"],
        "human"
    );
    assert!(harness
        .store
        .is_agent_chat_message_cancelled(&child, &client_id)
        .await
        .unwrap());
    let replay = harness
        .service
        .runtime
        .send(
            &child,
            SendInput {
                client_message_id: client_id,
                text: "Inspect only the child brief.".into(),
                attachments: Vec::new(),
                delivery: "auto".into(),
                model: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: None,
            },
            human("desktop").ctx,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&replay), "request_resolved");
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}
