//! Client-facing chat records. These are what the store persists and what
//! `agentChat.snapshot` and `agentChatChanged` carry; native provider ids never
//! appear in them.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub(crate) const STREAM_TEXT: &str = "text";
pub(crate) const STREAM_REASONING: &str = "reasoningText";
pub(crate) const STREAM_OUTPUT: &str = "output";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChatItem {
    pub item_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(rename = "type")]
    pub item_type: String,
    pub status: String,
    #[serde(default)]
    pub streaming: bool,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attachments: Option<Vec<Value>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub actor: Option<String>,
    #[serde(default)]
    pub normalized: Map<String, Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(default)]
    pub generation: i64,
}

impl ChatItem {
    pub(crate) fn new(item_id: String, item_type: &str, now: &str, generation: i64) -> Self {
        Self {
            item_id,
            turn_id: None,
            item_type: item_type.to_string(),
            status: "inProgress".into(),
            streaming: false,
            created_at: now.to_string(),
            updated_at: now.to_string(),
            title: None,
            detail: None,
            text: None,
            reasoning_text: None,
            output: None,
            client_message_id: None,
            attachments: None,
            actor: None,
            normalized: Map::new(),
            data: None,
            generation,
        }
    }

    pub(crate) fn stream_field(&mut self, stream: &str) -> &mut Option<String> {
        match stream {
            STREAM_REASONING => &mut self.reasoning_text,
            STREAM_OUTPUT => &mut self.output,
            _ => &mut self.text,
        }
    }

    pub(crate) fn stream_field_ref(&self, stream: &str) -> Option<&String> {
        match stream {
            STREAM_REASONING => self.reasoning_text.as_ref(),
            STREAM_OUTPUT => self.output.as_ref(),
            _ => self.text.as_ref(),
        }
    }

    pub(crate) fn is_hidden_payload(&self) -> bool {
        self.item_type == "payload" && self.normalized.get("hidden") == Some(&Value::Bool(true))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChatTurn {
    pub turn_id: String,
    pub status: String,
    #[serde(default)]
    pub started_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub provider_instance_id: String,
    #[serde(default)]
    pub generation: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ChatRequest {
    pub request_id: String,
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default)]
    pub questions: Vec<Value>,
    #[serde(default)]
    pub decisions: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elicitation: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct QueueEntry {
    pub queue_id: String,
    pub client_message_id: String,
    pub text: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<Value>,
    pub created_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub interaction_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime_mode_ceiling: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub actor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Recovery {
    pub kind: String,
    pub message: String,
    pub can_resume: bool,
    pub can_restart: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct TextAppend {
    pub item_id: String,
    pub stream: String,
    pub offset: usize,
    pub text: String,
}

/// Adds an append, merging it into the previous one for the same field when
/// it continues exactly where that one ended.
pub(crate) fn merge_append(
    appends: &mut Vec<TextAppend>,
    item_id: &str,
    stream: &str,
    offset: usize,
    text: &str,
) {
    if let Some(last) = appends
        .iter_mut()
        .rev()
        .find(|append| append.item_id == item_id && append.stream == stream)
    {
        if last.offset + utf16_len(&last.text) == offset {
            last.text.push_str(text);
            return;
        }
    }
    appends.push(TextAppend {
        item_id: item_id.to_string(),
        stream: stream.to_string(),
        offset,
        text: text.to_string(),
    });
}

pub(crate) fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

pub(crate) fn json<T: Serialize>(value: &T) -> Value {
    serde_json::to_value(value).unwrap_or(Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adjacent_appends_merge() {
        let mut appends = Vec::new();
        merge_append(&mut appends, "i1", STREAM_TEXT, 0, "hé");
        merge_append(&mut appends, "i1", STREAM_TEXT, 2, "llo");
        merge_append(&mut appends, "i1", STREAM_OUTPUT, 0, "x");
        merge_append(&mut appends, "i1", STREAM_TEXT, 9, "gap");
        assert_eq!(appends.len(), 3);
        assert_eq!(appends[0].text, "héllo");
    }
}
