use serde_json::json;

use super::super::agent_chat_test_support::*;
use super::super::*;

#[tokio::test]
async fn an_unselected_draft_serializes_null_and_can_select_a_real_instance_after_reopen() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = new_chat_id();
    let mut initial = snapshot(&id, "ws", "tab", 0);
    initial["provider"] = json!(null);
    initial["providerInstanceId"] = json!(null);
    initial["session"]["status"] = json!("stopped");
    initial["session"]["model"] = json!(null);
    initial["session"]["capabilities"] = json!({});
    let mut record = record(&id, "ws", "tab", initial);
    record.native_thread_id = None;
    record.provider = AGENT_CHAT_UNSELECTED_PROVIDER.into();
    record.provider_instance_id = AGENT_CHAT_UNSELECTED_PROVIDER.into();
    let mut tab = tab(&id, "ws", "tab");
    tab.payload["provider"] = json!(null);
    tab.payload["providerInstanceId"] = json!(null);
    store.create_agent_chat(&record, &tab, None).await.unwrap();
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["session"]["capabilities"] = json!({"steer": false, "fork": false});
    sqlx::query(
        "CREATE TRIGGER rejectUnselectedTabRewrite BEFORE UPDATE OF payloadJson ON workspaceTabs \
        BEGIN SELECT RAISE(ABORT, 'unchanged unselected payload'); END",
    )
    .execute(store.pool())
    .await
    .unwrap();
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None,
        )
        .await
        .unwrap();
    let payload = store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap()
        .payload;
    assert_eq!(payload.get("provider"), Some(&json!(null)));
    assert_eq!(payload.get("providerInstanceId"), Some(&json!(null)));
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
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .payload,
        payload
    );
    sqlx::query("DROP TRIGGER rejectUnselectedTabRewrite")
        .execute(store.pool())
        .await
        .unwrap();
    let stored = reopened.agent_chat(&id).await.unwrap().unwrap();
    assert_eq!(stored.provider, AGENT_CHAT_UNSELECTED_PROVIDER);
    assert!(stored.snapshot["provider"].is_null());
    assert!(stored.snapshot["providerInstanceId"].is_null());
    assert!(reopened
        .bind_agent_chat_native_thread(&id, 1, Some("native"))
        .await
        .is_err());
    assert!(reopened
        .map_agent_chat_native_id(&AgentChatNativeIdInput {
            chat_id: id.clone(),
            generation: 1,
            kind: "thread".into(),
            native_id: json!("native"),
            app_id: None
        })
        .await
        .is_err());
    let (cursor, mut next) = next_snapshot(&reopened, &id).await;
    assert!(reopened
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"items": [item("sent", "user_message", "blocked")]}),
            None
        )
        .await
        .is_err());
    next["provider"] = json!("codex");
    next["providerInstanceId"] = json!("codex-default");
    reopened
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"provider": "codex", "providerInstanceId": "codex-default"}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        reopened.agent_chat(&id).await.unwrap().unwrap().provider,
        "codex"
    );
    assert_eq!(
        reopened
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .payload["providerInstanceId"],
        "codex-default"
    );
}

#[tokio::test]
async fn an_unselected_create_with_a_native_thread_or_history_is_rejected() {
    let (_dir, store) = store_with_workspace("ws").await;
    let id = new_chat_id();
    let mut initial = snapshot(&id, "ws", "tab", 0);
    initial["provider"] = json!(null);
    initial["providerInstanceId"] = json!(null);
    initial["session"]["status"] = json!("stopped");
    initial["session"]["model"] = json!(null);
    let mut record = record(&id, "ws", "tab", initial);
    record.provider = AGENT_CHAT_UNSELECTED_PROVIDER.into();
    record.provider_instance_id = AGENT_CHAT_UNSELECTED_PROVIDER.into();
    let mut tab = tab(&id, "ws", "tab");
    tab.payload["provider"] = json!(null);
    tab.payload["providerInstanceId"] = json!(null);
    assert!(store.create_agent_chat(&record, &tab, None).await.is_err());
    record.native_thread_id = None;
    record.snapshot["items"] = json!([item("item", "user_message", "cannot send")]);
    assert!(store.create_agent_chat(&record, &tab, None).await.is_err());
    assert!(store.find_workspace_tab("tab").await.unwrap().is_none());
}

#[tokio::test]
async fn selected_provider_payloads_keep_ids_and_explicit_model_reset_removes_only_model() {
    let (dir, store) = store_with_workspace("ws").await;
    let id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["session"]["model"] = json!("selected-model");
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None,
        )
        .await
        .unwrap();
    let payload = store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap()
        .payload;
    assert_eq!(payload["provider"], "codex");
    assert_eq!(payload["providerInstanceId"], "codex-default");
    assert_eq!(payload["model"], "selected-model");
    sqlx::query(
        "CREATE TRIGGER rejectSelectedTabRewrite BEFORE UPDATE OF payloadJson ON workspaceTabs \
        BEGIN SELECT RAISE(ABORT, 'unchanged selected payload'); END",
    )
    .execute(store.pool())
    .await
    .unwrap();
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["session"]["capabilities"] = json!({"steer": false});
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .payload,
        payload
    );
    sqlx::query("DROP TRIGGER rejectSelectedTabRewrite")
        .execute(store.pool())
        .await
        .unwrap();
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["session"]["model"] = json!(null);
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None,
        )
        .await
        .unwrap();
    let payload = store
        .find_workspace_tab("tab")
        .await
        .unwrap()
        .unwrap()
        .payload;
    assert_eq!(payload["provider"], "codex");
    assert_eq!(payload["providerInstanceId"], "codex-default");
    assert!(!payload.as_object().unwrap().contains_key("model"));
    sqlx::query("CREATE TRIGGER rejectDefaultModelTabRewrite BEFORE UPDATE OF payloadJson ON workspaceTabs \
        BEGIN SELECT RAISE(ABORT, 'unchanged default-model payload'); END")
        .execute(store.pool()).await.unwrap();
    let (cursor, mut next) = next_snapshot(&store, &id).await;
    next["session"]["capabilities"] = json!({"steer": true});
    store
        .commit_agent_chat(
            &id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .payload,
        payload
    );
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
            .find_workspace_tab("tab")
            .await
            .unwrap()
            .unwrap()
            .payload,
        payload
    );
}
