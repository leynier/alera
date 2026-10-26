use super::*;
#[tokio::test]
async fn payload_versions_reject_partially_rewritten_rows_and_revisions_change() {
    let (_dir, store) = store_with_workspace("ws").await;
    let mut head = payload_head("head", 2);
    head["normalized"]["payloadRef"]["payloadVersion"] = json!("first");
    let mut first = payload_chunk("head", 1, "old-a");
    let mut second = payload_chunk("head", 2, "old-b");
    first["normalized"]["payloadVersion"] = json!("first");
    second["normalized"]["payloadVersion"] = json!("first");
    let chat_id = create_items(
        &store,
        "tab",
        vec![head.clone(), first.clone(), second.clone()],
        vec![],
    )
    .await;
    let old = store
        .agent_chat_payload(&chat_id, "head", 0, 1)
        .await
        .unwrap();
    head["normalized"]["payloadRef"]["payloadVersion"] = json!("second");
    first["normalized"]["payloadVersion"] = json!("second");
    first["text"] = json!("new-a");
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"items": [head, first]}),
            None,
        )
        .await
        .unwrap();
    assert_invalid(
        store
            .agent_chat_payload(&chat_id, "head", 0, 1)
            .await
            .unwrap_err(),
    );
    second["normalized"]["payloadVersion"] = json!("second");
    second["text"] = json!("new-b");
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(&chat_id, cursor, &next, &json!({"items": [second]}), None)
        .await
        .unwrap();
    let new = store
        .agent_chat_payload(&chat_id, "head", 0, 1)
        .await
        .unwrap();
    assert_ne!(new.revision, old.revision);
    assert_eq!(new.segment_count, old.segment_count);
    let tail = store
        .agent_chat_payload(&chat_id, "head", 1, 1)
        .await
        .unwrap();
    assert_eq!(tail.revision, new.revision);
    assert_eq!(new.chunks[0].text, "new-a");
    assert_eq!(tail.chunks[0].text, "new-b");
}

#[tokio::test]
async fn obsolete_payload_lookup_is_strictly_owned_and_deletion_uses_normal_commits() {
    let (_dir, store) = store_with_workspace("ws").await;
    let mut nonpayload = item("unknown", "future_item", "Future");
    nonpayload["normalized"] = json!({
        "hidden": true, "payloadOf": "head", "payloadIndex": 1, "format": "json"
    });
    let chat_id = create_items(
        &store,
        "tab",
        vec![
            payload_head("head", 3),
            payload_chunk("head", 1, "a"),
            payload_chunk("head", 2, "b"),
            payload_chunk("head", 3, "obsolete"),
            payload_chunk("foreign", 1, "foreign"),
            nonpayload,
        ],
        vec![],
    )
    .await;
    let ids = store
        .agent_chat_payload_item_ids(&chat_id, "head")
        .await
        .unwrap();
    assert_eq!(ids, ["head:payload:1", "head:payload:2", "head:payload:3"]);
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    store
        .commit_agent_chat(
            &chat_id,
            cursor,
            &next,
            &json!({"items": [payload_head("head", 2)], "removedItemIds": [ids[2]]}),
            None,
        )
        .await
        .unwrap();
    assert_eq!(
        store
            .agent_chat_payload_item_ids(&chat_id, "head")
            .await
            .unwrap(),
        ["head:payload:1", "head:payload:2"]
    );
    assert!(store
        .agent_chat_item(&chat_id, "head:payload:3")
        .await
        .unwrap()
        .is_none());
    assert!(store
        .agent_chat_item(&chat_id, "foreign:payload:1")
        .await
        .unwrap()
        .is_some());
    assert!(store
        .agent_chat_item(&chat_id, "unknown")
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        store
            .agent_chat_payload(&chat_id, "head", 0, 200)
            .await
            .unwrap()
            .chunks
            .iter()
            .map(|chunk| chunk.text.as_str())
            .collect::<Vec<_>>(),
        ["a", "b"]
    );
    let first = store
        .agent_chat_payload(&chat_id, "head", 0, 1)
        .await
        .unwrap();
    assert_eq!(first.chunks[0].text, "a");
    assert_eq!(first.next_index, Some(1));
    assert_eq!(
        store
            .agent_chat_payload(&chat_id, "head", 1, 1)
            .await
            .unwrap()
            .chunks[0]
            .text,
        "b"
    );
}
