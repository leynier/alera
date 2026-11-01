//! MCP elicitations the CLI forwards as `control_request` `elicitation`
//! frames, answered by an [ElicitationCallback]. Without a callback the
//! client declines, as the TypeScript SDK does without `onElicitation`.

use crate::types::ControlRequestContext;
use crate::Result;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

/// What an MCP server asks the user for.
#[derive(Debug, Clone, PartialEq)]
pub struct ElicitationRequest {
    pub server_name: String,
    pub message: String,
    /// `form` or `url`, when the CLI says.
    pub mode: Option<String>,
    pub url: Option<String>,
    pub elicitation_id: Option<String>,
    /// The JSON schema of a form, when it is an object.
    pub requested_schema: Option<Value>,
    pub title: Option<String>,
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub control: ControlRequestContext,
}

impl ElicitationRequest {
    pub(crate) fn from_control(request_id: &str, envelope: &Value, request: &Value) -> Self {
        let text = |key: &str| request.get(key).and_then(Value::as_str).map(str::to_owned);
        Self {
            server_name: text("mcp_server_name").unwrap_or_default(),
            message: text("message").unwrap_or_default(),
            mode: text("mode"),
            url: text("url"),
            elicitation_id: text("elicitation_id"),
            requested_schema: request
                .get("requested_schema")
                .filter(|schema| schema.is_object())
                .cloned(),
            title: text("title"),
            display_name: text("display_name"),
            description: text("description"),
            control: ControlRequestContext::from_envelope(request_id, envelope),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ElicitationAction {
    Accept,
    Decline,
    Cancel,
}

/// The answer written back to the CLI.
#[derive(Debug, Clone, PartialEq)]
pub struct ElicitationResult {
    pub action: ElicitationAction,
    pub content: Option<Map<String, Value>>,
}

impl ElicitationResult {
    pub fn accept(content: Option<Map<String, Value>>) -> Self {
        Self {
            action: ElicitationAction::Accept,
            content,
        }
    }

    pub fn decline() -> Self {
        Self {
            action: ElicitationAction::Decline,
            content: None,
        }
    }

    pub fn cancel() -> Self {
        Self {
            action: ElicitationAction::Cancel,
            content: None,
        }
    }

    /// `{action}`, plus `content` for an accept that has some.
    pub fn to_wire(&self) -> Value {
        let mut wire = json!({ "action": self.action });
        if self.action == ElicitationAction::Accept {
            if let Some(content) = &self.content {
                wire["content"] = Value::Object(content.clone());
            }
        }
        wire
    }
}

pub type ElicitationFuture = Pin<Box<dyn Future<Output = Result<ElicitationResult>> + Send>>;
pub type ElicitationCallback = Arc<dyn Fn(ElicitationRequest) -> ElicitationFuture + Send + Sync>;
