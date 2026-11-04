//! Item changes accumulated between two commits. A rewritten item is sent
//! whole, read from the session at commit time, so a burst of updates to one
//! item lands once; text streamed into an item that was not rewritten is sent
//! as appends, which the store applies to its stored copy.

use std::collections::HashMap;

use serde_json::{Map, Value};
use tokio::time::Instant;

use super::wire::{json, merge_append, ChatItem, TextAppend};

#[derive(Default)]
pub(crate) struct PendingItems {
    pub deadline: Option<Instant>,
    rewritten: Vec<String>,
    appends: Vec<TextAppend>,
    removed: Vec<String>,
}

fn push_unique(list: &mut Vec<String>, id: &str) {
    if !list.iter().any(|existing| existing == id) {
        list.push(id.to_string());
    }
}

impl PendingItems {
    pub(crate) fn session(&mut self) {}
    pub(crate) fn recovery(&mut self) {}
    pub(crate) fn archived(&mut self) {}
    pub(crate) fn queue(&mut self) {}

    pub(crate) fn is_empty(&self) -> bool {
        self.rewritten.is_empty() && self.appends.is_empty() && self.removed.is_empty()
    }

    pub(crate) fn text_bytes(&self) -> usize {
        self.appends.iter().map(|append| append.text.len()).sum()
    }

    pub(crate) fn estimated_bytes(&self, items: &HashMap<String, ChatItem>) -> usize {
        let rewritten = self
            .rewritten
            .iter()
            .filter_map(|id| items.get(id))
            .filter_map(|item| serde_json::to_vec(item).ok())
            .map(|item| item.len())
            .sum::<usize>();
        let appends = serde_json::to_vec(&self.appends)
            .map(|value| value.len())
            .unwrap_or(usize::MAX);
        let removed = serde_json::to_vec(&self.removed)
            .map(|value| value.len())
            .unwrap_or(usize::MAX);
        rewritten.saturating_add(appends).saturating_add(removed)
    }

    /// The item is sent whole.
    pub(crate) fn item(&mut self, item_id: &str) {
        self.removed.retain(|id| id != item_id);
        self.appends.retain(|append| append.item_id != item_id);
        push_unique(&mut self.rewritten, item_id);
    }

    pub(crate) fn append(&mut self, item_id: &str, stream: &str, offset: usize, text: &str) {
        if self.rewritten.iter().any(|id| id == item_id) {
            return;
        }
        merge_append(&mut self.appends, item_id, stream, offset, text);
    }

    pub(crate) fn remove_item(&mut self, item_id: &str) {
        self.rewritten.retain(|id| id != item_id);
        self.appends.retain(|append| append.item_id != item_id);
        push_unique(&mut self.removed, item_id);
    }

    pub(crate) fn write_into(
        &self,
        items: &HashMap<String, ChatItem>,
        delta: &mut Map<String, Value>,
    ) {
        let rewritten: Vec<&ChatItem> = self
            .rewritten
            .iter()
            .filter_map(|id| items.get(id))
            .collect();
        if !rewritten.is_empty() {
            delta.insert("items".into(), json(&rewritten));
        }
        if !self.appends.is_empty() {
            delta.insert("textAppends".into(), json(&self.appends));
        }
        if !self.removed.is_empty() {
            delta.insert("removedItemIds".into(), json(&self.removed));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_rewrite_absorbs_earlier_and_later_appends() {
        let mut pending = PendingItems::default();
        pending.append("a", "text", 0, "he");
        pending.append("a", "text", 2, "llo");
        pending.append("b", "output", 0, "x");
        assert_eq!(pending.appends.len(), 2);
        pending.item("a");
        pending.append("a", "text", 5, "!");
        let mut items = HashMap::new();
        items.insert(
            "a".to_string(),
            ChatItem::new("a".into(), "assistant_message", "t", 1),
        );
        let mut delta = Map::new();
        pending.write_into(&items, &mut delta);
        assert_eq!(delta["items"].as_array().unwrap().len(), 1);
        assert_eq!(delta["textAppends"].as_array().unwrap().len(), 1);
        assert_eq!(delta["textAppends"][0]["itemId"], "b");
    }

    #[test]
    fn hidden_payload_rewrites_remain_in_the_durable_delta() {
        let mut pending = PendingItems::default();
        pending.item("payload:1");
        pending.append("payload:2", "text", 0, "retained");
        let mut item = ChatItem::new("payload:1".into(), "payload", "t", 1);
        item.normalized.insert("hidden".into(), Value::Bool(true));
        let mut items = HashMap::new();
        items.insert(item.item_id.clone(), item);
        let mut delta = Map::new();
        pending.write_into(&items, &mut delta);
        assert_eq!(delta["items"][0]["type"], "payload");
        assert_eq!(delta["items"][0]["normalized"]["hidden"], true);
        assert_eq!(delta["textAppends"][0]["text"], "retained");
    }
}
