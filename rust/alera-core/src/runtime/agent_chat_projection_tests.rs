use std::collections::BTreeSet;

use serde_json::json;

use super::super::agent_chat_test_support::*;
use super::super::*;

#[tokio::test]
async fn large_turn_metadata_reduces_item_windows_without_losing_page_metadata() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let turns: Vec<_> = (0..20)
        .map(|n| {
            json!({
                "turnId": format!("t{n}"), "status": "completed", "unknown": "x".repeat(60 * 1024),
            })
        })
        .collect();
    let items: Vec<_> = (0..20)
        .map(|n| {
            let mut value = item(&format!("i{n}"), "assistant_message", "x");
            value["turnId"] = json!(format!("t{n}"));
            value
        })
        .collect();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!(items);
    initial["turns"] = json!(turns);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    assert_eq!(view["items"].as_array().unwrap().len(), 4);
    assert_eq!(view["turns"].as_array().unwrap().len(), 4);
    assert!(serde_json::to_string(&view).unwrap().len() < 1024 * 1024);
    let mut seen = BTreeSet::new();
    let mut before = Some(i64::MAX);
    while let Some(cursor) = before {
        let page = store
            .agent_chat_history(&chat_id, cursor, 200)
            .await
            .unwrap();
        assert!(serde_json::to_string(&page).unwrap().len() < AGENT_CHAT_PAGE_MAX_BYTES);
        for value in page.turns {
            assert_eq!(value["unknown"].as_str().unwrap().len(), 60 * 1024);
            assert!(seen.insert(value["turnId"].as_str().unwrap().to_string()));
        }
        before = page.history_before;
    }
    assert_eq!(seen.len(), 20);
}

#[tokio::test]
async fn a_large_first_item_keeps_its_complete_turn_metadata_on_every_read() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let turn = json!({"turnId": "large", "status": "completed", "unknown": "x".repeat(63 * 1024)});
    let mut value = item("large", "assistant_message", &"y".repeat(255 * 1024));
    value["turnId"] = json!("large");
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["items"] = json!([value]);
    initial["turns"] = json!([turn]);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    assert_eq!(view["items"], json!([value]));
    assert_eq!(view["turns"], json!([turn]));
    let page = store
        .agent_chat_history(&chat_id, i64::MAX, 200)
        .await
        .unwrap();
    assert_eq!(page.items, [value]);
    assert_eq!(page.turns, [turn]);
    assert!(serde_json::to_string(&page).unwrap().len() < 320 * 1024);
}

#[tokio::test]
async fn visible_items_share_their_turn_budget_and_preserve_turn_order() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["turns"] = json!([
        {"turnId": "z", "status": "completed", "unknown": "x".repeat(60 * 1024)},
        {"turnId": "a", "status": "completed"},
    ]);
    initial["items"] = json!((0..200)
        .map(|n| {
            let mut value = item(&format!("i{n}"), "assistant_message", "x");
            value["turnId"] = json!("z");
            value
        })
        .collect::<Vec<_>>());
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    assert_eq!(view["items"].as_array().unwrap().len(), 200);
    assert_eq!(view["turns"][0]["turnId"], "z");
    assert_eq!(view["turns"][1]["turnId"], "a");
    let page = store
        .agent_chat_history(&chat_id, i64::MAX, 200)
        .await
        .unwrap();
    assert_eq!(page.items.len(), 200);
    assert_eq!(page.turns.len(), 1);
}

#[tokio::test]
async fn excessive_live_metadata_is_rejected_before_a_chat_becomes_unreadable() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let mut next = snapshot(&chat_id, "ws", "tab", 0);
    for n in 0..15 {
        next["cursor"] = json!(n + 1);
        store.commit_agent_chat(&chat_id, n, &next, &json!({"turns": [{
            "turnId": format!("t{n}"), "status": "running", "unknown": "x".repeat(60 * 1024),
        }]}), None).await.unwrap();
    }
    next["cursor"] = json!(16);
    assert!(store
        .commit_agent_chat(
            &chat_id,
            15,
            &next,
            &json!({"turns": [{
                "turnId": "too-many", "status": "running", "unknown": "x".repeat(60 * 1024),
            }]}),
            None
        )
        .await
        .is_err());
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(view.cursor, 15);
    assert!(serde_json::to_string(&view.snapshot).unwrap().len() < 1024 * 1024);
    assert!(store
        .agent_chat_turn(&chat_id, "too-many")
        .await
        .unwrap()
        .is_none());
}
