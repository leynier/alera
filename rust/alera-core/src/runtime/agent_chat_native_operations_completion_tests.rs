use serde_json::{json, Value};

use super::test_support::*;
use crate::runtime::agent_chat_test_support::next_snapshot;
use crate::runtime::*;

fn committed(outcome: AgentChatNativeOperationCompleteOutcome) -> (AgentChatRecord, Value) {
    let AgentChatNativeOperationCompleteOutcome::Committed {
        record,
        event,
        response,
    } = outcome
    else {
        panic!("expected atomic completion");
    };
    assert_eq!(event.delta["snapshotRequired"], true);
    (*record, response)
}

async fn original_response(store: &RuntimeStore, id: &str) -> AgentChatReceiptCheck {
    store
        .check_agent_chat_receipt(
            &json!(["desktop", "agentChat.nativeRewind"]).to_string(),
            id,
            id,
        )
        .await
        .unwrap()
}

async fn force_receipt_failure(store: &RuntimeStore) {
    sqlx::query("CREATE TRIGGER failNativeReceipt BEFORE INSERT ON agentChatReceipts BEGIN SELECT RAISE(ABORT, 'test receipt persistence failure'); END")
        .execute(store.pool()).await.unwrap();
}

#[tokio::test]
async fn acknowledged_reopen_finishes_prefix_at_current_cursor_and_saves_exact_reconcile_wrapper() {
    let (dir, store, chat) = fixture().await;
    let op = acknowledge(&store, &begin(&store, &chat, "one", false).await).await;
    let (cursor, mut header) = next_snapshot(&store, &chat).await;
    header["session"]["status"] = json!("stopped");
    header["session"]["capabilities"] = json!({});
    header["pendingNativeOperation"] = agent_chat_native_operation_public_summary(&op);
    store.commit_agent_chat(&chat, cursor, &header, &json!({"session":header["session"],"pendingNativeOperation":header["pendingNativeOperation"]}), None).await.unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .recover_agent_chat_native_operations()
            .await
            .unwrap(),
        0
    );
    let snapshot = stopped_snapshot(&reopened, &chat).await;
    let reconcile = reconcile("finish");
    let (record, response) = committed(
        reopened
            .complete_agent_chat_native_rewind(
                &chat,
                "one",
                op.revision,
                1,
                &snapshot,
                Some(&reconcile),
            )
            .await
            .unwrap(),
    );
    assert_eq!(record.generation, 2);
    assert_eq!(record.native_thread_id.as_deref(), Some("native-thread"));
    assert_eq!(record.snapshot["turns"].as_array().unwrap().len(), 1);
    assert_eq!(record.snapshot["items"].as_array().unwrap().len(), 2);
    assert_eq!(record.snapshot["pendingNativeOperation"], Value::Null);
    assert_eq!(response["prompt"], "prompt 1");
    assert_eq!(
        response["attachments"],
        json!([{"name":"image.png","path":"/tmp/image.png"}])
    );
    assert_eq!(response["promptItem"]["itemId"], "user-1");
    assert_eq!(response["nativeRollback"], true);
    let terminal = reopened
        .agent_chat_native_operation(&chat, "one")
        .await
        .unwrap()
        .unwrap();
    let wrapper = json!({"snapshot":response["snapshot"],"operation":agent_chat_native_operation_public_summary(&terminal),"result":response});
    assert_eq!(
        reopened
            .check_agent_chat_receipt(
                &reconcile.caller_scope,
                &reconcile.request_id,
                &reconcile.digest
            )
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(wrapper.clone())
    );
    assert_eq!(
        reopened
            .complete_agent_chat_native_rewind(&chat, "one", 0, 0, &json!({}), Some(&reconcile))
            .await
            .unwrap(),
        AgentChatNativeOperationCompleteOutcome::Replay(wrapper)
    );
    assert_eq!(
        original_response(&reopened, "one").await,
        AgentChatReceiptCheck::Replay(response)
    );
    let cancelled: Vec<String> = sqlx::query_scalar("SELECT clientMessageId FROM agentChatCancelledMessages WHERE chatId = ? ORDER BY clientMessageId")
        .bind(&chat).fetch_all(reopened.pool()).await.unwrap();
    assert_eq!(cancelled, vec!["client-1", "client-2"]);
    let mappings: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM agentChatNativeIds WHERE chatId = ?")
            .bind(&chat)
            .fetch_one(reopened.pool())
            .await
            .unwrap();
    assert_eq!(mappings, 0);
    let events = reopened.agent_chat_events(&chat, 0, 10).await.unwrap();
    assert!(events.snapshot_required);
    assert!(events.events.is_empty());
    assert_eq!(events.cursor, 2);
}

#[tokio::test]
async fn failed_receipt_insert_rolls_back_prefix_generation_and_terminal_state_then_ack_can_finish()
{
    let (_dir, store, chat) = fixture().await;
    let op = acknowledge(&store, &begin(&store, &chat, "one", false).await).await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let snapshot = stopped_snapshot(&store, &chat).await;
    force_receipt_failure(&store).await;
    assert!(store
        .complete_agent_chat_native_rewind(&chat, "one", op.revision, 0, &snapshot, None)
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert_eq!(
        store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap(),
        op
    );
    assert_eq!(
        original_response(&store, "one").await,
        AgentChatReceiptCheck::New
    );
    let markers: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM agentChatCancelledMessages WHERE chatId = ?")
            .bind(&chat)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(markers, 0);
    sqlx::query("DROP TRIGGER failNativeReceipt")
        .execute(store.pool())
        .await
        .unwrap();
    let (_, response) = committed(
        store
            .complete_agent_chat_native_rewind(&chat, "one", op.revision, 0, &snapshot, None)
            .await
            .unwrap(),
    );
    assert_eq!(response["nativeRollback"], true);
}

#[tokio::test]
async fn uncertain_conversation_requires_explicit_receipt_backed_fallback_and_clears_context() {
    let (_dir, store, chat) = fixture().await;
    let op = advance(
        &store,
        &begin(&store, &chat, "one", false).await,
        "executing",
        None,
    )
    .await;
    let op = advance(
        &store,
        &op,
        "uncertain",
        Some(&json!({"reason":"providerError"})),
    )
    .await;
    let mut snapshot = stopped_snapshot(&store, &chat).await;
    assert!(store
        .complete_agent_chat_native_rewind(&chat, "one", op.revision, 0, &snapshot, None)
        .await
        .is_err());
    snapshot["nativeOperationReconcile"] = json!({"action":"continueFromTranscript"});
    assert!(store
        .complete_agent_chat_native_rewind(&chat, "one", op.revision, 0, &snapshot, None)
        .await
        .is_err());
    let reconcile = reconcile("human-fallback");
    let (record, response) = committed(
        store
            .complete_agent_chat_native_rewind(
                &chat,
                "one",
                op.revision,
                0,
                &snapshot,
                Some(&reconcile),
            )
            .await
            .unwrap(),
    );
    assert_eq!(record.generation, 2);
    assert_eq!(record.native_thread_id, None);
    assert_eq!(response["state"], "reconciled");
    assert_eq!(response["nativeRollback"], false);
    assert!(record.snapshot.get("nativeOperationReconcile").is_none());
    assert_eq!(
        original_response(&store, "one").await,
        AgentChatReceiptCheck::Replay(response.clone())
    );
    let AgentChatReceiptCheck::Replay(wrapper) = store
        .check_agent_chat_receipt(
            &reconcile.caller_scope,
            &reconcile.request_id,
            &reconcile.digest,
        )
        .await
        .unwrap()
    else {
        panic!("missing atomic reconciliation receipt");
    };
    assert_eq!(wrapper["result"], response);
    assert_eq!(
        wrapper["operation"]["recovery"]["needsReconciliation"],
        false
    );
}

#[tokio::test]
async fn acknowledged_files_preserve_transcript_and_do_not_infer_effects_from_empty_ack() {
    let (dir, store, chat) = fixture().await;
    let op = acknowledge(&store, &begin(&store, &chat, "one", true).await).await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let (record, response) = committed(
        reopened
            .complete_agent_chat_native_files(&chat, "one", op.revision, 0, &json!({}), None)
            .await
            .unwrap(),
    );
    assert_eq!(record.snapshot["items"], before.snapshot["items"]);
    assert_eq!(record.snapshot["turns"], before.snapshot["turns"]);
    assert_eq!(record.snapshot["session"]["status"], "stopped");
    assert_eq!(record.generation, 2);
    assert_eq!(record.native_thread_id.as_deref(), Some("native-thread"));
    assert_eq!(response["filesystemRewindAcknowledged"], true);
    assert_eq!(response["filesystemChangesReverted"], Value::Null);
    assert_eq!(
        original_response(&reopened, "one").await,
        AgentChatReceiptCheck::Replay(response)
    );
}

#[tokio::test]
async fn acknowledged_files_record_only_explicit_observations_and_receipt_failure_is_atomic() {
    let (_dir, store, chat) = fixture().await;
    let op = acknowledge(&store, &begin(&store, &chat, "one", true).await).await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    for invalid in [
        json!({"filesystemChangesReverted":true}),
        json!({"filesChanged":["private-path"]}),
    ] {
        assert!(store
            .complete_agent_chat_native_files(&chat, "one", op.revision, 0, &invalid, None)
            .await
            .is_err());
    }
    let observed =
        json!({"filesystemChangesReverted":true,"observedFileCount":1,"observationId":"one"});
    force_receipt_failure(&store).await;
    assert!(store
        .complete_agent_chat_native_files(&chat, "one", op.revision, 0, &observed, None)
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert_eq!(
        store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap(),
        op
    );
    sqlx::query("DROP TRIGGER failNativeReceipt")
        .execute(store.pool())
        .await
        .unwrap();
    let (_, response) = committed(
        store
            .complete_agent_chat_native_files(&chat, "one", op.revision, 0, &observed, None)
            .await
            .unwrap(),
    );
    assert_eq!(response["filesystemChangesReverted"], true);
}

#[tokio::test]
async fn uncertain_files_need_human_receipt_and_preserve_current_transcript_without_effect_claim() {
    let (_dir, store, chat) = fixture().await;
    let op = advance(
        &store,
        &begin(&store, &chat, "one", true).await,
        "executing",
        None,
    )
    .await;
    let op = advance(
        &store,
        &op,
        "uncertain",
        Some(&json!({"reason":"runtimeRestarted"})),
    )
    .await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let action = json!({"action":"continueFromCurrentFiles"});
    assert!(store
        .complete_agent_chat_native_files(&chat, "one", op.revision, 0, &action, None)
        .await
        .is_err());
    let (record, response) = committed(
        store
            .complete_agent_chat_native_files(
                &chat,
                "one",
                op.revision,
                0,
                &action,
                Some(&reconcile("human-files")),
            )
            .await
            .unwrap(),
    );
    assert_eq!(record.snapshot["items"], before.snapshot["items"]);
    assert_eq!(record.snapshot["turns"], before.snapshot["turns"]);
    assert_eq!(record.native_thread_id, None);
    assert_eq!(record.generation, 2);
    assert_eq!(response["state"], "reconciled");
    assert_eq!(response["filesystemRewindAcknowledged"], false);
    assert_eq!(response["filesystemChangesReverted"], Value::Null);
}

#[tokio::test]
async fn prepared_cancellation_receipt_failure_leaves_intent_prepared() {
    let (_dir, store, chat) = fixture().await;
    let op = begin(&store, &chat, "one", false).await;
    force_receipt_failure(&store).await;
    assert!(store
        .transition_agent_chat_native_operation(&chat, "one", op.revision, "cancelled", None)
        .await
        .is_err());
    assert_eq!(
        store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap(),
        op
    );
    assert_eq!(
        original_response(&store, "one").await,
        AgentChatReceiptCheck::New
    );
}

#[tokio::test]
async fn completion_revision_and_cursor_conflicts_leave_acknowledgment_and_history_intact() {
    let (_dir, store, chat) = fixture().await;
    let op = acknowledge(&store, &begin(&store, &chat, "one", false).await).await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let snapshot = stopped_snapshot(&store, &chat).await;
    assert_eq!(
        store
            .complete_agent_chat_native_rewind(&chat, "one", op.revision - 1, 0, &snapshot, None)
            .await
            .unwrap(),
        AgentChatNativeOperationCompleteOutcome::RevisionConflict {
            current: op.revision
        }
    );
    assert_eq!(
        store
            .complete_agent_chat_native_rewind(&chat, "one", op.revision, 9, &snapshot, None)
            .await
            .unwrap(),
        AgentChatNativeOperationCompleteOutcome::CursorConflict { current: 0 }
    );
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert_eq!(
        store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap(),
        op
    );
}
