use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    Integer(i64),
}

impl std::fmt::Display for RequestId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::String(id) => f.write_str(id),
            Self::Integer(id) => write!(f, "{id}"),
        }
    }
}
impl From<String> for RequestId {
    fn from(value: String) -> Self {
        Self::String(value)
    }
}
impl From<&str> for RequestId {
    fn from(value: &str) -> Self {
        Self::String(value.to_owned())
    }
}
impl From<i64> for RequestId {
    fn from(value: i64) -> Self {
        Self::Integer(value)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RequestKind {
    CommandExecutionApproval,
    FileReadApproval,
    FileChangeApproval,
    ApplyPatchApproval,
    ExecCommandApproval,
    McpElicitationApproval,
    PermissionApproval,
    ToolUserInput,
    DynamicToolCall,
    AuthTokensRefresh,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ApprovalDecision {
    Accept,
    AcceptForSession,
    AcceptAlways,
    Decline,
    Cancel,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ElicitationAction {
    Accept,
    Decline,
    Cancel,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserInputOption {
    pub label: String,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    #[serde(default)]
    pub options: Vec<UserInputOption>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allow_custom_answer: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub initial_answer: Option<String>,
    #[serde(default)]
    pub multi_select: bool,
}

pub type UserInputAnswers = BTreeMap<String, Value>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeRequest {
    pub request_id: RequestId,
    pub thread_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    pub kind: RequestKind,
    #[serde(default)]
    pub questions: Vec<UserInputQuestion>,
    pub payload: Value,
    /// Whether a declining answer may carry feedback the provider passes to
    /// the agent that asked, instead of a fixed refusal.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub supports_feedback: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum RuntimeResponse {
    Approval {
        request_id: RequestId,
        decision: ApprovalDecision,
        updated_input: Option<Value>,
        /// What to tell the agent along with a decline, when the request
        /// supports feedback.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        feedback: Option<String>,
    },
    UserInput {
        request_id: RequestId,
        answers: UserInputAnswers,
    },
    Elicitation {
        request_id: RequestId,
        action: ElicitationAction,
        content: Option<Value>,
    },
    Native {
        request_id: RequestId,
        result: Value,
    },
}

impl RuntimeResponse {
    pub fn request_id(&self) -> &RequestId {
        match self {
            Self::Approval { request_id, .. }
            | Self::UserInput { request_id, .. }
            | Self::Elicitation { request_id, .. }
            | Self::Native { request_id, .. } => request_id,
        }
    }
}
