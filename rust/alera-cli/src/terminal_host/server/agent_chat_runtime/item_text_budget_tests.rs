use std::collections::{HashMap, HashSet};

use serde_json::json;

use super::super::super::wire::{STREAM_OUTPUT, STREAM_REASONING, STREAM_TEXT};
use super::*;

fn head() -> ChatItem {
    let mut item = ChatItem::new(
        "parent".into(),
        "assistant_message",
        "2026-10-12T12:00:00.000Z",
        7,
    );
    item.turn_id = Some("turn".into());
    item.status = "completed".into();
    item.actor = Some("agent:child".into());
    item.client_message_id = Some("client".into());
    item.normalized.insert(
        "origin".into(),
        json!({"kind":"chatMessage", "senderChatId":"child"}),
    );
    item
}

fn replace(items: &mut HashMap<String, ChatItem>, stream: &str, text: &str) {
    let segments = segment_complete_item(items["parent"].clone(), stream, text).unwrap();
    for item in segments {
        items.insert(item.item_id.clone(), item);
    }
}

fn reconstruct(items: &HashMap<String, ChatItem>, stream: &str) -> String {
    let mut pieces = vec![(
        0,
        items["parent"]
            .stream_field_ref(stream)
            .cloned()
            .unwrap_or_default(),
    )];
    for item in items.values() {
        if item
            .normalized
            .get("continuationOf")
            .and_then(Value::as_str)
            == Some("parent")
            && item.normalized.get("stream").and_then(Value::as_str) == Some(stream)
        {
            pieces.push((
                item.normalized["segmentIndex"].as_u64().unwrap(),
                item.stream_field_ref(stream).unwrap().clone(),
            ));
        }
    }
    pieces.sort_by_key(|(index, _)| *index);
    for (expected, (index, _)) in pieces.iter().enumerate() {
        assert_eq!(*index, expected as u64);
    }
    pieces.into_iter().map(|(_, text)| text).collect()
}

#[test]
fn all_streams_fit_serialized_rows_and_reconstruct_exactly() {
    let text = "\"\\\u{0}\u{1f}\n🙂".repeat(45_000);
    let reasoning = "thinking\t\r\u{2}🧠".repeat(45_000);
    let output = "output\u{b}\\\"🚀".repeat(45_000);
    let mut item = head();
    item.data = Some(json!({"command":"run", "blob":"x".repeat(64 * 1024 - 40)}));
    item.normalized
        .insert("input".into(), json!({"message":"y".repeat(16 * 1024)}));
    let mut items = HashMap::from([(item.item_id.clone(), item)]);
    replace(&mut items, STREAM_TEXT, &text);
    replace(&mut items, STREAM_REASONING, &reasoning);
    replace(&mut items, STREAM_OUTPUT, &output);
    assert_eq!(reconstruct(&items, STREAM_TEXT), text);
    assert_eq!(reconstruct(&items, STREAM_REASONING), reasoning);
    assert_eq!(reconstruct(&items, STREAM_OUTPUT), output);
    let mut ids = HashSet::new();
    for item in items.values() {
        assert!(ids.insert(item.item_id.clone()));
        let bytes = serialized_item_bytes(item).unwrap();
        assert!(
            bytes <= AGENT_CHAT_ITEM_MAX_BYTES,
            "{}: {bytes}",
            item.item_id
        );
        assert_eq!(item.turn_id.as_deref(), Some("turn"));
        assert_eq!(item.generation, 7);
        assert_eq!(item.status, "completed");
        assert_eq!(item.actor.as_deref(), Some("agent:child"));
        assert_eq!(
            item.normalized["origin"],
            items["parent"].normalized["origin"]
        );
        if item.item_id != "parent" {
            assert!(item.client_message_id.is_none());
            assert!(item.data.is_none());
            assert!(!item.normalized.contains_key("input"));
            let stream = item.normalized["stream"].as_str().unwrap();
            let index = item.normalized["segmentIndex"].as_u64().unwrap() as usize;
            assert_eq!(item.item_id, continuation_item_id("parent", stream, index));
        }
    }
}

#[test]
fn encoded_prefix_matches_serde_json_and_ends_at_character_boundary() {
    for text in [
        "\"".repeat(300_000),
        "\\".repeat(300_000),
        "\u{0}".repeat(90_000),
        "🙂".repeat(90_000),
        "\n\r\t\u{8}\u{c}\u{1f}é".repeat(45_000),
    ] {
        let item = head();
        let take = stream_prefix_len(&item, STREAM_TEXT, &text).unwrap();
        assert!(text.is_char_boundary(take));
        let mut filled = item.clone();
        filled.text = Some(text[..take].into());
        assert!(serialized_item_bytes(&filled).unwrap() <= MAX_SEGMENT_ITEM_BYTES);
        let ch = text[take..].chars().next().unwrap();
        filled.text.as_mut().unwrap().push(ch);
        assert!(serialized_item_bytes(&filled).unwrap() > MAX_SEGMENT_ITEM_BYTES);
    }
}

#[test]
fn another_full_stream_moves_new_stream_into_its_first_continuation() {
    let first =
        segment_complete_item(head(), STREAM_TEXT, &"x".repeat(MAX_SEGMENT_ITEM_BYTES)).unwrap();
    let parent = first[0].clone();
    let reasoning = "🙂\u{0}".repeat(50_000);
    let segments = segment_complete_item(parent.clone(), STREAM_REASONING, &reasoning).unwrap();
    assert_eq!(segments[0].text, parent.text);
    assert_eq!(segments[0].reasoning_text.as_deref(), Some(""));
    assert_eq!(segments[1].item_id, "parent:segment:reasoningText:1");
    assert_eq!(
        segments
            .iter()
            .filter_map(|item| item.reasoning_text.as_deref())
            .collect::<String>(),
        reasoning
    );
}

#[test]
fn serialized_metadata_overflow_is_an_error_instead_of_truncated_text() {
    let mut item = head();
    item.normalized
        .insert("input".into(), json!("x".repeat(AGENT_CHAT_ITEM_MAX_BYTES)));
    assert!(segment_complete_item(item, STREAM_TEXT, "keep all text").is_err());
}
