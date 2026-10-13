use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::*;

fn payload_head(id: &str, count: usize) -> Value {
    let mut head = item(id, "mcp_tool_call", "Tool result");
    head["normalized"]["payloadRef"] =
        json!({"itemId": format!("{id}:payload:1"), "segmentCount": count, "format": "json"});
    head
}

fn payload_chunk(head: &str, index: usize, text: &str) -> Value {
    let mut chunk = item(&format!("{head}:payload:{index}"), "payload", text);
    chunk["normalized"] =
        json!({"hidden": true, "payloadOf": head, "payloadIndex": index, "format": "json"});
    chunk
}

async fn create_items(
    store: &RuntimeStore,
    tab_id: &str,
    items: Vec<Value>,
    turns: Vec<Value>,
) -> String {
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", tab_id, 0);
    initial["items"] = json!(items);
    initial["turns"] = json!(turns);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", tab_id, initial),
            &tab(&chat_id, "ws", tab_id),
            None,
        )
        .await
        .unwrap();
    chat_id
}

fn assert_invalid(error: anyhow::Error) {
    assert!(
        matches!(
            error.downcast_ref::<AgentChatStoreError>(),
            Some(AgentChatStoreError::Invalid(_))
        ),
        "{error:#}"
    );
}

#[tokio::test]
async fn hidden_payload_rows_never_evict_visible_heads_or_consume_history_cursors() {
    let (_dir, store) = store_with_workspace("ws").await;
    let mut items: Vec<_> = (0..205)
        .map(|n| {
            let mut value = item(&format!("old-{n}"), "assistant_message", "Answer");
            value["turnId"] = json!("old-turn");
            value
        })
        .collect();
    let mut head = payload_head("tool", 250);
    head["turnId"] = json!("tool-turn");
    items.push(head.clone());
    let tail = item("tail", "assistant_message", "Done");
    items.push(tail.clone());
    items.extend((1..=250).map(|n| {
        let mut chunk = payload_chunk("tool", n, &"x".repeat(4096));
        chunk["turnId"] = json!("payload-only-turn");
        chunk
    }));
    let chat_id = create_items(
        &store,
        "tab",
        items,
        vec![
            json!({"turnId": "old-turn", "status": "completed"}),
            json!({"turnId": "tool-turn", "status": "completed"}),
            json!({"turnId": "payload-only-turn", "status": "completed"}),
        ],
    )
    .await;
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    let visible = view["items"].as_array().unwrap();
    assert_eq!(visible.len(), 200);
    assert_eq!(visible[198], head);
    assert_eq!(visible[199], tail);
    let mut before = i64::MAX;
    let mut seen = Vec::new();
    loop {
        let page = store
            .agent_chat_history(&chat_id, before, 50)
            .await
            .unwrap();
        assert!(!page.items.is_empty());
        assert!(!page
            .turns
            .iter()
            .any(|turn| turn["turnId"] == "payload-only-turn"));
        seen.extend(
            page.items
                .into_iter()
                .map(|item| item["itemId"].as_str().unwrap().to_string()),
        );
        let Some(next) = page.history_before else {
            break;
        };
        assert!(next < before);
        before = next;
    }
    seen.sort();
    seen.dedup();
    assert_eq!(seen.len(), 207);
    assert!(store
        .agent_chat_item(&chat_id, "tool:payload:250")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn only_boolean_hidden_payloads_are_excluded_from_normal_views() {
    let (_dir, store) = store_with_workspace("ws").await;
    let mut unknown = item("unknown", "future_item", "Future content");
    unknown["normalized"]["hidden"] = json!(true);
    let mut string_hidden = item("string", "payload", "Visible malformed marker");
    string_hidden["normalized"]["hidden"] = json!("true");
    let mut number_hidden = item("number", "payload", "Visible malformed marker");
    number_hidden["normalized"]["hidden"] = json!(1);
    let mut public_payload = item("public", "payload", "Visible payload");
    public_payload["normalized"]["hidden"] = json!(false);
    let hidden = payload_chunk("head", 1, "Hidden");
    let expected = vec![unknown, string_hidden, number_hidden, public_payload];
    let mut all = expected.clone();
    all.push(hidden);
    let chat_id = create_items(&store, "tab", all, vec![]).await;
    assert_eq!(
        store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot["items"],
        json!(expected)
    );
    assert_eq!(
        store
            .agent_chat_history(&chat_id, i64::MAX, 200)
            .await
            .unwrap()
            .items,
        expected
    );
}

#[tokio::test]
async fn payload_pages_reconstruct_exact_json_after_restart_and_archive() {
    let (dir, store) = store_with_workspace("ws").await;
    let retained = json!({"data": "🧪\"\n\\".repeat(90_000), "last": "complete"}).to_string();
    let mut parts = Vec::new();
    let mut remaining = retained.as_str();
    while !remaining.is_empty() {
        let mut end = remaining.len().min(70_000);
        while !remaining.is_char_boundary(end) {
            end -= 1;
        }
        parts.push(remaining[..end].to_string());
        remaining = &remaining[end..];
    }
    let mut items = vec![payload_head("head", parts.len())];
    items.extend(
        parts
            .iter()
            .enumerate()
            .map(|(n, text)| payload_chunk("head", n + 1, text)),
    );
    let chat_id = create_items(&store, "tab", items, vec![]).await;
    store.archive_agent_chat(&chat_id).await.unwrap();
    drop(store);
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let mut index = 0;
    let mut loaded = String::new();
    let mut pages = 0;
    loop {
        let page = reopened
            .agent_chat_payload(&chat_id, "head", index, 200)
            .await
            .unwrap();
        assert!(serde_json::to_vec(&page).unwrap().len() <= AGENT_CHAT_PAGE_MAX_BYTES);
        assert_eq!(page.segment_count, parts.len() as u64);
        assert_eq!(page.format, "json");
        for chunk in page.chunks {
            assert_eq!(chunk.index, index);
            index += 1;
            loaded.push_str(&chunk.text);
        }
        pages += 1;
        let Some(next) = page.next_index else { break };
        assert_eq!(next, index);
    }
    assert!(pages > 1);
    assert_eq!(loaded, retained);
    assert_eq!(
        serde_json::from_str::<Value>(&loaded).unwrap()["last"],
        "complete"
    );
}

#[tokio::test]
async fn first_payload_chunk_fits_the_exact_page_budget_near_the_item_limit() {
    let (_dir, store) = store_with_workspace("ws").await;
    let text = "x".repeat(AGENT_CHAT_ITEM_MAX_BYTES - 700);
    let first = payload_chunk("head", 1, &text);
    assert!(serde_json::to_vec(&first).unwrap().len() <= AGENT_CHAT_ITEM_MAX_BYTES);
    let chat_id = create_items(
        &store,
        "tab",
        vec![
            payload_head("head", 2),
            first,
            payload_chunk("head", 2, "tail"),
        ],
        vec![],
    )
    .await;
    let page = store
        .agent_chat_payload(&chat_id, "head", 0, 200)
        .await
        .unwrap();
    assert_eq!(page.chunks.len(), 1);
    assert_eq!(page.chunks[0].text, text);
    assert_eq!(page.next_index, Some(1));
    assert!(serde_json::to_vec(&page).unwrap().len() <= AGENT_CHAT_PAGE_MAX_BYTES);
    assert_eq!(
        store
            .agent_chat_payload(&chat_id, "head", 1, 1)
            .await
            .unwrap()
            .chunks[0]
            .text,
        "tail"
    );
}

#[tokio::test]
async fn inline_payload_uses_the_same_reader_without_parsing_the_json_text() {
    let (_dir, store) = store_with_workspace("ws").await;
    let mut head = item("head", "mcp_tool_call", "Preview");
    let data = json!({"nested": {"value": "🧪\"\n"}, "other": [1, true]});
    head["data"] = data.clone();
    head["normalized"]["payloadRef"] = json!({"field": "data", "format": "json"});
    let chat_id = create_items(&store, "tab", vec![head], vec![]).await;
    let page = store
        .agent_chat_payload(&chat_id, "head", 0, 1)
        .await
        .unwrap();
    assert_eq!(page.segment_count, 1);
    assert_eq!(page.next_index, None);
    assert_eq!(page.chunks[0].text, data.to_string());
    assert_invalid(
        store
            .agent_chat_payload(&chat_id, "head", 1, 1)
            .await
            .unwrap_err(),
    );
}

#[tokio::test]
async fn payload_read_rejects_foreign_heads_chunks_missing_rows_and_duplicate_indices() {
    let (_dir, store) = store_with_workspace("ws").await;
    let fixtures = [
        vec![payload_head("head", 2), payload_chunk("head", 1, "a")],
        vec![
            payload_head("head", 2),
            payload_chunk("head", 1, "a"),
            payload_chunk("head", 3, "b"),
        ],
        {
            let mut duplicate = payload_chunk("head", 1, "b");
            duplicate["itemId"] = json!("duplicate");
            vec![
                payload_head("head", 2),
                payload_chunk("head", 1, "a"),
                duplicate,
            ]
        },
        {
            let mut head = payload_head("head", 1);
            head["normalized"]["payloadRef"]["itemId"] = json!("other:payload:1");
            vec![head, payload_chunk("other", 1, "foreign")]
        },
        {
            let mut broken = payload_chunk("head", 1, "a");
            broken["normalized"]["format"] = json!("text");
            vec![payload_head("head", 1), broken]
        },
        {
            let mut broken = payload_chunk("head", 1, "a");
            broken["normalized"]["payloadIndex"] = json!("1");
            vec![payload_head("head", 1), broken]
        },
        {
            let mut broken = payload_chunk("head", 1, "a");
            broken["normalized"]["hidden"] = json!(1);
            vec![payload_head("head", 1), broken]
        },
    ];
    for (n, items) in fixtures.into_iter().enumerate() {
        let chat_id = create_items(&store, &format!("tab-{n}"), items, vec![]).await;
        assert_invalid(
            store
                .agent_chat_payload(&chat_id, "head", 0, 200)
                .await
                .unwrap_err(),
        );
    }
    let chat_a = create_items(&store, "tab-a", vec![payload_head("head", 1)], vec![]).await;
    let chat_b = create_items(
        &store,
        "tab-b",
        vec![payload_head("head", 1), payload_chunk("head", 1, "foreign")],
        vec![],
    )
    .await;
    assert_invalid(
        store
            .agent_chat_payload(&chat_a, "head", 0, 200)
            .await
            .unwrap_err(),
    );
    assert_invalid(
        store
            .agent_chat_payload(&chat_b, "head:payload:1", 0, 200)
            .await
            .unwrap_err(),
    );
}

#[tokio::test]
async fn malformed_payload_references_and_missing_identity_return_domain_errors() {
    let (_dir, store) = store_with_workspace("ws").await;
    let references = [
        Value::Null,
        json!({"itemId": "x", "segmentCount": 0, "format": "json"}),
        json!({"itemId": "x", "segmentCount": "1", "format": "json"}),
        json!({"field": "data", "format": "text"}),
        json!({"field": "data", "format": "json"}),
        json!({"field": "data", "itemId": "x", "segmentCount": 1, "format": "json"}),
    ];
    let items = references
        .into_iter()
        .enumerate()
        .map(|(n, reference)| {
            let mut head = item(&format!("head-{n}"), "mcp_tool_call", "Preview");
            head["normalized"]["payloadRef"] = reference;
            head
        })
        .collect();
    let chat_id = create_items(&store, "tab", items, vec![]).await;
    for n in 0..6 {
        assert_invalid(
            store
                .agent_chat_payload(&chat_id, &format!("head-{n}"), 0, 200)
                .await
                .unwrap_err(),
        );
    }
    for (chat, head) in [(&chat_id, "missing"), (&new_chat_id(), "head")] {
        let error = store
            .agent_chat_payload(chat, head, 0, 200)
            .await
            .unwrap_err();
        assert!(matches!(
            error.downcast_ref::<AgentChatStoreError>(),
            Some(AgentChatStoreError::NotFound(_))
        ));
    }
}

#[path = "agent_chat_payload_revision_tests.rs"]
mod revision_tests;
