use serde_json::json;

use super::agent_chat_test_support::*;
use super::*;

#[tokio::test]
async fn history_pages_cover_every_item_once_within_the_page_budget() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let big = "x".repeat(20 * 1024);
    let items: Vec<_> = (0..40)
        .map(|n| item(&format!("i{n:02}"), "assistant_message", &big))
        .collect();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!(items);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    let window = chat.snapshot["items"].as_array().unwrap();
    assert!(serde_json::to_string(window).unwrap().len() <= AGENT_CHAT_PAGE_MAX_BYTES);
    assert_eq!(window.last().unwrap()["itemId"], "i39");
    let mut seen: Vec<String> = window
        .iter()
        .map(|i| i["itemId"].as_str().unwrap().to_string())
        .collect();
    let mut before = chat.snapshot["historyBefore"].as_i64();
    assert!(before.is_some());
    while let Some(cursor) = before {
        let page = store
            .agent_chat_history(&chat_id, cursor, 100)
            .await
            .unwrap();
        assert!(serde_json::to_string(&page.items).unwrap().len() <= AGENT_CHAT_PAGE_MAX_BYTES);
        let mut ids: Vec<String> = page
            .items
            .iter()
            .map(|i| i["itemId"].as_str().unwrap().to_string())
            .collect();
        ids.append(&mut seen);
        seen = ids;
        before = page.history_before;
    }
    let expected: Vec<String> = (0..40).map(|n| format!("i{n:02}")).collect();
    assert_eq!(seen, expected);
    let short = store
        .agent_chat_history(&chat_id, i64::MAX, 3)
        .await
        .unwrap();
    assert_eq!(short.items.len(), 3);
}

#[tokio::test]
async fn event_pages_follow_the_cursor_and_ask_for_a_snapshot_when_lost() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    for n in 0..5 {
        let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
        next["title"] = json!(format!("Title {n}"));
        store
            .commit_agent_chat(
                &chat_id,
                cursor,
                &next,
                &json!({"title": format!("Title {n}")}),
                None,
            )
            .await
            .unwrap();
    }
    let page = store.agent_chat_events(&chat_id, 1, 2).await.unwrap();
    assert_eq!(
        page.events.iter().map(|e| e.cursor).collect::<Vec<_>>(),
        [2, 3]
    );
    assert_eq!(page.cursor, 3);
    assert!(page.has_more && !page.snapshot_required);
    let rest = store
        .agent_chat_events(&chat_id, page.cursor, 10)
        .await
        .unwrap();
    assert_eq!(rest.events.len(), 2);
    assert!(!rest.has_more);
    assert_eq!(rest.events[1].delta, json!({"title": "Title 4"}));
    assert!(
        store
            .agent_chat_events(&chat_id, 9, 10)
            .await
            .unwrap()
            .snapshot_required
    );
    sqlx::query("DELETE FROM agentChatEvents WHERE chatId = ? AND cursor <= 2")
        .bind(&chat_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(
        store
            .agent_chat_events(&chat_id, 1, 10)
            .await
            .unwrap()
            .snapshot_required
    );
    assert!(
        !store
            .agent_chat_events(&chat_id, 2, 10)
            .await
            .unwrap()
            .snapshot_required
    );
    assert!(store
        .agent_chat_events(&new_chat_id(), 0, 10)
        .await
        .is_err());
}

#[tokio::test]
async fn host_metadata_stays_outside_the_snapshot_and_refuses_credentials() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.metadata, Some(json!({"creationSource": "desktop"})));
    assert!(chat.snapshot.get("creationSource").is_none());
    let linked = json!({"creationSource": "orchestrator", "parentChatId": "p", "taskId": "t"});
    let updated = store
        .set_agent_chat_metadata(&chat_id, Some(&linked))
        .await
        .unwrap();
    assert_eq!((updated.metadata, updated.cursor), (Some(linked), 0));
    assert!(store
        .set_agent_chat_metadata(&chat_id, None)
        .await
        .unwrap()
        .metadata
        .is_none());
    for bad in [
        json!({"mcpServers": [{"url": "x"}]}),
        json!({"launch": {"api_key": "k"}}),
        json!([1]),
    ] {
        assert!(store
            .set_agent_chat_metadata(&chat_id, Some(&bad))
            .await
            .is_err());
    }
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    next["session"]["capabilities"]["Authorization"] = json!("Bearer x");
    assert!(store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"session": next["session"]}),
            None
        )
        .await
        .is_err());
    let leaky = new_chat_id();
    let mut snapshot = snapshot(&leaky, "ws", "tab-2", 0);
    snapshot["launch"] = json!({"env": {"OPENAI_API_KEY": "x"}, "accessToken": "y"});
    assert!(store
        .create_agent_chat(
            &record(&leaky, "ws", "tab-2", snapshot),
            &tab(&leaky, "ws", "tab-2"),
            None
        )
        .await
        .is_err());
    assert!(store.find_workspace_tab("tab-2").await.unwrap().is_none());
}

#[tokio::test]
async fn per_turn_client_metadata_round_trips() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let (cursor, mut next) = next_snapshot(&store, &chat_id).await;
    let turn = json!({
        "turnId": "t1",
        "status": "completed",
        "creationSource": "mobile",
        "metadata": {"clientMessageId": "c1", "parentChatId": "p"},
    });
    next["turns"] = json!([turn]);
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"turns": [turn]}), None)
        .await
        .unwrap();
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.snapshot["turns"][0], turn);
    let events = store.agent_chat_events(&chat_id, 0, 1).await.unwrap();
    assert_eq!(events.events[0].delta["turns"][0], turn);
}
