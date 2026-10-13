use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::*;

#[tokio::test]
async fn header_turn_migration_is_idempotent_and_retains_oversized_unknown_metadata() {
    let (dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let old_turn = json!({
        "turnId": "old", "status": "completed", "model": null,
        "provider": "codex", "generation": 1,
        "reason": "retained", "future": "x".repeat(100 * 1024),
    });
    let mut legacy = snapshot(&chat_id, "ws", "tab", 0);
    legacy["turns"] = json!([old_turn]);
    sqlx::query("UPDATE agentChatSessions SET snapshotJson = ? WHERE chatId = ?")
        .bind(serde_json::to_string(&legacy).unwrap())
        .bind(&chat_id)
        .execute(store.pool())
        .await
        .unwrap();
    store.migrate_agent_chats().await.unwrap();
    store.migrate_agent_chats().await.unwrap();
    assert_eq!(
        store.agent_chat_turn(&chat_id, "old").await.unwrap(),
        Some(old_turn.clone())
    );
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM agentChatTurns WHERE chatId = ?")
        .bind(&chat_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 1);
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"turns": [old_turn]}), None)
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        reopened.agent_chat_turn(&chat_id, "old").await.unwrap(),
        Some(old_turn)
    );
    assert_eq!(
        reopened.agent_chat(&chat_id).await.unwrap().unwrap().cursor,
        1
    );
}

#[tokio::test]
async fn header_turn_migration_rolls_back_every_header_if_a_row_is_invalid() {
    let (_dir, store) = store_with_workspace("ws").await;
    let a = create_chat(&store, "ws", "a").await;
    let b = create_chat(&store, "ws", "b").await;
    for (id, tab_id, turn) in [
        (&a, "a", json!({"turnId": "good", "status": "completed"})),
        (&b, "b", json!({"turnId": "bad", "status": 7})),
    ] {
        let mut legacy = snapshot(id, "ws", tab_id, 0);
        legacy["turns"] = json!([turn]);
        sqlx::query("UPDATE agentChatSessions SET snapshotJson = ? WHERE chatId = ?")
            .bind(serde_json::to_string(&legacy).unwrap())
            .bind(id)
            .execute(store.pool())
            .await
            .unwrap();
    }
    assert!(store.migrate_agent_chats().await.is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM agentChatTurns")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
    let header: String =
        sqlx::query_scalar("SELECT snapshotJson FROM agentChatSessions WHERE chatId = ?")
            .bind(&a)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&header).unwrap()["turns"][0]["turnId"],
        "good"
    );
}

#[tokio::test]
async fn turn_rows_roll_back_with_invalid_items_and_command_receipts() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    let receipt = AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: "turn".into(),
        digest: "d".into(),
        receipt: json!({"accepted": true}),
    };
    let mut bad = item("bad", "assistant_message", "x");
    bad["type"] = json!("Invalid Type");
    assert!(store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"turns": [{"turnId": "new", "status": "completed"}], "items": [bad]}),
            Some(&receipt)
        )
        .await
        .is_err());
    assert!(store
        .agent_chat_turn(&chat_id, "new")
        .await
        .unwrap()
        .is_none());
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
    assert!(store
        .agent_chat_events(&chat_id, 0, 10)
        .await
        .unwrap()
        .events
        .is_empty());
    assert_eq!(
        store
            .check_agent_chat_receipt("desktop", "turn", "d")
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
}

#[tokio::test]
async fn turn_row_limits_and_duplicate_delta_entries_fail_without_advancing() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    let oversized = json!({"turnId": "big", "status": "completed", "future": "x".repeat(AGENT_CHAT_TURN_MAX_BYTES)});
    let repeated = json!({"turnId": "twice", "status": "completed"});
    for delta in [
        json!({"turns": [oversized]}),
        json!({"turns": [repeated, repeated]}),
    ] {
        assert!(store
            .commit_agent_chat(&chat_id, cursor, &next, &delta, None)
            .await
            .is_err());
    }
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 0);
}

#[tokio::test]
async fn migrated_large_running_turns_can_settle_without_trimming_metadata() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let old_turn =
        json!({"turnId": "large", "status": "running", "future": "x".repeat(100 * 1024)});
    let mut legacy = snapshot(&chat_id, "ws", "tab", 0);
    legacy["turns"] = json!([old_turn]);
    legacy["session"]["activeTurnId"] = json!("large");
    legacy["session"]["status"] = json!("running");
    sqlx::query("UPDATE agentChatSessions SET snapshotJson = ? WHERE chatId = ?")
        .bind(serde_json::to_string(&legacy).unwrap())
        .bind(&chat_id)
        .execute(store.pool())
        .await
        .unwrap();
    store.migrate_agent_chats().await.unwrap();
    let recovered = store.recover_agent_chats().await.unwrap();
    assert_eq!(recovered[0].interrupted_turn_ids, ["large"]);
    let settled = store
        .agent_chat_turn(&chat_id, "large")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(settled["status"], "interrupted");
    assert_eq!(settled["future"], old_turn["future"]);
}
