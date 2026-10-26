//! UTF-8 stream segments sized against their complete serialized store row.

use alera_core::runtime::AGENT_CHAT_ITEM_MAX_BYTES;
use serde_json::Value;

use super::super::wire::ChatItem;

// Leave room for lifecycle status and timestamp changes, plus delta framing.
pub(crate) const MAX_SEGMENT_ITEM_BYTES: usize = AGENT_CHAT_ITEM_MAX_BYTES - 16 * 1024;

pub(crate) fn serialized_item_bytes(item: &ChatItem) -> Result<usize, String> {
    serde_json::to_vec(item)
        .map(|bytes| bytes.len())
        .map_err(|error| error.to_string())
}

fn encoded_char_bytes(ch: char) -> usize {
    match ch {
        '"' | '\\' | '\u{8}' | '\u{c}' | '\n' | '\r' | '\t' => 2,
        '\u{0}'..='\u{1f}' => 6,
        _ => ch.len_utf8(),
    }
}

/// The next prefix that fits after the existing field, counting the exact
/// JSON escaping serde_json uses and all other fields already on this item.
pub(crate) fn stream_prefix_len(
    item: &ChatItem,
    stream: &str,
    text: &str,
) -> Result<usize, String> {
    let mut bytes = serialized_item_bytes(item)?;
    if item.stream_field_ref(stream).is_none() {
        // An absent optional field becomes ,"field":"" before its content.
        bytes = bytes.saturating_add(stream.len() + 6);
    }
    let available = MAX_SEGMENT_ITEM_BYTES.saturating_sub(bytes);
    Ok(json_text_prefix_len(text, available))
}

pub(super) fn json_text_prefix_len(text: &str, available: usize) -> usize {
    let mut encoded = 0;
    let mut prefix = 0;
    for ch in text.chars() {
        let next = encoded_char_bytes(ch);
        if next > available.saturating_sub(encoded) {
            break;
        }
        encoded += next;
        prefix += ch.len_utf8();
    }
    prefix
}

pub(crate) fn continuation_item_id(parent_id: &str, stream: &str, segment_index: usize) -> String {
    format!("{parent_id}:segment:{stream}:{segment_index}")
}

pub(crate) fn continuation_item(head: &ChatItem, stream: &str, segment_index: usize) -> ChatItem {
    let mut item = ChatItem::new(
        continuation_item_id(&head.item_id, stream, segment_index),
        &head.item_type,
        &head.created_at,
        head.generation,
    );
    item.turn_id = head.turn_id.clone();
    item.status = head.status.clone();
    item.streaming = head.streaming;
    item.updated_at = head.updated_at.clone();
    item.actor = head.actor.clone();
    if let Some(origin) = head.normalized.get("origin") {
        item.normalized.insert("origin".into(), origin.clone());
    }
    item.normalized
        .insert("continuationOf".into(), Value::String(head.item_id.clone()));
    item.normalized
        .insert("segmentIndex".into(), Value::from(segment_index as u64));
    item.normalized
        .insert("stream".into(), Value::String(stream.to_owned()));
    item
}

/// Keeps the original identity and metadata on the head. Each sibling owns
/// only one stream, so unrelated fields and native payloads are never copied.
pub(crate) fn segment_complete_item(
    mut head: ChatItem,
    stream: &str,
    text: &str,
) -> Result<Vec<ChatItem>, String> {
    *head.stream_field(stream) = Some(String::new());
    if serialized_item_bytes(&head)? > AGENT_CHAT_ITEM_MAX_BYTES {
        return Err(format!(
            "Item {} metadata exceeds the store row budget.",
            head.item_id
        ));
    }
    let mut items = Vec::new();
    let mut remaining = text;
    let take = stream_prefix_len(&head, stream, remaining)?;
    *head.stream_field(stream) = Some(remaining[..take].to_string());
    remaining = &remaining[take..];
    items.push(head);
    let mut segment_index = 1;
    while !remaining.is_empty() {
        let mut item = continuation_item(&items[0], stream, segment_index);
        let take = stream_prefix_len(&item, stream, remaining)?;
        if take == 0 {
            return Err(format!(
                "Item {} continuation metadata exceeds the stream budget.",
                item.item_id
            ));
        }
        *item.stream_field(stream) = Some(remaining[..take].to_string());
        remaining = &remaining[take..];
        items.push(item);
        segment_index += 1;
    }
    Ok(items)
}

#[cfg(test)]
#[path = "item_text_budget_tests.rs"]
mod tests;
