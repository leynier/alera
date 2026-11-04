//! Hidden, history-loadable rows for large native tool payloads.

use std::collections::HashSet;

use serde_json::{json, Value};

use super::super::ids::new_id;
use super::super::item_normalization::payload_items;
use super::super::session::ChatSession;

impl ChatSession {
    pub(in super::super) async fn set_item_payload(
        &mut self,
        parent_id: &str,
        payload: Option<&str>,
    ) -> Result<(), String> {
        let Some(head) = self.items.get(parent_id).cloned() else {
            return Ok(());
        };
        let mut segments = payload
            .map(|text| payload_items(&head, text))
            .transpose()?
            .unwrap_or_default();
        let version = new_id("payload");
        for item in &mut segments {
            item.normalized
                .insert("payloadVersion".into(), json!(version));
        }
        let retained: HashSet<_> = segments.iter().map(|item| item.item_id.clone()).collect();
        let mut existing: HashSet<_> = self
            .deps
            .store
            .agent_chat_payload_item_ids(&self.header.chat_id, parent_id)
            .await
            .map_err(|error| error.to_string())?
            .into_iter()
            .collect();
        existing.extend(
            self.items
                .values()
                .filter(|item| {
                    item.is_hidden_payload()
                        && item.normalized.get("payloadOf").and_then(Value::as_str)
                            == Some(parent_id)
                })
                .map(|item| item.item_id.clone()),
        );
        for item_id in existing.difference(&retained) {
            self.items.remove(item_id);
            self.pending.remove_item(item_id);
        }
        let parent = self
            .items
            .get_mut(parent_id)
            .expect("parent is still present");
        if let Some(first) = segments.first() {
            parent.normalized.insert(
                "payloadRef".into(),
                json!({
                    "itemId":first.item_id, "segmentCount":segments.len(), "format":"json",
                    "payloadVersion":version
                }),
            );
        } else if parent
            .normalized
            .get("payloadRef")
            .and_then(|reference| reference.get("field"))
            .and_then(Value::as_str)
            != Some("data")
        {
            parent.normalized.remove("payloadRef");
        }
        self.pending.item(parent_id);
        for item in segments {
            if !self.pending.is_empty() {
                self.flush().await?;
            }
            self.insert_item(item);
        }
        Ok(())
    }
}
