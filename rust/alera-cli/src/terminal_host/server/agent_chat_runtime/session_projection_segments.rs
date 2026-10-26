//! Segment large canonical item content without losing transcript text.

use serde_json::Value;

use super::item_normalization::{
    continuation_item, continuation_item_id, segment_complete_item, stream_prefix_len,
    MAX_SEGMENT_ITEM_BYTES,
};
use super::session::ChatSession;
use super::wire::{utf16_len, ChatItem, STREAM_OUTPUT, STREAM_REASONING, STREAM_TEXT};

#[path = "session_projection_payload.rs"]
mod session_projection_payload;

impl ChatSession {
    pub(super) fn stream_target(&self, parent_id: &str, stream: &str) -> (String, usize) {
        let mut target = (parent_id.to_owned(), 0_usize);
        for (item_id, item) in &self.items {
            if item
                .normalized
                .get("continuationOf")
                .and_then(Value::as_str)
                != Some(parent_id)
                || item.normalized.get("stream").and_then(Value::as_str) != Some(stream)
            {
                continue;
            }
            let Some(index) = item.normalized.get("segmentIndex").and_then(Value::as_u64) else {
                continue;
            };
            if index as usize > target.1 {
                target = (item_id.clone(), index as usize);
            }
        }
        target
    }

    pub(super) fn ensure_stream_segment(
        &mut self,
        parent_id: &str,
        item_type: &str,
        turn_id: Option<String>,
        stream: &str,
        segment_index: usize,
    ) -> String {
        if !self.items.contains_key(parent_id) {
            let mut head = ChatItem::new(
                parent_id.into(),
                item_type,
                &super::ids::now(),
                self.generation,
            );
            head.turn_id = turn_id;
            self.insert_item(head);
        }
        let item_id = if segment_index == 0 {
            parent_id.to_owned()
        } else {
            continuation_item_id(parent_id, stream, segment_index)
        };
        if !self.items.contains_key(&item_id) {
            let head = self.items.get(parent_id).expect("parent was inserted");
            self.insert_item(continuation_item(head, stream, segment_index));
        }
        item_id
    }

    /// Persists every code point, including a stream whose first code point
    /// cannot fit beside the head's other streams or native metadata.
    pub(super) async fn append_stream(
        &mut self,
        parent_id: &str,
        item_type: &str,
        turn_id: Option<String>,
        stream: &str,
        text: &str,
    ) -> Result<(), String> {
        let mut remaining = text;
        let (_, mut segment_index) = self.stream_target(parent_id, stream);
        while !remaining.is_empty() {
            let target_id = self.ensure_stream_segment(
                parent_id,
                item_type,
                turn_id.clone(),
                stream,
                segment_index,
            );
            let (take, start_streaming) = {
                let item = self
                    .items
                    .get_mut(&target_id)
                    .expect("segment was inserted");
                let start_streaming = !item.streaming;
                item.streaming = true;
                item.updated_at = super::ids::now();
                (stream_prefix_len(item, stream, remaining)?, start_streaming)
            };
            if take == 0 {
                if segment_index > 0
                    && self.items[&target_id]
                        .stream_field_ref(stream)
                        .is_none_or(String::is_empty)
                {
                    return Err(format!(
                        "Item {target_id} continuation metadata exceeds the stream budget."
                    ));
                }
                segment_index += 1;
                continue;
            }
            let chunk = &remaining[..take];
            let item = self
                .items
                .get_mut(&target_id)
                .expect("segment was inserted");
            let offset = item
                .stream_field_ref(stream)
                .map_or(0, |field| utf16_len(field));
            item.stream_field(stream)
                .get_or_insert_with(String::new)
                .push_str(chunk);
            if start_streaming {
                self.pending.item(&target_id);
            } else {
                self.pending.append(&target_id, stream, offset, chunk);
            }
            remaining = &remaining[take..];
            if !remaining.is_empty()
                || self.pending.estimated_bytes(&self.items) >= MAX_SEGMENT_ITEM_BYTES
            {
                self.flush().await?;
            }
        }
        Ok(())
    }

    pub(super) async fn set_complete_stream(
        &mut self,
        parent_id: &str,
        item_type: &str,
        turn_id: Option<String>,
        stream: &str,
        text: &str,
    ) -> Result<(), String> {
        self.ensure_stream_segment(parent_id, item_type, turn_id, stream, 0);
        let mut head = self.items[parent_id].clone();
        head.status = "completed".into();
        head.streaming = false;
        head.updated_at = super::ids::now();
        self.replace_stream(head, stream, text).await
    }

    async fn replace_stream(
        &mut self,
        head: ChatItem,
        stream: &str,
        text: &str,
    ) -> Result<(), String> {
        let parent_id = head.item_id.clone();
        let segments = segment_complete_item(head, stream, text)?;
        let retained: std::collections::HashSet<_> =
            segments.iter().map(|item| item.item_id.clone()).collect();
        let obsolete: Vec<_> = self
            .items
            .values()
            .filter(|item| {
                item.normalized
                    .get("continuationOf")
                    .and_then(Value::as_str)
                    == Some(parent_id.as_str())
            })
            .filter(|item| item.normalized.get("stream").and_then(Value::as_str) == Some(stream))
            .filter(|item| !retained.contains(&item.item_id))
            .map(|item| item.item_id.clone())
            .collect();
        for item_id in obsolete {
            self.items.remove(&item_id);
            self.pending.remove_item(&item_id);
        }
        let segment_count = segments.len();
        for (index, item) in segments.into_iter().enumerate() {
            self.insert_item(item);
            if index + 1 < segment_count {
                self.flush().await?;
            }
        }
        Ok(())
    }

    /// Lifecycle metadata can grow after the stream filled its head row.
    /// Repartition the live streams with that final metadata in the budget.
    pub(super) async fn rebalance_streams(&mut self, parent_id: &str) -> Result<(), String> {
        let Some(head) = self.items.get(parent_id).cloned() else {
            return Ok(());
        };
        let mut streams = Vec::new();
        for stream in [STREAM_TEXT, STREAM_REASONING, STREAM_OUTPUT] {
            let mut pieces = vec![(
                0,
                head.stream_field_ref(stream).cloned().unwrap_or_default(),
            )];
            for item in self.items.values() {
                if item
                    .normalized
                    .get("continuationOf")
                    .and_then(Value::as_str)
                    == Some(parent_id)
                    && item.normalized.get("stream").and_then(Value::as_str) == Some(stream)
                {
                    if let Some(index) = item.normalized.get("segmentIndex").and_then(Value::as_u64)
                    {
                        pieces.push((
                            index,
                            item.stream_field_ref(stream).cloned().unwrap_or_default(),
                        ));
                    }
                }
            }
            if head.stream_field_ref(stream).is_none() && pieces.len() == 1 {
                continue;
            }
            pieces.sort_by_key(|(index, _)| *index);
            let text: String = pieces.into_iter().map(|(_, text)| text).collect();
            streams.push((stream, text));
        }
        let parent = self
            .items
            .get_mut(parent_id)
            .expect("parent is still present");
        parent.text = None;
        parent.reasoning_text = None;
        parent.output = None;
        for (stream, text) in streams {
            let next = self.items[parent_id].clone();
            self.replace_stream(next, stream, &text).await?;
        }
        Ok(())
    }
}
