use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::paused_runtime_fixture::{CommandGate, PausedChatRuntime};
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

async fn idle(harness: &TestHarness, chat_id: &str) {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.service.runtime.snapshot(chat_id).await.unwrap();
            if matches!(
                snapshot["session"]["status"].as_str(),
                Some("ready" | "stopped")
            ) && snapshot["session"]["activeTurnId"].is_null()
            {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
}

async fn pending_request(harness: &TestHarness, chat_id: &str) -> String {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let requests = harness
                .service
                .handle("requests", &json!({"chatId": chat_id}), &human("desktop"))
                .await
                .unwrap();
            if let Some(id) = requests["requests"][0]["request"]["requestId"].as_str() {
                break id.into();
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn bound_controls_recheck_target_mode_at_actor_admission_after_human_configuration() {
    for verb in ["interrupt", "respond", "configure"] {
        let harness = TestHarness::new().await;
        let parent = harness.create_chat("ws-a", "auto").await;
        harness
            .send_human(
                &parent,
                "parent",
                "Coordinate authorized descendant controls.",
            )
            .await;
        let caller = harness.agent(&parent).await;
        let task = harness
            .service
            .handle(
                "delegate",
                &delegate_payload("descendant", json!({"workspace": {"workspaceId": "ws-a"}})),
                &caller,
            )
            .await
            .unwrap();
        let child = task["childChatId"].as_str().unwrap();
        let before = harness.control(child).await;
        tokio::time::timeout(TEST_DEADLINE, before.wait_turns(1))
            .await
            .unwrap();
        before.complete(1, "Initial delegated turn completed.");
        harness
            .task_status(task["taskId"].as_str().unwrap(), Status::Completed)
            .await;
        idle(&harness, child).await;
        let mut payload = json!({"requestId": format!("bound-{verb}"), "chatId": child});
        if verb == "configure" {
            payload["model"] = json!("racing-agent-model");
        }
        if verb == "respond" {
            harness
                .send_human(child, "question-turn", "Ask for a human answer.")
                .await;
            tokio::time::timeout(TEST_DEADLINE, before.wait_turns(2))
                .await
                .unwrap();
            before.request_input(2, "native-racing-question");
            payload["runtimeRequestId"] = json!(pending_request(&harness, child).await);
            payload["response"] =
                json!({"type": "userInput", "answers": {"choice": "Bound answer."}});
        }
        let gate = CommandGate::new(child, &caller.ctx.scope);
        let paused = harness.service.clone().with_runtime(PausedChatRuntime::new(
            harness.service.runtime.clone(),
            gate.clone(),
        ));
        let sending = paused.clone();
        let bound_payload = payload.clone();
        let control =
            tokio::spawn(async move { sending.handle(verb, &bound_payload, &caller).await });
        tokio::time::timeout(TEST_DEADLINE, gate.arrived.notified())
            .await
            .unwrap();
        if verb == "respond" {
            paused
                .handle(
                    "respond",
                    &json!({"requestId": "human-first-answer", "chatId": child,
                "runtimeRequestId": payload["runtimeRequestId"], "response": {"type": "userInput",
                    "answers": {"choice": "Human answer."}}}),
                    &human("desktop"),
                )
                .await
                .unwrap();
            before.complete(2, "The human resolved the prior request.");
            idle(&harness, child).await;
        }
        paused
            .handle(
                "configure",
                &json!({"requestId": "human-elevation", "chatId": child,
            "runtimeMode": "full-access", "model": "human-model"}),
                &human("mobile:phone"),
            )
            .await
            .unwrap();
        idle(&harness, child).await;
        gate.release.notify_one();
        let error = tokio::time::timeout(TEST_DEADLINE, control)
            .await
            .unwrap()
            .unwrap()
            .unwrap_err();
        assert_eq!(error_code(&error), "mode_ceiling", "{verb}");
        let carried = gate.operations.lock().unwrap()[0].clone();
        assert_eq!(carried["WithinCeiling"]["runtime_mode_ceiling"], "auto");
        let snapshot = harness.service.runtime.snapshot(child).await.unwrap();
        assert_eq!(snapshot["session"]["runtimeMode"], "full-access");
        assert_eq!(snapshot["session"]["model"], "human-model");
        assert!(before.interrupts.lock().unwrap().is_empty());
        assert_eq!(snapshot["session"]["status"], "stopped");
        assert_eq!(
            harness
                .factory
                .launches
                .lock()
                .unwrap()
                .iter()
                .filter(|launch| launch.chat_id == child)
                .count(),
            1
        );
        assert_eq!(
            before.responses.lock().unwrap().len(),
            usize::from(verb == "respond")
        );
        if verb == "configure" {
            paused
                .handle(
                    "configure",
                    &json!({"requestId": "human-final-configure", "chatId": child,
                "model": "human-final-model"}),
                    &human("desktop"),
                )
                .await
                .unwrap();
            assert_eq!(
                harness.service.runtime.snapshot(child).await.unwrap()["session"]["model"],
                "human-final-model"
            );
            harness
                .send_human(
                    child,
                    "human-final-model-turn",
                    "Send with the human-selected model.",
                )
                .await;
            let current = harness.factory.control_after(child, &before).await;
            tokio::time::timeout(TEST_DEADLINE, current.wait_turns(1))
                .await
                .unwrap();
            assert_eq!(
                current.turns.lock().unwrap()[0].model.as_deref(),
                Some("human-final-model")
            );
        } else {
            harness
                .send_human(
                    child,
                    "human-high-mode",
                    "Human authority remains available.",
                )
                .await;
            let current = harness.factory.control_after(child, &before).await;
            tokio::time::timeout(TEST_DEADLINE, current.wait_turns(1))
                .await
                .unwrap();
            if verb == "interrupt" {
                paused
                    .handle(
                        "interrupt",
                        &json!({"requestId": "human-final-interrupt", "chatId": child}),
                        &human("desktop"),
                    )
                    .await
                    .unwrap();
                assert_eq!(current.interrupts.lock().unwrap().len(), 1);
            } else {
                current.request_input(1, "native-human-high-mode");
                let id = pending_request(&harness, child).await;
                paused.handle("respond", &json!({"requestId": "human-final-answer", "chatId": child,
                    "runtimeRequestId": id, "response": {"type": "userInput", "answers": {"choice": "Allowed."}}}),
                    &human("mobile:phone")).await.unwrap();
                assert_eq!(current.responses.lock().unwrap().len(), 1);
            }
        }
        assert!(!snapshot.to_string().contains("racing-agent-model"));
        harness.finish().await;
    }
}
