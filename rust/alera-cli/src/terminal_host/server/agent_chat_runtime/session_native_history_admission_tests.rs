use super::*;

use alera_core::runtime::AgentChatReceiptCheck;

use super::super::super::commands::{CallerCtx, ReceiptKey};
use super::super::super::ids::receipt_scope;

#[tokio::test]
async fn unknown_executing_kind_reload_keeps_reads_available_without_writes_or_provider_calls() {
    let (harness, mut session, prepared) = prepared_fixture().await;
    let executing = transition(
        &mut session,
        &prepared,
        "executing",
        json!({"processEpoch":prepared.process_epoch}),
    )
    .await;
    sqlx::query("UPDATE agentChatNativeOperations SET kind = 'future-kind' WHERE operationId = ?")
        .bind(&executing.operation_id)
        .execute(harness.store.pool())
        .await
        .unwrap();
    let before_operation = harness
        .store
        .agent_chat_native_operation(&executing.chat_id, &executing.operation_id)
        .await
        .unwrap()
        .unwrap();
    let before_chat = harness
        .store
        .agent_chat(&executing.chat_id)
        .await
        .unwrap()
        .unwrap();
    for statement in [
        "CREATE TRIGGER reject_native_operation_read_write BEFORE UPDATE ON agentChatNativeOperations BEGIN SELECT RAISE(ABORT, 'read must not change native operations'); END",
        "CREATE TRIGGER reject_chat_read_write BEFORE UPDATE ON agentChatSessions BEGIN SELECT RAISE(ABORT, 'read must not change chats'); END",
    ] {
        sqlx::query(statement)
            .execute(harness.store.pool())
            .await
            .unwrap();
    }
    let reads = tokio::time::timeout(Duration::from_secs(5), async {
        let mut reloaded = ChatSession::load(&executing.chat_id, session.deps.clone())
            .await
            .unwrap();
        assert_ne!(reloaded.process_epoch, executing.process_epoch);
        assert_eq!(reloaded.native_operation.as_ref(), Some(&before_operation));
        assert!(reloaded.is_busy());
        assert!(reloaded.provider.is_none());
        assert!(reloaded.startup.is_none());
        reloaded.load_native_history_recovery().await.unwrap();
        let snapshot = reloaded.snapshot().await.unwrap();
        let history = reloaded
            .history(&format!("seq:{}", i64::MAX), 20)
            .await
            .unwrap();
        let by_id = reloaded
            .native_history_operation_status(Some(&executing.operation_id))
            .await
            .unwrap();
        let pending = reloaded
            .native_history_operation_status(None)
            .await
            .unwrap();
        assert_eq!(by_id, pending);
        assert_eq!(snapshot["pendingNativeOperation"], by_id["operation"]);
        assert_eq!(snapshot["pendingNativeOperation"]["state"], "executing");
        assert_eq!(snapshot["pendingNativeOperation"]["kind"], "unknown");
        assert_eq!(
            snapshot["pendingNativeOperation"]["recovery"]["needsReconciliation"],
            true
        );
        for action in [
            "canCancelUnstarted",
            "canFinishAcknowledged",
            "canRestartFromTranscript",
            "canContinueFromCurrentFiles",
        ] {
            assert_eq!(by_id["operation"]["recovery"][action], false);
        }
        assert_eq!(snapshot["cursor"].as_i64(), Some(before_chat.cursor));
        assert_eq!(history["items"].as_array().unwrap().len(), 2);
        assert_eq!(reloaded.native_operation.as_ref(), Some(&before_operation));
        [snapshot, history, by_id, pending]
    })
    .await
    .unwrap();
    for read in reads {
        let public = read.to_string();
        for private in [
            "future-kind",
            "native-seed-source",
            "native-seed-turn",
            "seed-process",
        ] {
            assert!(!public.contains(private));
        }
    }
    assert_eq!(
        harness
            .store
            .agent_chat_native_operation(&executing.chat_id, &executing.operation_id)
            .await
            .unwrap(),
        Some(before_operation)
    );
    let after_chat = harness
        .store
        .agent_chat(&executing.chat_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(after_chat.snapshot, before_chat.snapshot);
    assert_eq!(after_chat.cursor, before_chat.cursor);
    assert_eq!(after_chat.generation, before_chat.generation);
    assert_eq!(after_chat.native_thread_id, before_chat.native_thread_id);
    assert_eq!(after_chat.updated_at, before_chat.updated_at);
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn unknown_prepared_kind_rejects_forged_cancellation_in_the_actor_and_keeps_the_freeze() {
    let (harness, mut session, prepared) = prepared_fixture().await;
    sqlx::query("UPDATE agentChatNativeOperations SET kind = 'future-kind' WHERE operationId = ?")
        .bind(&prepared.operation_id)
        .execute(harness.store.pool())
        .await
        .unwrap();
    session.load_native_history_recovery().await.unwrap();
    let pending = session.native_operation.clone().unwrap();
    let public = native_operation_public_summary(&pending);
    assert_eq!(public["kind"], "unknown");
    for action in [
        "canCancelUnstarted",
        "canFinishAcknowledged",
        "canRestartFromTranscript",
        "canContinueFromCurrentFiles",
    ] {
        assert_eq!(public["recovery"][action], false);
    }
    let header = session.header.clone();
    let committed = session.committed.clone();
    let before = harness
        .store
        .agent_chat(&prepared.chat_id)
        .await
        .unwrap()
        .unwrap();
    let key = ReceiptKey {
        verb: "agentChat.nativeHistory.reconcile".into(),
        request_id: "forged-future-cancel".into(),
        digest: "forged-cancel-digest".into(),
    };
    let error = session
        .reconcile_native_history(
            &pending.operation_id,
            Some(pending.revision),
            "cancelUnstarted",
            &CallerCtx::runtime(),
            Some(&key),
        )
        .await
        .unwrap_err();
    assert!(matches!(error, HostError::Conflict {code, ..} if code == "nativeOperationPending"));
    assert_eq!(session.native_operation.as_ref(), Some(&pending));
    assert_eq!(session.header, header);
    assert_eq!(session.committed, committed);
    let after = harness
        .store
        .agent_chat(&prepared.chat_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(after.snapshot, before.snapshot);
    assert_eq!(after.cursor, before.cursor);
    assert_eq!(after.generation, before.generation);
    assert_eq!(after.native_thread_id, before.native_thread_id);
    assert_eq!(
        harness
            .store
            .pending_agent_chat_native_operation(&prepared.chat_id)
            .await
            .unwrap(),
        Some(pending)
    );
    assert_eq!(
        harness
            .store
            .check_agent_chat_receipt(
                &receipt_scope("runtime", &key.verb),
                &key.request_id,
                &key.digest
            )
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}
