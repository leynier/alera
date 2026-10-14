use std::sync::atomic::Ordering;
use std::time::Duration;

use alera_provider_protocol::{CanonicalItemType, EventKind, NativeRollbackBoundary};
use serde_json::json;

use super::commands::{CallerCtx, ChatOp, SendInput};

#[path = "session_native_history_fixture.rs"]
mod fixture;
use fixture::*;

#[tokio::test]
async fn native_conversation_acknowledgment_and_exact_receipt_replay_call_the_provider_once() {
    let (harness, runtime, factory, chat) = fixture("codex").await;
    let first = send(&runtime, &factory, &chat, "first", 1).await;
    complete(&runtime, &factory, &chat, 1).await;
    send(&runtime, &factory, &chat, "later", 2).await;
    complete(&runtime, &factory, &chat, 2).await;
    let source = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    let op = ChatOp::NativeRewind {
        turn_id: first["turnId"].as_str().unwrap().into(),
    };
    let response = command(&runtime, &chat, op.clone(), "native-once")
        .await
        .unwrap();
    let replay = command(&runtime, &chat, op, "native-once").await.unwrap();
    assert_eq!(replay, response);
    assert_eq!(response["nativeRollback"], true);
    assert_eq!(response["filesystemChangesReverted"], false);
    assert_eq!(response["prompt"], "Prompt first");
    assert!(!response.to_string().contains("private-provider-reply"));
    let calls = factory.records.rollbacks.lock().unwrap().clone();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].thread_id, chat);
    assert_eq!(
        calls[0].boundary,
        NativeRollbackBoundary::BeforeTurn("native-turn-1".into())
    );
    let rewound = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    assert_eq!(rewound.generation, source.generation + 1);
    assert_eq!(rewound.native_thread_id, source.native_thread_id);
    assert!(rewound.snapshot["items"].as_array().unwrap().is_empty());
    assert!(harness
        .store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .is_none());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn lost_native_reply_freezes_across_restart_until_explicit_transcript_fallback() {
    let (harness, runtime, factory, chat) = fixture("codex").await;
    let first = send(&runtime, &factory, &chat, "first", 1).await;
    complete(&runtime, &factory, &chat, 1).await;
    factory.records.fail_rollback.store(true, Ordering::SeqCst);
    let op = ChatOp::NativeRewind {
        turn_id: first["turnId"].as_str().unwrap().into(),
    };
    assert!(command(&runtime, &chat, op.clone(), "unknown-once")
        .await
        .is_err());
    assert!(command(&runtime, &chat, op.clone(), "unknown-once")
        .await
        .is_err());
    let pending = harness
        .store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.state, "uncertain");
    assert_eq!(factory.records.rollbacks.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    let recovered = fixture::runtime(&harness, factory.clone());
    let snapshot = recovered.snapshot(&chat).await.unwrap();
    assert_eq!(snapshot["pendingNativeOperation"]["state"], "uncertain");
    assert!(command(&recovered, &chat, op.clone(), "unknown-once")
        .await
        .is_err());
    let input = serde_json::from_value::<SendInput>(json!({
        "client_message_id":"blocked-send","text":"Do not submit this","attachments":[],"delivery":"auto",
    })).unwrap();
    assert!(recovered
        .send(&chat, input, CallerCtx::runtime())
        .await
        .is_err());
    assert_eq!(factory.records.rollbacks.lock().unwrap().len(), 1);
    assert_eq!(factory.records.turns.lock().unwrap().len(), 1);
    let reconcile = ChatOp::NativeHistoryReconcile {
        operation_id: pending.operation_id.clone(),
        expected_revision: Some(pending.revision),
        action: "restartFromTranscript".into(),
    };
    let continued = command(&recovered, &chat, reconcile.clone(), "fallback-once")
        .await
        .unwrap();
    assert_eq!(
        command(&recovered, &chat, reconcile, "fallback-once")
            .await
            .unwrap(),
        continued
    );
    assert_eq!(continued["operation"]["state"], "reconciled");
    assert_eq!(continued["result"]["nativeRollback"], false);
    assert_eq!(continued["result"]["operationKind"], "transcriptRewind");
    let record = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    assert!(record.native_thread_id.is_none());
    assert!(record.snapshot["items"].as_array().unwrap().is_empty());
    let original_replay = command(&recovered, &chat, op, "unknown-once")
        .await
        .unwrap();
    assert_eq!(original_replay["nativeRollback"], false);
    assert_eq!(factory.records.rollbacks.lock().unwrap().len(), 1);
    recovered.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn workspace_sleep_preserves_uncertain_recovery_and_allows_reconcile_without_native_repeat() {
    let (harness, runtime, factory, chat) = fixture("codex").await;
    let first = send(&runtime, &factory, &chat, "sleep-source", 1).await;
    complete(&runtime, &factory, &chat, 1).await;
    factory.records.fail_rollback.store(true, Ordering::SeqCst);
    let original = ChatOp::NativeRewind {
        turn_id: first["turnId"].as_str().unwrap().into(),
    };
    assert!(command(&runtime, &chat, original.clone(), "sleep-native")
        .await
        .is_err());
    let pending = harness
        .store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(pending.state, "uncertain");
    let before = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    for _ in 0..2 {
        let stopped = runtime
            .command(&chat, ChatOp::Stop, CallerCtx::runtime(), None)
            .await
            .unwrap();
        assert_eq!(stopped["stopped"], true);
    }
    let after = harness.store.agent_chat(&chat).await.unwrap().unwrap();
    assert_eq!(after.snapshot, before.snapshot);
    assert_eq!(after.cursor, before.cursor);
    assert_eq!(after.generation, before.generation);
    assert_eq!(after.native_thread_id, before.native_thread_id);
    assert_eq!(
        harness
            .store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap(),
        pending
    );
    let reconcile = ChatOp::NativeHistoryReconcile {
        operation_id: pending.operation_id,
        expected_revision: Some(pending.revision),
        action: "restartFromTranscript".into(),
    };
    let response = command(&runtime, &chat, reconcile.clone(), "sleep-reconcile")
        .await
        .unwrap();
    assert_eq!(response["operation"]["state"], "reconciled");
    assert_eq!(response["result"]["nativeRollback"], false);
    assert_eq!(response["result"]["prompt"], "Prompt sleep-source");
    assert_eq!(
        command(&runtime, &chat, reconcile, "sleep-reconcile")
            .await
            .unwrap(),
        response
    );
    let replay = command(&runtime, &chat, original, "sleep-native")
        .await
        .unwrap();
    assert_eq!(replay["nativeRollback"], false);
    assert_eq!(factory.records.rollbacks.lock().unwrap().len(), 1);
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn legacy_count_rollback_and_old_process_epoch_are_rejected_before_native_io() {
    let (harness, runtime, factory, chat) = fixture("codex").await;
    let first = send(&runtime, &factory, &chat, "first", 1).await;
    complete(&runtime, &factory, &chat, 1).await;
    let op = ChatOp::NativeRewind {
        turn_id: first["turnId"].as_str().unwrap().into(),
    };
    factory.records.legacy_only.store(true, Ordering::SeqCst);
    assert!(command(&runtime, &chat, op.clone(), "legacy-rejected")
        .await
        .is_err());
    assert!(factory.records.rollbacks.lock().unwrap().is_empty());
    factory.records.legacy_only.store(false, Ordering::SeqCst);
    runtime
        .command(&chat, ChatOp::Stop, CallerCtx::runtime(), None)
        .await
        .unwrap();
    runtime
        .command(
            &chat,
            ChatOp::Recover {
                mode: Some("resume".into()),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    wait_for_starts(&factory, 2).await;
    runtime.snapshot(&chat).await.unwrap();
    assert!(command(&runtime, &chat, op, "old-epoch-rejected")
        .await
        .is_err());
    assert!(factory.records.rollbacks.lock().unwrap().is_empty());
    assert!(harness
        .store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .is_none());
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn file_rewind_requires_checkpoint_launch_and_correlated_user_uuid_and_keeps_transcript() {
    checked_file_rewind(None).await;
}

#[tokio::test]
async fn file_rewind_empty_provider_observations_do_not_claim_restoration() {
    checked_file_rewind(Some(Vec::new())).await;
}

#[tokio::test]
async fn file_rewind_nonempty_provider_observations_confirm_restoration() {
    checked_file_rewind(Some(vec!["src/observed.rs".into()])).await;
}

async fn checked_file_rewind(files_changed: Option<Vec<String>>) {
    let (harness, runtime, factory, chat) = fixture("claudeAgent").await;
    let observed_changes = files_changed
        .as_ref()
        .is_some_and(|files| !files.is_empty());
    *factory.records.files_changed.lock().unwrap() = files_changed;
    command(
        &runtime,
        &chat,
        ChatOp::NativeFileCheckpoints { enabled: true },
        "enable-checkpoints",
    )
    .await
    .unwrap();
    assert!(factory.inner.launches.lock().unwrap().is_empty());
    let started = send(&runtime, &factory, &chat, "file-source", 1).await;
    complete(&runtime, &factory, &chat, 1).await;
    assert_eq!(
        factory.records.starts.lock().unwrap()[0].options["enableFileCheckpointing"],
        true
    );
    let turn_id = started["turnId"].as_str().unwrap().to_owned();
    let op = ChatOp::NativeRewindFiles {
        turn_id: turn_id.clone(),
    };
    assert!(command(&runtime, &chat, op.clone(), "no-user-boundary")
        .await
        .is_err());
    assert!(factory.records.files.lock().unwrap().is_empty());
    let app_item_id = factory.records.turns.lock().unwrap()[0].options["appUserItemId"]
        .as_str()
        .unwrap()
        .to_owned();
    assert_eq!(app_item_id, started["itemId"].as_str().unwrap());
    let native_user_uuid = uuid::Uuid::new_v4().to_string();
    control(&factory, &chat).await.event(
        EventKind::ItemUpdated,
        1,
        json!({
            "itemType":CanonicalItemType::UserMessage,"status":"completed",
            "nativeUserMessageId":native_user_uuid,"appUserItemId":app_item_id,
            "data":{"text":"Native echo must not create another visible user message"},
        }),
    );
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if harness
                .store
                .agent_chat_native_id_for_app(&chat, 1, "userTurn", &turn_id)
                .await
                .unwrap()
                .is_some()
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let before = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(
        before["items"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|item| item["type"] == "user_message")
            .count(),
        1
    );
    assert!(!before.to_string().contains(&native_user_uuid));
    let response = command(&runtime, &chat, op.clone(), "file-once")
        .await
        .unwrap();
    assert_eq!(
        command(&runtime, &chat, op, "file-once").await.unwrap(),
        response
    );
    assert_eq!(response["filesystemRewindAcknowledged"], true);
    if observed_changes {
        assert_eq!(response["filesystemChangesReverted"], true);
    } else {
        assert!(response["filesystemChangesReverted"].is_null());
    }
    assert!(!response.to_string().contains("private-provider-reply"));
    assert!(!response.to_string().contains(&native_user_uuid));
    let calls = factory.records.files.lock().unwrap().clone();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].native_user_message_id, native_user_uuid);
    let after = runtime.snapshot(&chat).await.unwrap();
    assert_eq!(after["items"], before["items"]);
    assert_eq!(after["turns"], before["turns"]);
    runtime.shutdown().await;
    harness.finish().await;
}
