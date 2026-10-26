use serde_json::json;

use super::super::agent_chat_test_support::*;
use super::super::*;

async fn count(store: &RuntimeStore, table: &str, chat_id: &str) -> i64 {
    sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT COUNT(*) FROM {table} WHERE chatId = ?"
    )))
    .bind(chat_id)
    .fetch_one(store.pool())
    .await
    .unwrap()
}

#[tokio::test]
async fn create_writes_tab_session_and_initial_items_together() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!([
        item("a", "user_message", "hello"),
        item("b", "assistant_message", "hi")
    ]);
    let outcome = store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let AgentChatCreateOutcome::Created(created) = outcome else {
        panic!("expected a new chat");
    };
    assert_eq!(created.generation, 1);
    assert_eq!(created.cursor, 0);
    assert_eq!(created.native_thread_id.as_deref(), Some("native-thread"));
    assert!(created.snapshot.get("nativeThreadId").is_none());
    let items = created.snapshot["items"].as_array().unwrap();
    assert_eq!(
        items
            .iter()
            .map(|i| i["itemId"].as_str().unwrap())
            .collect::<Vec<_>>(),
        ["a", "b"]
    );
    assert_eq!(items[0]["normalized"], json!({}));
    assert!(created.snapshot.get("historyBefore").is_none());
    let stored_tab = store.find_workspace_tab("tab").await.unwrap().unwrap();
    assert_eq!(stored_tab.kind, AGENT_CHAT_TAB_KIND);
    assert_eq!(
        store
            .agent_chat_for_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .chat_id,
        chat_id
    );
}

#[tokio::test]
async fn create_rejects_bad_identity_without_writing_anything() {
    let (_dir, store) = store_with_workspace("ws").await;
    let upper = new_chat_id().to_uppercase();
    let v7ish = "0190f5b2-7c3e-7a00-8000-000000000000".to_string();
    for chat_id in [upper, v7ish, String::new()] {
        let result = store
            .create_agent_chat(
                &record(&chat_id, "ws", "tab", snapshot(&chat_id, "ws", "tab", 0)),
                &tab(&chat_id, "ws", "tab"),
                None,
            )
            .await;
        assert!(result.is_err(), "{chat_id} must be refused");
    }
    let chat_id = new_chat_id();
    let mut wrong_tab = tab(&chat_id, "ws", "tab");
    wrong_tab.payload["provider"] = json!("claude");
    assert!(store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", snapshot(&chat_id, "ws", "tab", 0)),
            &wrong_tab,
            None
        )
        .await
        .is_err());
    let missing_workspace = new_chat_id();
    assert!(store
        .create_agent_chat(
            &record(
                &missing_workspace,
                "gone",
                "tab",
                snapshot(&missing_workspace, "gone", "tab", 0)
            ),
            &tab(&missing_workspace, "gone", "tab"),
            None,
        )
        .await
        .is_err());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
    assert!(store.list_agent_chats("ws", true).await.unwrap().is_empty());
}

#[tokio::test]
async fn create_rolls_back_when_the_tab_already_exists() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut existing = tab(&chat_id, "ws", "tab");
    existing.kind = "terminal".into();
    store.insert_workspace_tab(existing).await.unwrap();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!([item("a", "user_message", "hello")]);
    let error = store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref(),
        Some(AgentChatStoreError::AlreadyExists(_))
    ));
    assert!(store.agent_chat(&chat_id).await.unwrap().is_none());
    assert_eq!(count(&store, "agentChatItems", &chat_id).await, 0);
    assert_eq!(
        store.find_workspace_tab("tab").await.unwrap().unwrap().kind,
        "terminal"
    );
}

#[tokio::test]
async fn create_receipt_replays_an_exact_retry_and_refuses_a_different_payload() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let digest = agent_chat_command_digest(&json!({"b": 1, "a": [1, 2]}));
    assert_eq!(
        digest,
        agent_chat_command_digest(&json!({"a": [1, 2], "b": 1}))
    );
    let receipt = AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: "req-1".into(),
        digest: digest.clone(),
        receipt: json!({"chatId": chat_id}),
    };
    let chat = record(&chat_id, "ws", "tab", snapshot(&chat_id, "ws", "tab", 0));
    let created = store
        .create_agent_chat(&chat, &tab(&chat_id, "ws", "tab"), Some(&receipt))
        .await
        .unwrap();
    assert!(matches!(created, AgentChatCreateOutcome::Created(_)));
    let replay = store
        .create_agent_chat(&chat, &tab(&chat_id, "ws", "tab"), Some(&receipt))
        .await
        .unwrap();
    assert_eq!(
        replay,
        AgentChatCreateOutcome::Replay(json!({"chatId": chat_id}))
    );

    let other_id = new_chat_id();
    let other = record(
        &other_id,
        "ws",
        "tab-2",
        snapshot(&other_id, "ws", "tab-2", 0),
    );
    let conflicting = AgentChatReceipt {
        digest: agent_chat_command_digest(&json!({"other": true})),
        ..receipt.clone()
    };
    let conflict = store
        .create_agent_chat(&other, &tab(&other_id, "ws", "tab-2"), Some(&conflicting))
        .await
        .unwrap();
    assert_eq!(conflict, AgentChatCreateOutcome::ReceiptConflict);
    assert!(store.agent_chat(&other_id).await.unwrap().is_none());
    assert!(store.find_workspace_tab("tab-2").await.unwrap().is_none());
    // A different caller may reuse the request id.
    let foreign = AgentChatReceipt {
        caller_scope: "mobile:phone".into(),
        ..conflicting
    };
    let created = store
        .create_agent_chat(&other, &tab(&other_id, "ws", "tab-2"), Some(&foreign))
        .await
        .unwrap();
    assert!(matches!(created, AgentChatCreateOutcome::Created(_)));
}

#[tokio::test]
async fn removing_the_tab_archives_the_chat_and_keeps_its_transcript() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!([item("a", "user_message", "keep me")]);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    store.remove_workspace_tab("tab").await.unwrap();
    let archived = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert!(archived.archived);
    assert!(archived.archived_at.is_some());
    assert_eq!(archived.snapshot["items"][0]["text"], "keep me");
    assert!(store.agent_chat_for_tab("tab").await.unwrap().is_none());
    assert!(store
        .list_agent_chats("ws", false)
        .await
        .unwrap()
        .is_empty());
    let listed = store.list_agent_chats("ws", true).await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].snapshot["items"], json!([]));

    // Clearing every tab of a workspace archives as well.
    let second = create_chat(&store, "ws", "tab-2").await;
    store.remove_workspace_tabs("ws").await.unwrap();
    assert!(store.agent_chat(&second).await.unwrap().unwrap().archived);
}

#[tokio::test]
async fn archive_closes_the_tab_and_restore_reopens_in_a_new_one() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let archived = store.archive_agent_chat(&chat_id).await.unwrap();
    assert!(archived.archived);
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
    assert_eq!(store.archive_agent_chat(&chat_id).await.unwrap().cursor, 0);

    let restored = store
        .restore_agent_chat(&chat_id, &tab(&chat_id, "ws", "tab-new"))
        .await
        .unwrap();
    assert!(!restored.archived);
    assert_eq!(restored.tab_id, "tab-new");
    assert_eq!(restored.snapshot["tabId"], "tab-new");
    assert_eq!(restored.cursor, 1);
    let page = store.agent_chat_events(&chat_id, 0, 10).await.unwrap();
    assert_eq!(
        page.events[0].delta,
        json!({"tabId": "tab-new", "archived": false})
    );
    assert!(store
        .restore_agent_chat(&chat_id, &tab(&chat_id, "ws", "tab-3"))
        .await
        .is_err());
    // A restore into another workspace is refused.
    store.archive_agent_chat(&chat_id).await.unwrap();
    add_workspace(&store, "other").await;
    assert!(store
        .restore_agent_chat(&chat_id, &tab(&chat_id, "other", "tab-4"))
        .await
        .is_err());
    assert!(store.find_workspace_tab("tab-4").await.unwrap().is_none());
}

#[tokio::test]
async fn deleting_the_workspace_deletes_its_chats_and_their_rows() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!([item("a", "user_message", "hello")]);
    let receipt = AgentChatReceipt {
        caller_scope: "desktop".into(),
        request_id: "create".into(),
        digest: "d".into(),
        receipt: json!({}),
    };
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            Some(&receipt),
        )
        .await
        .unwrap();
    store
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: chat_id.clone(),
            generation: 1,
            kind: "turn".into(),
            native_id: json!("t1"),
            app_id: None,
        })
        .await
        .unwrap();
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .unwrap();
    store.remove_workspace("ws", true).await.unwrap();
    assert!(store.agent_chat(&chat_id).await.unwrap().is_none());
    for table in [
        "agentChatItems",
        "agentChatEvents",
        "agentChatNativeIds",
        "agentChatReceipts",
    ] {
        assert_eq!(count(&store, table, &chat_id).await, 0, "{table}");
    }
}

#[tokio::test]
async fn a_tab_moved_to_another_workspace_takes_its_chat_along() {
    let (_dir, store) = store_with_workspace("child").await;
    add_workspace(&store, "main").await;
    let chat_id = create_chat(&store, "child", "tab").await;
    sqlx::query("UPDATE workspaceTabs SET workspaceId = 'main' WHERE id = 'tab'")
        .execute(store.pool())
        .await
        .unwrap();
    store.remove_workspace("child", false).await.unwrap();
    let moved = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(moved.workspace_id, "main");
    assert_eq!(moved.snapshot["workspaceId"], "main");
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({}), None)
        .await
        .is_ok());
}

#[tokio::test]
async fn chats_survive_reopening_the_runtime_store() {
    let dir = tempfile::tempdir().unwrap();
    let chat_id = {
        let store = RuntimeStore::open(dir.path()).await.unwrap();
        add_workspace(&store, "ws").await;
        let chat_id = create_chat(&store, "ws", "tab").await;
        let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
        next["title"] = json!("Persisted");
        store
            .commit_agent_chat(
                &chat_id,
                cursor,
                &next,
                &json!({"title": "Persisted", "items": [item("a", "user_message", "durable")]}),
                None,
            )
            .await
            .unwrap();
        store.pool().close().await;
        chat_id
    };
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let chat = reopened.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.cursor, 1);
    assert_eq!(chat.snapshot["title"], "Persisted");
    assert_eq!(chat.snapshot["items"][0]["text"], "durable");
    assert_eq!(
        reopened
            .agent_chat_events(&chat_id, 0, 10)
            .await
            .unwrap()
            .events
            .len(),
        1
    );
}
