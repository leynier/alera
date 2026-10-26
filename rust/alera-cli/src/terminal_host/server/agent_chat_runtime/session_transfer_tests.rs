use std::sync::{atomic::Ordering, Arc};
use std::time::Duration;

use serde_json::{json, Value};

use super::super::commands::{CallerCtx, ChatOp, ConfigureInput};
use super::super::events::NullSink;
use super::super::session_transfers::{ContextTransfer, TransferKind, TransferStatus};
use super::super::{AgentChatRuntime, InstanceDirectory};
use super::fixture::*;

fn transfers(snapshot: &Value) -> Vec<Value> {
    snapshot["contextTransfers"]
        .as_array()
        .cloned()
        .unwrap_or_default()
}

async fn transfer_where(
    runtime: &AgentChatRuntime,
    chat: &str,
    test: impl Fn(&Value) -> bool,
) -> Value {
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        let snapshot = runtime.snapshot(chat).await.unwrap();
        if let Some(found) = transfers(&snapshot).into_iter().find(|value| test(value)) {
            return found;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "no matching transfer in {:#}",
            snapshot["contextTransfers"]
        );
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

#[tokio::test]
async fn forks_and_merge_backs_leave_records_that_survive_a_restart() {
    let (harness, runtime, factory) = fixture().await;
    let source = create(&runtime, None).await;
    let first = send(&runtime, &source, "first", "Plan the cache").await;
    let control = provider_control(&factory, &source).await;
    control.wait_turns(1).await;
    finish_turn(&runtime, &factory, &source, 1).await;
    let forked = runtime
        .fork(
            &source,
            first["turnId"].as_str().unwrap(),
            Some("Cache experiment".into()),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let fork = forked["chatId"].as_str().unwrap().to_owned();
    let fork_records = transfers(&forked["snapshot"]);
    assert_eq!(fork_records.len(), 1);
    assert_eq!(fork_records[0]["kind"], "fork");
    assert_eq!(fork_records[0]["sourceChatId"], source.as_str());
    assert_eq!(fork_records[0]["targetChatId"], fork.as_str());
    assert_eq!(fork_records[0]["sourceTurnId"], first["turnId"]);
    assert_eq!(fork_records[0]["status"], "consumed");
    // The source keeps no record: the context moved into the fork.
    assert!(transfers(&runtime.snapshot(&source).await.unwrap()).is_empty());

    send(&runtime, &fork, "fork-first", "Try an LRU cache").await;
    provider_control(&factory, &fork).await.wait_turns(1).await;
    finish_turn(&runtime, &factory, &fork, 1).await;
    let merged = runtime
        .merge_back(&fork, CallerCtx::runtime(), None)
        .await
        .unwrap();
    let pending = transfer_where(&runtime, &source, |value| value["kind"] == "mergeBack").await;
    assert_eq!(pending["status"], "pending");
    assert_eq!(pending["sourceChatId"], fork.as_str());
    assert_eq!(pending["sourceTitle"], "Cache experiment");
    assert_eq!(pending["itemId"], merged["itemId"]);
    assert!(pending.get("consumedAt").is_none());

    let second = send(&runtime, &source, "second", "Which one wins?").await;
    control.wait_turns(2).await;
    let consumed = transfer_where(&runtime, &source, |value| {
        value["kind"] == "mergeBack" && value["status"] == "consumed"
    })
    .await;
    assert_eq!(consumed["transferId"], pending["transferId"]);
    assert_eq!(consumed["targetTurnId"], second["turnId"]);
    assert!(consumed["consumedAt"].is_string());
    finish_turn(&runtime, &factory, &source, 2).await;
    runtime.shutdown().await;

    let restarted = AgentChatRuntime::new(
        harness.store.clone(),
        factory.clone(),
        Arc::new(harness.store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    );
    let after = transfers(&restarted.snapshot(&source).await.unwrap());
    assert_eq!(after, vec![consumed]);
    assert_eq!(
        transfers(&restarted.snapshot(&fork).await.unwrap())[0]["kind"],
        "fork"
    );
    restarted.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_provider_handoff_record_follows_its_marker() {
    let (harness, runtime, factory) = fixture().await;
    let chat = create(&runtime, None).await;
    send(&runtime, &chat, "first", "Earlier question").await;
    finish_turn(&runtime, &factory, &chat, 1).await;
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
    let failed_record = transfer_where(&runtime, &chat, |value| {
        value["targetTurnId"] == failed["turnId"] && value["status"] == "failed"
    })
    .await;
    assert_eq!(failed_record["kind"], "providerHandoff");
    assert_eq!(failed_record["sourceChatId"], chat.as_str());
    assert_eq!(failed_record["targetChatId"], chat.as_str());
    assert_eq!(failed_record["from"]["provider"], "codex");
    assert_eq!(failed_record["to"]["provider"], "claudeAgent");
    assert!(failed_record["itemId"].is_string());

    factory.recorded.reject_send.store(false, Ordering::SeqCst);
    let retried = send(&runtime, &chat, "third", "Try again").await;
    let retry_record = transfer_where(&runtime, &chat, |value| {
        value["targetTurnId"] == retried["turnId"] && value["status"] == "consumed"
    })
    .await;
    assert_ne!(retry_record["transferId"], failed_record["transferId"]);
    assert_eq!(retry_record["from"]["provider"], "codex");
    runtime.shutdown().await;
    harness.finish().await;
}

#[tokio::test]
async fn a_delegated_record_is_kept_once_per_task_and_only_by_its_target() {
    let (harness, runtime, _factory) = fixture().await;
    let parent = create(&runtime, None).await;
    let child = create(&runtime, None).await;
    let brief = |status| {
        let mut transfer =
            ContextTransfer::new(TransferKind::SubagentSpawn, &parent, &child, status);
        transfer.task_id = Some("task-1".into());
        transfer
    };
    let record = |transfer| ChatOp::RecordTransfer(transfer);
    let first = runtime
        .command(
            &child,
            record(brief(TransferStatus::Pending)),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let replay = runtime
        .command(
            &child,
            record(brief(TransferStatus::Consumed)),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert_eq!(first["transferId"], replay["transferId"]);
    let stored = transfers(&runtime.snapshot(&child).await.unwrap());
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0]["status"], "consumed");
    assert_eq!(stored[0]["taskId"], "task-1");

    let misdirected = runtime
        .command(
            &parent,
            record(brief(TransferStatus::Consumed)),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap_err();
    assert!(format!("{misdirected:?}").contains("transferTarget"));
    assert_eq!(
        runtime.snapshot(&parent).await.unwrap()["contextTransfers"],
        json!(null)
    );
    runtime.shutdown().await;
    harness.finish().await;
}
