use std::sync::{atomic::Ordering, Arc};
use std::time::Duration;

use alera_provider_protocol::{Attachment, NativeForkBoundary};
use serde_json::json;

use super::commands::{CallerCtx, ChatOp, ConfigureInput, ReceiptKey};

#[path = "session_delivery_fixture.rs"]
mod fixture;
use fixture::*;

#[path = "session_background_work_tests.rs"]
mod background_work;
#[path = "session_parent_resume_tests.rs"]
mod parent_resume;
#[path = "session_commands_tests.rs"]
mod provider_commands;
#[path = "session_queue_reorder_tests.rs"]
mod queue_reorder;
#[path = "session_redirect_tests.rs"]
mod redirect;

#[tokio::test]
async fn supported_effort_reaches_session_and_turn_and_remembering_waits_for_native_acceptance() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, Some("high")).await;
    let gate = Arc::new(SendGate::default());
    *factory.recorded.send_gate.lock().unwrap() = Some(gate.clone());
    send(&runtime, &chat, "first", "First accepted prompt").await;
    tokio::time::timeout(Duration::from_secs(5), gate.entered.notified())
        .await
        .unwrap();
    assert!(harness.store.agent_chat_preferences().await.unwrap()["rememberedSelection"].is_null());
    assert_eq!(
        factory.recorded.starts.lock().unwrap()[0].options["reasoningEffort"],
        "high"
    );
    assert_eq!(
        factory.recorded.turns.lock().unwrap()[0].options["reasoningEffort"],
        "high"
    );
    gate.release.notify_one();
    let control = provider_control(&factory, &chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    runtime.snapshot(&chat).await.unwrap();
    let preferences = harness.store.agent_chat_preferences().await.unwrap();
    assert_eq!(
        preferences["rememberedSelection"]["providerInstanceId"],
        "codex"
    );
    assert_eq!(
        preferences["rememberedSelection"]["model"],
        "verified-model"
    );
    finish_turn(&runtime, &factory, &chat, 1).await;
    runtime
        .command(
            &chat,
            ChatOp::Configure(ConfigureInput {
                reasoning_effort: Some(None),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    runtime
        .command(&chat, ChatOp::Stop, CallerCtx::runtime(), None)
        .await
        .unwrap();
    send(&runtime, &chat, "second", "Prompt after effort reset").await;
    wait_until(|| factory.recorded.turns.lock().unwrap().len() == 2).await;
    runtime.snapshot(&chat).await.unwrap();
    assert!(factory.recorded.starts.lock().unwrap()[1]
        .options
        .get("reasoningEffort")
        .is_none());
    assert!(factory.recorded.turns.lock().unwrap()[1]
        .options
        .get("reasoningEffort")
        .is_none());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn queue_edit_and_native_steer_preserve_attachments_and_receipt_replay_is_once() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    let started = send(&runtime, &chat, "first", "Running prompt").await;
    let control = provider_control(&factory, &chat).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    runtime.snapshot(&chat).await.unwrap();
    let attachments =
        vec![json!({"type":"image","url":"https://example.invalid/image.png","caption":"retain"})];
    let mut queued = input("queued", "Original queued prompt");
    queued.attachments = attachments.clone();
    let pending = runtime
        .send(&chat, queued, CallerCtx::runtime())
        .await
        .unwrap();
    let queue_id = pending["queueId"].as_str().unwrap().to_owned();
    runtime
        .command(
            &chat,
            ChatOp::QueueEdit {
                queue_id: queue_id.clone(),
                text: "Edited queued prompt".into(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let turn_id = started["turnId"].as_str().unwrap().to_owned();
    let op = ChatOp::QueuePromoteToSteer {
        queue_id: queue_id.clone(),
        turn_id: turn_id.clone(),
    };
    let key = ReceiptKey {
        verb: "agentChat.queueSteer".into(),
        request_id: "steer-once".into(),
        digest: "digest".into(),
    };
    factory.recorded.reject_steer.store(true, Ordering::SeqCst);
    assert!(runtime
        .command(&chat, op.clone(), CallerCtx::runtime(), Some(key.clone()))
        .await
        .is_err());
    let failed = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(failed["queue"][0]["text"], "Edited queued prompt");
    assert_eq!(failed["queue"][0]["attachments"], json!(attachments));
    assert!(!failed["items"]
        .as_array()
        .unwrap()
        .iter()
        .any(|item| item["clientMessageId"] == "queued"));
    factory.recorded.reject_steer.store(false, Ordering::SeqCst);
    let steered = runtime
        .command(&chat, op.clone(), CallerCtx::runtime(), Some(key.clone()))
        .await
        .unwrap();
    assert_eq!(
        runtime
            .command(&chat, op, CallerCtx::runtime(), Some(key))
            .await
            .unwrap(),
        steered
    );
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    assert!(snapshot["queue"].as_array().unwrap().is_empty());
    assert_eq!(snapshot["turns"].as_array().unwrap().len(), 1);
    let user = snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|item| item["clientMessageId"] == "queued")
        .unwrap();
    assert_eq!(user["turnId"], turn_id);
    assert_eq!(user["attachments"], json!(attachments));
    let calls = factory.recorded.steers.lock().unwrap().clone();
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[1].1, "native-turn-1");
    assert_ne!(calls[1].1, turn_id);
    assert_eq!(calls[1].0.input, "Edited queued prompt");
    assert_eq!(
        calls[1].0.attachments,
        vec![Attachment::Image {
            url: "https://example.invalid/image.png".into()
        }]
    );
    assert_eq!(control.turns.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn deferred_native_fork_uses_the_selected_old_boundary_and_sends_no_duplicate_handoff() {
    let (harness, runtime, factory) = fixture().await;
    let source = create(&runtime, None).await;
    let first = send(&runtime, &source, "source-first", "Original prefix").await;
    let control = provider_control(&factory, &source).await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(1))
        .await
        .unwrap();
    finish_turn(&runtime, &factory, &source, 1).await;
    send(&runtime, &source, "source-second", "Later source prompt").await;
    tokio::time::timeout(Duration::from_secs(5), control.wait_turns(2))
        .await
        .unwrap();
    finish_turn(&runtime, &factory, &source, 2).await;
    let source_native = harness
        .store
        .agent_chat(&source)
        .await
        .unwrap()
        .unwrap()
        .native_thread_id
        .unwrap();
    let forked = runtime
        .fork(
            &source,
            first["turnId"].as_str().unwrap(),
            None,
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let target = forked["chatId"].as_str().unwrap();
    assert_eq!(forked["operationKind"], "nativeForkDeferred");
    assert_eq!(factory.inner.launches.lock().unwrap().len(), 1);
    assert!(factory.recorded.forks.lock().unwrap().is_empty());
    send(&runtime, target, "target-first", "Continue this fork").await;
    wait_until(|| factory.recorded.forks.lock().unwrap().len() == 1).await;
    let target_control = provider_control(&factory, target).await;
    tokio::time::timeout(Duration::from_secs(5), target_control.wait_turns(1))
        .await
        .unwrap();
    let snapshot = runtime.snapshot(target).await.unwrap();
    let native = factory.recorded.forks.lock().unwrap()[0].clone();
    assert_eq!(native.source_native_thread_id, source_native);
    assert_eq!(
        native.boundary,
        Some(NativeForkBoundary::Turn("native-turn-1".into()))
    );
    assert_eq!(native.session.thread_id, target);
    assert!(native.session.resume_thread_id.is_none());
    assert_eq!(factory.inner.launches.lock().unwrap().len(), 2);
    assert!(!factory
        .recorded
        .starts
        .lock()
        .unwrap()
        .iter()
        .any(|start| start.thread_id == target));
    assert_eq!(
        target_control.turns.lock().unwrap()[0].input,
        "Continue this fork"
    );
    assert_eq!(
        snapshot["session"]["historyOperation"]["kind"],
        "nativeFork"
    );
    let target_record = harness.store.agent_chat(target).await.unwrap().unwrap();
    assert_eq!(
        target_record.native_thread_id.as_deref(),
        Some(format!("fork-native-{target}").as_str())
    );
    assert_ne!(
        target_record.native_thread_id.as_deref(),
        Some(source_native.as_str())
    );
    assert!(target_record.metadata.unwrap().get("nativeFork").is_none());
    runtime.shutdown().await;
    harness.finish().await;
}

fn handoff_markers(snapshot: &serde_json::Value) -> Vec<serde_json::Value> {
    snapshot["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|item| item["type"] == "notice" && item["normalized"]["handoff"].is_object())
        .cloned()
        .collect()
}

#[tokio::test]
async fn provider_switch_records_a_handoff_marker_that_fails_with_its_turn() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Earlier question").await;
    finish_turn(&runtime, &factory, &chat, 1).await;
    assert!(handoff_markers(&runtime.snapshot(&chat).await.unwrap()).is_empty());
    runtime
        .command(
            &chat,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("claudeAgent".into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();

    factory.recorded.reject_send.store(true, Ordering::SeqCst);
    let failed = send(&runtime, &chat, "second", "Continue here").await;
    wait_until(|| factory.recorded.turns.lock().unwrap().len() == 2).await;
    tokio::time::timeout(Duration::from_secs(5), async {
        while !runtime.snapshot(&chat).await.unwrap()["session"]["activeTurnId"].is_null() {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let snapshot = runtime.snapshot(&chat).await.unwrap();
    let markers = handoff_markers(&snapshot);
    assert_eq!(markers.len(), 1);
    assert_eq!(markers[0]["turnId"], failed["turnId"]);
    assert_eq!(markers[0]["status"], "failed");
    let handoff = &markers[0]["normalized"]["handoff"];
    assert_eq!(handoff["status"], "failed");
    assert_eq!(handoff["from"]["provider"], "codex");
    assert_eq!(handoff["from"]["model"], "verified-model");
    assert_eq!(handoff["to"]["provider"], "claudeAgent");

    factory.recorded.reject_send.store(false, Ordering::SeqCst);
    let retried = send(&runtime, &chat, "third", "Try again").await;
    wait_until(|| factory.recorded.turns.lock().unwrap().len() == 3).await;
    assert!(factory.recorded.turns.lock().unwrap()[2]
        .input
        .contains("Earlier question"));
    let markers = handoff_markers(&runtime.snapshot(&chat).await.unwrap());
    assert_eq!(markers.len(), 2);
    let retry = markers
        .iter()
        .find(|marker| marker["turnId"] == retried["turnId"])
        .unwrap();
    assert_eq!(retry["status"], "completed");
    assert_eq!(retry["normalized"]["handoff"]["status"], "completed");
    // The retry names where the context came from, not the failed turn.
    assert_eq!(retry["normalized"]["handoff"]["from"]["provider"], "codex");
    assert_eq!(
        retry["normalized"]["handoff"]["to"]["provider"],
        "claudeAgent"
    );
    runtime.shutdown().await;
    harness.finish().await;
}
