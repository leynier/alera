use serde_json::json;

use super::test_support::*;
use crate::runtime::agent_chat_test_support::{item, next_snapshot};
use crate::runtime::*;

#[tokio::test]
async fn intent_is_idempotent_receipt_reserved_and_single_active_per_chat() {
    let (_dir, store, chat) = fixture().await;
    let op = begin(&store, &chat, "one", false).await;
    let retry = store
        .begin_agent_chat_native_operation(&input(&chat, "retry-id", false), &receipt("one"))
        .await
        .unwrap();
    assert_eq!(
        retry,
        AgentChatNativeOperationOutcome::Existing(Box::new(op.clone()))
    );
    assert!(matches!(
        store
            .begin_agent_chat_native_operation(&input(&chat, "two", false), &receipt("two"))
            .await
            .unwrap(),
        AgentChatNativeOperationOutcome::Busy { .. }
    ));
    let mut changed = receipt("one");
    changed.digest = "different".into();
    assert_eq!(
        store
            .begin_agent_chat_native_operation(&input(&chat, "one", false), &changed)
            .await
            .unwrap(),
        AgentChatNativeOperationOutcome::ReceiptConflict
    );
    let original = AgentChatReceipt {
        caller_scope: json!(["desktop", "agentChat.nativeRewind"]).to_string(),
        request_id: "one".into(),
        digest: "one".into(),
        receipt: json!({"premature":true}),
    };
    assert!(store
        .record_agent_chat_receipt(Some(&chat), &original)
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap().cursor, 0);
}

#[tokio::test]
async fn intent_refuses_foreign_epoch_ambiguous_boundary_and_ambiguous_prompt_before_io() {
    let (_dir, store, chat) = fixture().await;
    let mut wrong = input(&chat, "wrong", false);
    wrong.process_epoch = "other".into();
    assert!(store
        .begin_agent_chat_native_operation(&wrong, &receipt("wrong"))
        .await
        .is_err());
    store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: chat.clone(),
            generation: 1,
            kind: "turn@epoch@conflict".into(),
            native_id: json!("different-turn"),
            app_id: Some("turn-1".into()),
        })
        .await
        .unwrap();
    assert!(store
        .begin_agent_chat_native_operation(&input(&chat, "ambiguous", false), &receipt("ambiguous"))
        .await
        .is_err());
    sqlx::query("DELETE FROM agentChatNativeIds WHERE chatId = ? AND kind = 'turn@epoch@conflict'")
        .bind(&chat)
        .execute(store.pool())
        .await
        .unwrap();
    let mut steer = item("steer", "user_message", "additional steering");
    steer["turnId"] = json!("turn-1");
    let json = steer.to_string();
    sqlx::query("INSERT INTO agentChatItems(chatId,itemId,seq,turnId,itemJson,byteSize,updatedCursor) VALUES (?,'steer',100,'turn-1',?,?,0)")
        .bind(&chat).bind(&json).bind(json.len() as i64).execute(store.pool()).await.unwrap();
    assert!(store
        .begin_agent_chat_native_operation(&input(&chat, "steered", false), &receipt("steered"))
        .await
        .unwrap_err()
        .to_string()
        .contains("exactly one user message"));
    assert!(store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn executing_cas_has_one_winner_and_ack_rejects_raw_or_mismatched_evidence() {
    let (dir, store, chat) = fixture().await;
    let op = begin(&store, &chat, "one", false).await;
    let other = RuntimeStore::open(dir.path()).await.unwrap();
    let (one, two) = tokio::join!(
        store.transition_agent_chat_native_operation(&chat, "one", 1, "executing", None),
        other.transition_agent_chat_native_operation(&chat, "one", 1, "executing", None),
    );
    let outcomes = [one.unwrap(), two.unwrap()];
    assert_eq!(
        outcomes
            .iter()
            .filter(|outcome| matches!(outcome, AgentChatNativeOperationOutcome::Applied(_)))
            .count(),
        1
    );
    assert_eq!(
        outcomes
            .iter()
            .filter(|outcome| matches!(
                outcome,
                AgentChatNativeOperationOutcome::RevisionConflict { current: 2 }
            ))
            .count(),
        1
    );
    for ack in [
        json!({"threadId":"foreign","nativeThreadId":"native-thread","boundary":op.boundary}),
        json!({"threadId":"native-thread","nativeThreadId":"native-thread","boundary":op.boundary,"nativeResponse":{"accessToken":"never-persist"}}),
    ] {
        assert!(store
            .transition_agent_chat_native_operation(&chat, "one", 2, "acknowledged", Some(&ack))
            .await
            .is_err());
    }
    assert_eq!(
        store
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap()
            .state,
        "executing"
    );
}

#[tokio::test]
async fn prepared_cancellation_saves_original_receipt_without_changing_chat() {
    let (_dir, store, chat) = fixture().await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let op = begin(&store, &chat, "one", false).await;
    let cancelled = advance(&store, &op, "cancelled", None).await;
    assert_eq!(cancelled.state, "cancelled");
    assert_eq!(cancelled.result.as_ref().unwrap()["nativeRollback"], false);
    assert!(store
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .is_none());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert_eq!(
        store
            .begin_agent_chat_native_operation(&input(&chat, "retry", false), &receipt("one"))
            .await
            .unwrap(),
        AgentChatNativeOperationOutcome::Replay(cancelled.result.unwrap())
    );
}

#[tokio::test]
async fn executing_reopen_is_write_free_and_explicit_recovery_is_uncertain_once() {
    let (dir, store, chat) = fixture().await;
    let op = begin(&store, &chat, "one", false).await;
    advance(&store, &op, "executing", None).await;
    let mut observer = store.pool().acquire().await.unwrap();
    let before: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let after: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    assert_eq!(after, before);
    assert_eq!(
        reopened
            .pending_agent_chat_native_operation(&chat)
            .await
            .unwrap()
            .unwrap()
            .state,
        "executing"
    );
    assert_eq!(
        reopened
            .recover_agent_chat_native_operations()
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        reopened
            .recover_agent_chat_native_operations()
            .await
            .unwrap(),
        0
    );
    let op = reopened
        .pending_agent_chat_native_operation(&chat)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(op.state, "uncertain");
    assert_eq!(op.revision, 3);
    let evidence: String = sqlx::query_scalar(
        "SELECT evidenceJson FROM agentChatNativeOperations WHERE operationId = 'one'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&evidence).unwrap(),
        json!({"reason":"runtimeRestarted"})
    );
    assert!(reopened.recover_agent_chats().await.unwrap().is_empty());
    assert!(reopened
        .transition_agent_chat_native_operation(&chat, "one", 3, "executing", None)
        .await
        .is_err());
}

#[tokio::test]
async fn pending_operation_allows_only_safe_header_publication_and_freezes_closure_and_wakes() {
    let (_dir, store, chat) = fixture().await;
    let op = begin(&store, &chat, "one", false).await;
    let executing = advance(&store, &op, "executing", None).await;
    let (cursor, mut next) = next_snapshot(&store, &chat).await;
    let summary = agent_chat_native_operation_public_summary(&executing);
    next["pendingNativeOperation"] = summary.clone();
    next["session"]["status"] = json!("stopped");
    next["session"]["capabilities"] = json!({});
    store
        .commit_agent_chat(
            &chat,
            cursor,
            &next,
            &json!({"session":next["session"],"pendingNativeOperation":summary}),
            None,
        )
        .await
        .unwrap();
    let (cursor, next) = next_snapshot(&store, &chat).await;
    assert!(store
        .commit_agent_chat(
            &chat,
            cursor,
            &next,
            &json!({"items":[item("sent","user_message","must not send")]}),
            None
        )
        .await
        .is_err());
    assert!(store.archive_agent_chat(&chat).await.is_err());
    assert!(store
        .close_agent_chat_with_receipt(&chat, &reconcile("close"))
        .await
        .is_err());
    assert!(
        sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
            .bind(&chat)
            .execute(store.pool())
            .await
            .is_err()
    );
    assert!(store
        .bind_agent_chat_native_thread(&chat, 1, None)
        .await
        .is_err());
    assert!(store
        .seal_chat_orchestration_wake(&chat)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn pending_recovery_pages_are_bounded_and_unknown_kind_actions_fail_closed() {
    let (_dir, store, chat) = fixture().await;
    let mut op = begin(&store, &chat, "one", false).await;
    let second = seed(&store, "second").await;
    begin(&store, &second, "two", true).await;
    let page = store
        .list_pending_agent_chat_native_operations(None, 1)
        .await
        .unwrap();
    assert_eq!(page.operations.len(), 1);
    assert!(page.next_after.is_some());
    let next = store
        .list_pending_agent_chat_native_operations(page.next_after.as_deref(), 1)
        .await
        .unwrap();
    assert_eq!(next.operations.len(), 1);
    assert!(next.next_after.is_none());
    op.kind = "future-kind".into();
    for state in ["prepared", "acknowledged"] {
        op.state = state.into();
        op.ack = Some(json!({}));
        let summary = agent_chat_native_operation_public_summary(&op);
        assert_eq!(summary["kind"], "unknown");
        assert_eq!(summary["recovery"]["needsReconciliation"], true);
        for action in [
            "canCancelUnstarted",
            "canFinishAcknowledged",
            "canRestartFromTranscript",
            "canContinueFromCurrentFiles",
        ] {
            assert_eq!(summary["recovery"][action], false);
        }
    }
}
