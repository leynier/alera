use std::sync::Arc;

use serde_json::json;
use tokio::sync::Barrier;
use tokio::task::JoinSet;

use super::agent_chat_test_support::*;
use super::*;

async fn cancelled(store: &RuntimeStore, chat_id: &str, message_id: &str) -> bool {
    store
        .is_agent_chat_message_cancelled(chat_id, message_id)
        .await
        .unwrap()
}

async fn marker_count(store: &RuntimeStore, chat_id: &str) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM agentChatCancelledMessages WHERE chatId = ?")
        .bind(chat_id)
        .fetch_one(store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn cancellation_before_any_send_is_idempotent_and_exactly_scoped() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let other_chat = create_chat(&store, "ws", "other-tab").await;
    assert!(!cancelled(&store, &chat_id, "task-prompt").await);
    assert!(store
        .cancel_agent_chat_message(&chat_id, "task-prompt")
        .await
        .unwrap());
    let first_timestamp: String = sqlx::query_scalar(
        "SELECT cancelledAt FROM agentChatCancelledMessages WHERE chatId = ? AND clientMessageId = ?",
    )
    .bind(&chat_id)
    .bind("task-prompt")
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert!(!store
        .cancel_agent_chat_message(&chat_id, "task-prompt")
        .await
        .unwrap());
    let timestamp: String = sqlx::query_scalar(
        "SELECT cancelledAt FROM agentChatCancelledMessages WHERE chatId = ? AND clientMessageId = ?",
    )
    .bind(&chat_id)
    .bind("task-prompt")
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(timestamp, first_timestamp);
    assert!(cancelled(&store, &chat_id, "task-prompt").await);
    assert!(!cancelled(&store, &chat_id, "Task-prompt").await);
    assert!(!cancelled(&store, &chat_id, "human-prompt").await);
    assert!(!cancelled(&store, &other_chat, "task-prompt").await);
    assert_eq!(marker_count(&store, &chat_id).await, 1);
    assert_eq!(marker_count(&store, &other_chat).await, 0);
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
}

#[tokio::test]
async fn cancelling_preserves_turns_items_and_command_receipts() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    let mut user_item = item("user", "user_message", "completed prompt");
    user_item["clientMessageId"] = json!("completed-message");
    user_item["turnId"] = json!("completed-turn");
    initial["items"] = json!([user_item]);
    initial["turns"] = json!([{"turnId": "completed-turn", "status": "completed"}]);
    let receipt = AgentChatReceipt {
        caller_scope: "runtime".into(),
        request_id: "completed-send".into(),
        digest: "send-digest".into(),
        receipt: json!({"turnId": "completed-turn"}),
    };
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            Some(&receipt),
        )
        .await
        .unwrap();
    let before = store.agent_chat(&chat_id).await.unwrap().unwrap();
    store
        .cancel_agent_chat_message(&chat_id, "completed-message")
        .await
        .unwrap();
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap(), before);
    assert_eq!(
        store
            .check_agent_chat_receipt("runtime", "completed-send", "send-digest")
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(receipt.receipt)
    );
}

#[tokio::test]
async fn cancellation_survives_restart_and_startup_recovery() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    store
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .generation,
        1
    );
    assert!(cancelled(&reopened, &chat_id, "delayed-send").await);
    assert!(!reopened
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap());
    reopened.recover_agent_chats().await.unwrap();
    assert!(cancelled(&reopened, &chat_id, "delayed-send").await);
    assert!(!cancelled(&reopened, &chat_id, "fresh-send").await);
}

#[tokio::test]
async fn archive_reopen_and_provider_switch_keep_cancellation() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    store
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap();
    store.archive_agent_chat(&chat_id).await.unwrap();
    assert!(cancelled(&store, &chat_id, "delayed-send").await);
    assert!(store
        .cancel_agent_chat_message(&chat_id, "cancel-while-archived")
        .await
        .unwrap());
    store
        .restore_agent_chat(&chat_id, &tab(&chat_id, "ws", "restored-tab"))
        .await
        .unwrap();
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["provider"] = json!("claude");
    next["providerInstanceId"] = json!("claude-work");
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"provider": "claude", "providerInstanceId": "claude-work"}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .generation,
        2
    );
    assert!(cancelled(&store, &chat_id, "delayed-send").await);
    assert!(cancelled(&store, &chat_id, "cancel-while-archived").await);
    assert!(!cancelled(&store, &chat_id, "new-generation-send").await);
}

#[tokio::test]
async fn receipt_retention_never_expires_cancellation_markers() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    store
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap();
    let receipt = AgentChatReceipt {
        caller_scope: "runtime".into(),
        request_id: "old-cancel".into(),
        digest: "cancel-digest".into(),
        receipt: json!({"cancelled": true}),
    };
    store
        .record_agent_chat_receipt(Some(&chat_id), &receipt)
        .await
        .unwrap();
    sqlx::query("UPDATE agentChatReceipts SET createdAt = '2000-01-01T00:00:00.000Z'")
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("UPDATE agentChatCancelledMessages SET cancelledAt = '2000-01-01T00:00:00.000Z'")
        .execute(store.pool())
        .await
        .unwrap();
    assert_eq!(
        store
            .check_agent_chat_receipt("runtime", "old-cancel", "cancel-digest")
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert!(cancelled(&store, &chat_id, "delayed-send").await);
    assert_eq!(marker_count(&store, &chat_id).await, 1);
}

#[tokio::test]
async fn missing_chats_and_invalid_ids_never_create_markers() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let missing = new_chat_id();
    for error in [
        store
            .cancel_agent_chat_message(&missing, "message")
            .await
            .unwrap_err(),
        store
            .is_agent_chat_message_cancelled(&missing, "message")
            .await
            .unwrap_err(),
    ] {
        assert_eq!(
            error.downcast_ref::<AgentChatStoreError>(),
            Some(&AgentChatStoreError::NotFound(missing.clone()))
        );
    }
    let too_long = "x".repeat(AGENT_CHAT_ID_MAX_BYTES + 1);
    for bad_message in ["", " message", "message ", too_long.as_str()] {
        for error in [
            store
                .cancel_agent_chat_message(&chat_id, bad_message)
                .await
                .unwrap_err(),
            store
                .is_agent_chat_message_cancelled(&chat_id, bad_message)
                .await
                .unwrap_err(),
        ] {
            assert!(matches!(
                error.downcast_ref(),
                Some(AgentChatStoreError::Invalid(_))
            ));
        }
    }
    for bad_chat in ["", "not-a-chat", "0190f5b2-7c3e-7a00-8000-000000000000"] {
        assert!(store
            .cancel_agent_chat_message(bad_chat, "message")
            .await
            .is_err());
        assert!(store
            .is_agent_chat_message_cancelled(bad_chat, "message")
            .await
            .is_err());
    }
    assert_eq!(marker_count(&store, &chat_id).await, 0);
    assert_eq!(marker_count(&store, &missing).await, 0);
}

#[tokio::test]
async fn concurrent_cancellations_across_connections_insert_once() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let second = RuntimeStore::open(dir.path()).await.unwrap();
    let barrier = Arc::new(Barrier::new(24));
    let mut calls = JoinSet::new();
    for index in 0..24 {
        let store = if index % 2 == 0 {
            store.clone()
        } else {
            second.clone()
        };
        let chat_id = chat_id.clone();
        let barrier = barrier.clone();
        calls.spawn(async move {
            barrier.wait().await;
            store
                .cancel_agent_chat_message(&chat_id, "delayed-send")
                .await
                .unwrap()
        });
    }
    let mut inserted = 0;
    while let Some(result) = calls.join_next().await {
        inserted += usize::from(result.unwrap());
    }
    assert_eq!(inserted, 1);
    assert_eq!(marker_count(&store, &chat_id).await, 1);
    assert!(cancelled(&second, &chat_id, "delayed-send").await);
}

#[tokio::test]
async fn deleting_the_workspace_deletes_only_its_markers() {
    let (_dir, store) = store_with_workspace("ws").await;
    add_workspace(&store, "other").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let other_chat = create_chat(&store, "other", "other-tab").await;
    for chat in [&chat_id, &other_chat] {
        store
            .cancel_agent_chat_message(chat, "delayed-send")
            .await
            .unwrap();
    }
    store.remove_workspace("ws", true).await.unwrap();
    assert_eq!(marker_count(&store, &chat_id).await, 0);
    assert!(cancelled(&store, &other_chat, "delayed-send").await);
    assert!(store
        .cancel_agent_chat_message(&chat_id, "new-send")
        .await
        .is_err());
    assert_eq!(marker_count(&store, &chat_id).await, 0);
}

#[tokio::test]
async fn foreign_key_cascade_removes_markers_without_the_cleanup_trigger() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    store
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap();
    let mut connection = store.pool().acquire().await.unwrap();
    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query("DROP TRIGGER agentChatDeleteChildren")
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
        .bind(&chat_id)
        .execute(&mut *connection)
        .await
        .unwrap();
    drop(connection);
    assert_eq!(marker_count(&store, &chat_id).await, 0);
}

#[tokio::test]
async fn additive_migration_keeps_existing_chats_and_replaces_old_cleanup_trigger() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let before = store.agent_chat(&chat_id).await.unwrap().unwrap();
    // Keep the fixture DDL on one connection so CREATE sees the preceding DROP.
    let mut connection = store.pool().acquire().await.unwrap();
    sqlx::query("DROP TRIGGER agentChatDeleteChildren")
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query("DROP TABLE agentChatCancelledMessages")
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER agentChatDeleteChildren AFTER DELETE ON agentChatSessions BEGIN \
         DELETE FROM agentChatItems WHERE chatId = OLD.chatId; END;",
    )
    .execute(&mut *connection)
    .await
    .unwrap();
    drop(connection);
    store.pool().close().await;
    let migrated = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        migrated.agent_chat(&chat_id).await.unwrap().unwrap(),
        before
    );
    migrated
        .cancel_agent_chat_message(&chat_id, "delayed-send")
        .await
        .unwrap();
    migrated.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert!(cancelled(&reopened, &chat_id, "delayed-send").await);
    let mut connection = reopened.pool().acquire().await.unwrap();
    sqlx::query("PRAGMA foreign_keys = OFF")
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query("DELETE FROM agentChatSessions WHERE chatId = ?")
        .bind(&chat_id)
        .execute(&mut *connection)
        .await
        .unwrap();
    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&mut *connection)
        .await
        .unwrap();
    drop(connection);
    assert_eq!(marker_count(&reopened, &chat_id).await, 0);
}
