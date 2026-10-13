//! The session actor's copy of the stored snapshot header (everything but
//! items). Each commit sends the new header and a delta computed by diffing
//! it against the last committed one, so the delta always explains exactly
//! what changed, which the store verifies.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::wire::{json, ChatRequest, ChatTurn, QueueEntry};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SessionView {
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub runtime_mode: String,
    pub interaction_mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active_turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default)]
    pub generation: i64,
    #[serde(default = "empty_object")]
    pub capabilities: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

fn empty_object() -> Value {
    Value::Object(Map::new())
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Header {
    pub chat_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub provider_instance_id: String,
    pub provider: String,
    #[serde(default)]
    pub title: String,
    pub cursor: i64,
    pub session: SessionView,
    #[serde(default)]
    pub turns: Vec<ChatTurn>,
    #[serde(default)]
    pub pending_requests: Vec<ChatRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recovery: Option<Value>,
    #[serde(default)]
    pub queue: Vec<QueueEntry>,
    #[serde(default)]
    pub archived: bool,
    /// Safe lineage projected from host metadata (`originKind`,
    /// `parentChatId`, ...); the metadata itself never leaves the host.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lineage: Option<Value>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Header {
    /// Parses a stored snapshot, dropping the item page a read attaches.
    pub(crate) fn from_snapshot(mut snapshot: Value) -> Result<Self, String> {
        if let Some(object) = snapshot.as_object_mut() {
            object.remove("items");
            object.remove("historyBefore");
        }
        serde_json::from_value(snapshot).map_err(|error| format!("chat header: {error}"))
    }

    pub(crate) fn to_snapshot(&self) -> Value {
        let mut value = json(self);
        value["items"] = Value::Array(Vec::new());
        value
    }

    pub(crate) fn turn_mut(&mut self, turn_id: &str) -> Option<&mut ChatTurn> {
        self.turns.iter_mut().find(|turn| turn.turn_id == turn_id)
    }

    pub(crate) fn upsert_turn(&mut self, turn: ChatTurn) {
        match self.turn_mut(&turn.turn_id) {
            Some(existing) => *existing = turn,
            None => self.turns.push(turn),
        }
    }
}

/// Header fields of the delta from `old` to `new`.
pub(crate) fn header_delta(old: &Header, new: &Header) -> Map<String, Value> {
    let mut delta = Map::new();
    if old.session != new.session {
        delta.insert("session".into(), json(&new.session));
    }
    if old.pending_requests != new.pending_requests {
        delta.insert("requests".into(), json(&new.pending_requests));
    }
    if old.title != new.title {
        delta.insert("title".into(), Value::String(new.title.clone()));
    }
    if old.usage != new.usage {
        delta.insert("usage".into(), new.usage.clone().unwrap_or(Value::Null));
    }
    if old.recovery != new.recovery {
        delta.insert(
            "recovery".into(),
            new.recovery.clone().unwrap_or(Value::Null),
        );
    }
    if old.provider != new.provider || old.provider_instance_id != new.provider_instance_id {
        delta.insert("provider".into(), Value::String(new.provider.clone()));
        delta.insert(
            "providerInstanceId".into(),
            Value::String(new.provider_instance_id.clone()),
        );
    }
    let changed_turns: Vec<&ChatTurn> = new
        .turns
        .iter()
        .filter(|turn| !old.turns.contains(turn))
        .collect();
    if !changed_turns.is_empty() {
        delta.insert("turns".into(), json(&changed_turns));
    }
    if old.queue != new.queue {
        delta.insert("queue".into(), json(&new.queue));
    }
    if old.archived != new.archived {
        delta.insert("archived".into(), Value::Bool(new.archived));
    }
    if old.lineage != new.lineage {
        delta.insert("lineage".into(), new.lineage.clone().unwrap_or(Value::Null));
    }
    if old.tab_id != new.tab_id {
        delta.insert("tabId".into(), Value::String(new.tab_id.clone()));
    }
    delta
}

/// The lineage a client may see, taken from explicit metadata keys only.
pub(crate) fn lineage_from_metadata(metadata: Option<&Value>) -> Option<Value> {
    let metadata = metadata?.as_object()?;
    let mut lineage = Map::new();
    for key in [
        "originKind",
        "parentChatId",
        "runId",
        "taskId",
        "createdByChatId",
    ] {
        if let Some(Value::String(value)) = metadata.get(key) {
            lineage.insert(key.into(), Value::String(value.chars().take(256).collect()));
        }
    }
    (!lineage.is_empty()).then_some(Value::Object(lineage))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn header() -> Header {
        Header::from_snapshot(json!({
            "chatId": "c", "workspaceId": "w", "tabId": "t",
            "providerInstanceId": "codex", "provider": "codex", "cursor": 0,
            "session": {"status": "stopped", "runtimeMode": "approval-required", "interactionMode": "default"},
            "items": [{"itemId": "x"}],
        }))
        .unwrap()
    }

    #[test]
    fn diff_names_only_what_changed() {
        let old = header();
        assert!(!old.extra.contains_key("items"));
        let mut new = old.clone();
        new.title = "Renamed".into();
        new.recovery = None;
        new.archived = true;
        let delta = header_delta(&old, &new);
        assert_eq!(delta.len(), 2);
        assert_eq!(delta["title"], "Renamed");
        assert_eq!(delta["archived"], true);
    }

    #[test]
    fn cleared_recovery_is_sent_as_null() {
        let mut old = header();
        old.recovery = Some(json!({"kind": "resumable"}));
        let new = header();
        assert_eq!(header_delta(&old, &new)["recovery"], Value::Null);
    }

    #[test]
    fn lineage_projects_only_named_string_keys() {
        let lineage = lineage_from_metadata(Some(&json!({
            "parentChatId": "p", "token": "secret", "runId": 4
        })))
        .unwrap();
        assert_eq!(lineage, json!({"parentChatId": "p"}));
    }
}
