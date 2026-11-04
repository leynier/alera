use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::*;

fn receipt(request_id: &str, payload: Value) -> AgentChatReceipt {
    AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: request_id.into(),
        digest: agent_chat_command_digest(&payload),
        receipt: json!({"accepted": request_id}),
    }
}

#[tokio::test]
async fn native_ids_keep_their_json_type() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let input = |native_id: Value, app_id: Option<&str>| AgentChatNativeIdInput {
        chat_id: chat_id.clone(),
        generation: 1,
        kind: "request".into(),
        native_id,
        app_id: app_id.map(str::to_string),
    };
    let integer = store
        .map_agent_chat_native_id(&input(json!(1), None))
        .await
        .unwrap();
    let string = store
        .map_agent_chat_native_id(&input(json!("1"), None))
        .await
        .unwrap();
    assert_ne!(integer, string);
    assert_eq!(
        store
            .map_agent_chat_native_id(&input(json!(1), None))
            .await
            .unwrap(),
        integer
    );
    assert_eq!(
        store
            .agent_chat_app_id(&chat_id, 1, "request", &json!("1"))
            .await
            .unwrap(),
        Some(string.clone())
    );
    assert_eq!(
        store
            .agent_chat_native_id(&chat_id, "request", &integer)
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!(1)
    );
    assert_eq!(
        store
            .agent_chat_native_id(&chat_id, "request", &string)
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!("1")
    );
    // Adopting an app id another native id holds, or re-pointing one, conflicts.
    assert!(store
        .map_agent_chat_native_id(&input(json!(2), Some(&integer)))
        .await
        .is_err());
    assert!(store
        .map_agent_chat_native_id(&input(json!(1), Some("other")))
        .await
        .is_err());
    for bad in [json!(1.5), json!(null), json!({"id": 1}), json!("")] {
        assert!(store
            .map_agent_chat_native_id(&input(bad, None))
            .await
            .is_err());
    }
}

#[tokio::test]
async fn standalone_receipts_replay_and_conflict() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let interrupt = receipt("interrupt-1", json!({"turnId": "t1"}));
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &interrupt)
            .await
            .unwrap(),
        AgentChatReceiptCheck::New
    );
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &interrupt)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Replay(json!({"accepted": "interrupt-1"}))
    );
    let other = receipt("interrupt-1", json!({"turnId": "t2"}));
    assert_eq!(
        store
            .record_agent_chat_receipt(Some(&chat_id), &other)
            .await
            .unwrap(),
        AgentChatReceiptCheck::Conflict
    );
    assert!(store
        .record_agent_chat_receipt(Some(&new_chat_id()), &receipt("x", json!(0)))
        .await
        .is_err());
}

async fn map_boundary(
    store: &RuntimeStore,
    chat_id: &str,
    generation: i64,
    kind: &str,
    native_id: &str,
    app_id: &str,
) {
    store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: chat_id.into(),
            generation,
            kind: kind.into(),
            native_id: json!(native_id),
            app_id: Some(app_id.into()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn changing_a_native_thread_invalidates_only_its_generation_and_keeps_raw_history() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat = create_chat(&store, "ws", "tab").await;
    let other_chat = create_chat(&store, "ws", "other-tab").await;
    map_boundary(
        &store,
        &chat,
        1,
        "turn@1",
        "historical-native",
        "historical",
    )
    .await;
    map_boundary(&store, &other_chat, 1, "turn@1", "other-native", "other").await;
    let (cursor, mut next) = next_snapshot(&store, &chat).await;
    next["provider"] = json!("claudeAgent");
    next["providerInstanceId"] = json!("claude-default");
    let mut raw_item = item("history-item", "assistant_message", "preserve this");
    raw_item["data"] = json!({"rawProviderTurnId": "historical-native"});
    store.commit_agent_chat(&chat, cursor, &next, &json!({
        "provider": "claudeAgent", "providerInstanceId": "claude-default", "items": [raw_item],
    }), None).await.unwrap();
    store
        .bind_agent_chat_native_thread(&chat, 2, Some("thread-two"))
        .await
        .unwrap();
    for (kind, app) in [
        ("turn@2", "current-turn"),
        ("item@2", "current-item"),
        ("request", "current-request"),
    ] {
        map_boundary(&store, &chat, 2, kind, "current-native", app).await;
    }
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    store
        .bind_agent_chat_native_thread(&chat, 2, Some("replacement-thread"))
        .await
        .unwrap();
    let after = store.agent_chat(&chat).await.unwrap().unwrap();
    assert_eq!(
        after.native_thread_id.as_deref(),
        Some("replacement-thread")
    );
    assert_eq!(after.snapshot, before.snapshot);
    assert_eq!(after.metadata, before.metadata);
    assert_eq!(after.generation, before.generation);
    assert_eq!(after.cursor, before.cursor);
    assert_eq!(
        store.agent_chat_item(&chat, "history-item").await.unwrap(),
        Some(raw_item)
    );
    for (prefix, app) in [("turn", "current-turn"), ("item", "current-item")] {
        assert!(store
            .agent_chat_native_id_for_app(&chat, 2, prefix, app)
            .await
            .unwrap()
            .is_none());
    }
    assert!(store
        .agent_chat_native_id(&chat, "request", "current-request")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        store
            .agent_chat_native_id(&chat, "turn@1", "historical")
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!("historical-native")
    );
    assert_eq!(
        store
            .agent_chat_native_id_for_app(&other_chat, 1, "turn", "other")
            .await
            .unwrap()
            .unwrap()
            .native_id,
        json!("other-native")
    );
}

#[tokio::test]
async fn clearing_and_first_binding_invalidate_mappings_but_unchanged_threads_write_nothing() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat = create_chat(&store, "ws", "tab").await;
    map_boundary(&store, &chat, 1, "turn@1", "old-native", "old").await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    let mut observer = store.pool().acquire().await.unwrap();
    let version: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    store
        .bind_agent_chat_native_thread(&chat, 1, Some("native-thread"))
        .await
        .unwrap();
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    let unchanged: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    assert_eq!(unchanged, version);
    assert!(store
        .agent_chat_native_id_for_app(&chat, 1, "turn", "old")
        .await
        .unwrap()
        .is_some());
    store
        .bind_agent_chat_native_thread(&chat, 1, None)
        .await
        .unwrap();
    assert!(store
        .agent_chat_native_id_for_app(&chat, 1, "turn", "old")
        .await
        .unwrap()
        .is_none());
    map_boundary(&store, &chat, 1, "turn@2", "pending-native", "pending").await;
    let cleared = store.agent_chat(&chat).await.unwrap().unwrap();
    let version: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    store
        .bind_agent_chat_native_thread(&chat, 1, None)
        .await
        .unwrap();
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), cleared);
    let unchanged: i64 = sqlx::query_scalar("PRAGMA data_version")
        .fetch_one(&mut *observer)
        .await
        .unwrap();
    assert_eq!(unchanged, version);
    assert!(store
        .agent_chat_app_id(&chat, 1, "turn@2", &json!("pending-native"))
        .await
        .unwrap()
        .is_some());
    store
        .bind_agent_chat_native_thread(&chat, 1, Some("first-fresh-thread"))
        .await
        .unwrap();
    assert!(store
        .agent_chat_native_id_for_app(&chat, 1, "turn", "pending")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn stale_or_failed_native_thread_binding_leaves_mappings_and_thread_unchanged() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat = create_chat(&store, "ws", "tab").await;
    map_boundary(&store, &chat, 1, "turn@1", "native", "boundary").await;
    let before = store.agent_chat(&chat).await.unwrap().unwrap();
    assert!(store
        .bind_agent_chat_native_thread(&chat, 2, Some("stale"))
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert!(store
        .agent_chat_native_id_for_app(&chat, 1, "turn", "boundary")
        .await
        .unwrap()
        .is_some());
    sqlx::query("CREATE TRIGGER rejectNativeBinding BEFORE UPDATE OF nativeThreadId ON agentChatSessions \
        WHEN NEW.nativeThreadId = 'rejected' BEGIN SELECT RAISE(ABORT, 'reject native binding'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .bind_agent_chat_native_thread(&chat, 1, Some("rejected"))
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat).await.unwrap().unwrap(), before);
    assert!(store
        .agent_chat_native_id_for_app(&chat, 1, "turn", "boundary")
        .await
        .unwrap()
        .is_some());
}
