use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TextBlock {
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ThinkingBlock {
    pub thinking: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolUseBlock {
    pub id: String,
    pub name: String,
    pub input: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolResultBlock {
    #[serde(rename = "tool_use_id")]
    pub tool_use_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_error: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServerToolUseBlock {
    pub id: String,
    pub name: String,
    pub input: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServerToolResultBlock {
    #[serde(rename = "tool_use_id")]
    pub tool_use_id: String,
    pub content: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ContentBlock {
    Text(TextBlock),
    Thinking(ThinkingBlock),
    ToolUse(ToolUseBlock),
    ToolResult(ToolResultBlock),
    ServerToolUse(ServerToolUseBlock),
    ServerToolResult(ServerToolResultBlock),
    Unknown(Value),
}

impl ContentBlock {
    pub fn from_value(value: Value) -> Self {
        let kind = value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default();
        match kind {
            "text" => serde_json::from_value(value.clone())
                .map(Self::Text)
                .unwrap_or(Self::Unknown(value)),
            "thinking" => serde_json::from_value(value.clone())
                .map(Self::Thinking)
                .unwrap_or(Self::Unknown(value)),
            "tool_use" => serde_json::from_value(value.clone())
                .map(Self::ToolUse)
                .unwrap_or(Self::Unknown(value)),
            "tool_result" => serde_json::from_value(value.clone())
                .map(Self::ToolResult)
                .unwrap_or(Self::Unknown(value)),
            "server_tool_use" => serde_json::from_value(value.clone())
                .map(Self::ServerToolUse)
                .unwrap_or(Self::Unknown(value)),
            "server_tool_result" => serde_json::from_value(value.clone())
                .map(Self::ServerToolResult)
                .unwrap_or(Self::Unknown(value)),
            _ => Self::Unknown(value),
        }
    }

    pub fn to_value(&self) -> Value {
        match self {
            Self::Text(block) => tagged("text", block),
            Self::Thinking(block) => tagged("thinking", block),
            Self::ToolUse(block) => tagged("tool_use", block),
            Self::ToolResult(block) => tagged("tool_result", block),
            Self::ServerToolUse(block) => tagged("server_tool_use", block),
            Self::ServerToolResult(block) => tagged("server_tool_result", block),
            Self::Unknown(value) => value.clone(),
        }
    }
}

fn tagged<T: Serialize>(kind: &str, value: &T) -> Value {
    let mut object = match serde_json::to_value(value).unwrap_or(Value::Object(Map::new())) {
        Value::Object(object) => object,
        _ => Map::new(),
    };
    object.insert("type".into(), Value::String(kind.into()));
    Value::Object(object)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct UserMessage {
    pub content: Value,
    #[serde(default)]
    pub uuid: Option<String>,
    #[serde(default)]
    pub parent_tool_use_id: Option<String>,
    #[serde(default)]
    pub tool_use_result: Option<Value>,
    #[serde(default)]
    pub origin: Option<Value>,
    #[serde(skip)]
    pub raw: Value,
}

impl UserMessage {
    fn from_value(value: Value) -> Option<Self> {
        let message = value.get("message")?;
        Some(Self {
            content: message.get("content")?.clone(),
            uuid: value.get("uuid").and_then(Value::as_str).map(str::to_owned),
            parent_tool_use_id: value
                .get("parent_tool_use_id")
                .and_then(Value::as_str)
                .map(str::to_owned),
            tool_use_result: value.get("tool_use_result").cloned(),
            origin: value.get("origin").cloned(),
            raw: value,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AssistantMessage {
    pub content: Vec<ContentBlock>,
    pub model: String,
    pub parent_tool_use_id: Option<String>,
    pub error: Option<String>,
    pub usage: Option<Value>,
    pub message_id: Option<String>,
    pub stop_reason: Option<String>,
    pub session_id: Option<String>,
    pub uuid: Option<String>,
    pub raw: Value,
}

impl AssistantMessage {
    fn from_value(value: Value) -> Option<Self> {
        let message = value
            .get("message")
            .cloned()
            .unwrap_or_else(|| value.clone());
        let content = message
            .get("content")?
            .as_array()?
            .iter()
            .cloned()
            .map(ContentBlock::from_value)
            .collect();
        Some(Self {
            content,
            model: message
                .get("model")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .into(),
            parent_tool_use_id: value
                .get("parent_tool_use_id")
                .and_then(Value::as_str)
                .map(str::to_owned),
            // The CLI sets the error code on the envelope, beside `message`.
            error: value
                .get("error")
                .or_else(|| message.get("error"))
                .and_then(Value::as_str)
                .map(str::to_owned),
            usage: message.get("usage").cloned(),
            message_id: message.get("id").and_then(Value::as_str).map(str::to_owned),
            stop_reason: message
                .get("stop_reason")
                .and_then(Value::as_str)
                .map(str::to_owned),
            session_id: value
                .get("session_id")
                .and_then(Value::as_str)
                .map(str::to_owned),
            uuid: value.get("uuid").and_then(Value::as_str).map(str::to_owned),
            raw: value,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SystemMessage {
    pub subtype: String,
    #[serde(flatten)]
    pub data: BTreeMap<String, Value>,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeferredToolUse {
    pub id: String,
    pub name: String,
    pub input: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResultMessage {
    pub subtype: String,
    #[serde(default)]
    pub duration_ms: u64,
    #[serde(default)]
    pub duration_api_ms: u64,
    #[serde(default)]
    pub is_error: bool,
    #[serde(default)]
    pub num_turns: u32,
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub total_cost_usd: Option<f64>,
    #[serde(default)]
    pub usage: Option<Value>,
    #[serde(default)]
    pub result: Option<String>,
    #[serde(default)]
    pub structured_output: Option<Value>,
    #[serde(default)]
    #[serde(rename = "modelUsage")]
    pub model_usage: Option<Value>,
    #[serde(default)]
    pub permission_denials: Option<Vec<Value>>,
    #[serde(default)]
    pub deferred_tool_use: Option<DeferredToolUse>,
    #[serde(default)]
    pub errors: Option<Vec<String>>,
    #[serde(default)]
    pub api_error_status: Option<u16>,
    #[serde(default)]
    pub uuid: Option<String>,
    #[serde(default)]
    pub terminal_reason: Option<String>,
    #[serde(default)]
    pub origin: Option<Value>,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StreamEvent {
    pub uuid: String,
    pub session_id: String,
    pub event: Value,
    #[serde(default)]
    pub parent_tool_use_id: Option<String>,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RateLimitInfo {
    pub status: String,
    #[serde(rename = "resetsAt", default)]
    pub resets_at: Option<u64>,
    #[serde(rename = "rateLimitType", default)]
    pub rate_limit_type: Option<String>,
    #[serde(default)]
    pub utilization: Option<f64>,
    #[serde(rename = "overageStatus", default)]
    pub overage_status: Option<String>,
    #[serde(rename = "overageResetsAt", default)]
    pub overage_resets_at: Option<u64>,
    #[serde(rename = "overageDisabledReason", default)]
    pub overage_disabled_reason: Option<String>,
    #[serde(flatten)]
    pub raw: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RateLimitEvent {
    pub rate_limit_info: RateLimitInfo,
    pub uuid: String,
    pub session_id: String,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ConversationResetMessage {
    pub new_conversation_id: String,
    pub uuid: String,
    pub session_id: String,
    #[serde(skip)]
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq)]
// Keep ResultMessage inline so provider adapters can consume the typed value without unboxing.
#[allow(clippy::large_enum_variant)]
pub enum Message {
    User(UserMessage),
    Assistant(AssistantMessage),
    System(SystemMessage),
    Result(ResultMessage),
    StreamEvent(StreamEvent),
    RateLimit(RateLimitEvent),
    ConversationReset(ConversationResetMessage),
    Unknown(Value),
}

impl Message {
    pub fn from_value(value: Value) -> Self {
        match value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
        {
            "user" => UserMessage::from_value(value.clone())
                .map(Self::User)
                .unwrap_or(Self::Unknown(value)),
            "assistant" => AssistantMessage::from_value(value.clone())
                .map(Self::Assistant)
                .unwrap_or(Self::Unknown(value)),
            "system" => serde_json::from_value::<SystemMessage>(value.clone())
                .ok()
                .map(|mut message| {
                    message.raw = value.clone();
                    Self::System(message)
                })
                .unwrap_or(Self::Unknown(value)),
            "result" => serde_json::from_value::<ResultMessage>(value.clone())
                .ok()
                .map(|mut message| {
                    message.raw = value.clone();
                    Self::Result(message)
                })
                .unwrap_or(Self::Unknown(value)),
            "stream_event" => serde_json::from_value::<StreamEvent>(value.clone())
                .ok()
                .map(|mut message| {
                    message.raw = value.clone();
                    Self::StreamEvent(message)
                })
                .unwrap_or(Self::Unknown(value)),
            "rate_limit_event" => serde_json::from_value::<RateLimitEvent>(value.clone())
                .ok()
                .map(|mut message| {
                    message.raw = value.clone();
                    Self::RateLimit(message)
                })
                .unwrap_or(Self::Unknown(value)),
            "conversation_reset" => {
                serde_json::from_value::<ConversationResetMessage>(value.clone())
                    .ok()
                    .map(|mut message| {
                        message.raw = value.clone();
                        Self::ConversationReset(message)
                    })
                    .unwrap_or(Self::Unknown(value))
            }
            _ => Self::Unknown(value),
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::User(_) => "user",
            Self::Assistant(_) => "assistant",
            Self::System(_) => "system",
            Self::Result(_) => "result",
            Self::StreamEvent(_) => "stream_event",
            Self::RateLimit(_) => "rate_limit_event",
            Self::ConversationReset(_) => "conversation_reset",
            Self::Unknown(_) => "unknown",
        }
    }

    pub fn raw(&self) -> &Value {
        match self {
            Self::User(message) => &message.raw,
            Self::Assistant(message) => &message.raw,
            Self::System(message) => &message.raw,
            Self::Result(message) => &message.raw,
            Self::StreamEvent(message) => &message.raw,
            Self::RateLimit(message) => &message.raw,
            Self::ConversationReset(message) => &message.raw,
            Self::Unknown(value) => value,
        }
    }

    pub fn is_terminal_result(&self) -> bool {
        matches!(self, Self::Result(_))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct UserPrompt {
    pub content: Value,
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub parent_tool_use_id: Option<String>,
    #[serde(default)]
    pub uuid: Option<String>,
    #[serde(default)]
    pub origin: Option<Value>,
}

impl UserPrompt {
    pub fn text(prompt: impl Into<String>) -> Self {
        Self {
            content: Value::String(prompt.into()),
            session_id: String::new(),
            parent_tool_use_id: None,
            uuid: None,
            origin: None,
        }
    }

    pub fn to_wire(&self, verbatim: bool) -> Value {
        let mut message = Map::new();
        message.insert("role".into(), Value::String("user".into()));
        message.insert("content".into(), self.content.clone());
        let mut wire = Map::new();
        wire.insert("type".into(), Value::String("user".into()));
        wire.insert("session_id".into(), Value::String(self.session_id.clone()));
        wire.insert("message".into(), Value::Object(message));
        wire.insert(
            "parent_tool_use_id".into(),
            self.parent_tool_use_id
                .clone()
                .map(Value::String)
                .unwrap_or(Value::Null),
        );
        if let Some(uuid) = &self.uuid {
            wire.insert("uuid".into(), Value::String(uuid.clone()));
        }
        if let Some(origin) = &self.origin {
            wire.insert("origin".into(), origin.clone());
        }
        if verbatim {
            wire.insert("client_composed".into(), Value::Bool(true));
        }
        Value::Object(wire)
    }
}
