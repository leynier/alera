use alera_provider_protocol::StreamKind;
use serde_json::Value;
use std::collections::HashMap;

/// Native message roles and part kinds for the currently admitted turn.
#[derive(Default)]
pub(crate) struct NativeParts {
    user_messages: HashMap<String, bool>,
    stream_kinds: HashMap<(String, String), StreamKind>,
}

impl NativeParts {
    pub fn start_turn(&mut self, user_message_id: Option<String>) {
        self.clear();
        if let Some(id) = user_message_id {
            self.user_messages.insert(id, true);
        }
    }

    pub fn clear(&mut self) {
        self.user_messages.clear();
        self.stream_kinds.clear();
    }

    pub fn record_message(&mut self, props: &Value) {
        let info = props.get("info").unwrap_or(props);
        if let (Some(id), Some(role)) = (
            info.get("id").and_then(Value::as_str),
            info.get("role").and_then(Value::as_str),
        ) {
            match role {
                "user" => self.user_messages.insert(id.into(), true),
                "assistant" => self.user_messages.insert(id.into(), false),
                _ => None,
            };
        }
    }

    pub fn record_part(&mut self, props: &Value) {
        let part = props.get("part").unwrap_or(props);
        let kind = match part.get("type").and_then(Value::as_str) {
            Some("text") => StreamKind::AssistantText,
            Some("reasoning") => StreamKind::ReasoningText,
            _ => return,
        };
        if let (Some(message_id), Some(part_id)) = (
            part.get("messageID").and_then(Value::as_str),
            part.get("id").and_then(Value::as_str),
        ) {
            self.stream_kinds
                .insert((message_id.into(), part_id.into()), kind);
        }
    }

    pub fn is_user_part(&self, props: &Value) -> bool {
        let part = props.get("part").unwrap_or(props);
        part.get("messageID")
            .and_then(Value::as_str)
            .and_then(|id| self.user_messages.get(id))
            == Some(&true)
    }

    pub fn stream_kind(&self, props: &Value) -> Option<StreamKind> {
        let message_id = props.get("messageID")?.as_str()?;
        let part_id = props.get("partID")?.as_str()?;
        self.stream_kinds
            .get(&(message_id.into(), part_id.into()))
            .copied()
    }
}
