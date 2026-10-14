use super::*;
use serde_json::json;

#[derive(Default)]
struct FailOnceHook(AtomicUsize);

#[tokio::test]
async fn disabling_selected_instance_during_launch_hook_never_spawns_defaults() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    harness
        .runtime
        .instances()
        .replace(vec![
            super::super::super::provider_factory::ProviderInstanceConfig {
                provider_instance_id: "codex".into(),
                provider: "codex".into(),
                enabled: false,
                ..Default::default()
            },
        ])
        .await;
    harness.gate.release.notify_one();
    let snapshot = status(&harness, &chat_id, "error").await;
    assert_eq!(snapshot["recovery"]["kind"], "providerMissing");
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(harness.live_credential_count(&chat_id).await, 0);
    assert_eq!(snapshot["turns"].as_array().unwrap().len(), 1);
    harness.finish().await;
}

#[async_trait]
impl ProviderLaunchHook for FailOnceHook {
    async fn prepare(&self, _: &mut ProviderLaunch) -> Result<(), String> {
        if self.0.fetch_add(1, Ordering::SeqCst) == 0 {
            Err("First launch failed".into())
        } else {
            Ok(())
        }
    }
}

async fn status(harness: &StartupHarness, chat_id: &str, expected: &str) -> serde_json::Value {
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            let snapshot = harness.runtime.snapshot(chat_id).await.unwrap();
            if snapshot["session"]["status"] == expected {
                return snapshot;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn deferred_first_send_injects_credentials_only_at_spawn() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(harness.live_credential_count(&chat_id).await, 0);
    harness.gate.release.notify_one();
    let control = tokio::time::timeout(TEST_DEADLINE, harness.factory.control(&chat_id))
        .await
        .unwrap();
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let launch = harness.factory.launches.lock().unwrap()[0].clone();
    let token = std::fs::read_to_string(&launch.env["ALERA_CHAT_CREDENTIAL_FILE"]).unwrap();
    let binding = harness.credentials.verify(&token).await.unwrap();
    assert_eq!(binding.chat_id, chat_id);
    assert_eq!(binding.generation, launch.generation);
    assert_eq!(harness.live_credential_count(&chat_id).await, 1);
    harness.finish().await;
}

#[tokio::test]
async fn cancelling_owned_message_cancels_deferred_startup_before_credentials() {
    let harness = StartupHarness::new().await;
    let chat_id = harness.create_paused_chat().await;
    let response = harness
        .runtime
        .command(
            &chat_id,
            ChatOp::CancelMessage {
                client_message_id: "first-startup-message".into(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(response["cancelled"], true);
    harness.assert_cancelled_without_launch(&chat_id).await;
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert_eq!(snapshot["turns"][0]["status"], "interrupted");
    assert_eq!(snapshot["session"]["status"], "stopped");
    harness.finish().await;
}

#[tokio::test]
async fn failed_first_start_keeps_message_and_recovery_does_not_resend_it() {
    let harness = StartupHarness::new().await;
    harness
        .runtime
        .register_launch_hook(Arc::new(FailOnceHook::default()));
    let chat_id = harness.create_paused_chat().await;
    harness.gate.release.notify_one();
    let snapshot = status(&harness, &chat_id, "error").await;
    assert_eq!(snapshot["turns"].as_array().unwrap().len(), 1);
    assert_eq!(
        snapshot["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|item| item["type"] == "user_message")
            .count(),
        1
    );
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    assert_eq!(harness.live_credential_count(&chat_id).await, 0);
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Recover {
                mode: Some("restart".into()),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    status(&harness, &chat_id, "ready").await;
    let control = tokio::time::timeout(TEST_DEADLINE, harness.factory.control(&chat_id))
        .await
        .unwrap();
    let replay = harness
        .runtime
        .send(
            &chat_id,
            SendInput {
                client_message_id: "first-startup-message".into(),
                text: "Start the deferred provider.".into(),
                attachments: Vec::new(),
                delivery: "auto".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: None,
            },
            CallerCtx::runtime(),
        )
        .await
        .unwrap();
    assert_eq!(replay["delivery"], "started");
    assert!(control.turns.lock().unwrap().is_empty());
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert_eq!(snapshot["turns"].as_array().unwrap().len(), 1);
    assert_eq!(
        snapshot["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|item| item["type"] == "user_message")
            .count(),
        1
    );
    assert_eq!(snapshot["titleSource"], json!("derived"));
    harness.finish().await;
}
