use alera_core::runtime::{
    ChatOrchestrationNewWorkspace, ChatOrchestrationNotify, ChatOrchestrationTarget,
    ChatOrchestrationTaskStatus,
};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum WaitUntil {
    All,
    Any,
}

impl WaitUntil {
    pub(crate) fn parse(value: Option<&Value>) -> HostResult<Self> {
        match value.and_then(Value::as_str).unwrap_or("all") {
            "all" => Ok(Self::All),
            "any" => Ok(Self::Any),
            other => Err(HostError::format(format!(
                "until must be all or any, got {other}"
            ))),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct AgentChoice {
    pub provider_instance_id: Option<String>,
    pub model: Option<String>,
    pub options: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct NewWorkspaceTarget {
    pub spec: ChatOrchestrationNewWorkspace,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum ParsedTarget {
    Chat { chat_id: String },
    Workspace { workspace_id: String },
    NewWorkspace(NewWorkspaceTarget),
}

impl ParsedTarget {
    pub(crate) fn store_target(&self) -> ChatOrchestrationTarget {
        match self {
            Self::Chat { chat_id } => ChatOrchestrationTarget::Chat {
                chat_id: chat_id.clone(),
            },
            Self::Workspace { workspace_id } => ChatOrchestrationTarget::Workspace {
                workspace_id: workspace_id.clone(),
            },
            Self::NewWorkspace(target) => {
                ChatOrchestrationTarget::NewWorkspace(target.spec.clone())
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct DelegateInput {
    pub task: String,
    pub parent_chat_id: Option<String>,
    pub title: Option<String>,
    pub role: Option<String>,
    pub notify: ChatOrchestrationNotify,
    pub mode: DelegateMode,
    pub wait_seconds: u64,
    pub agent: AgentChoice,
    pub runtime_mode: Option<String>,
    pub interaction_mode: Option<String>,
    pub target: ParsedTarget,
    pub request_id: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DelegateMode {
    Async,
    Wait,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct SendInput {
    pub parent_chat_id: Option<String>,
    pub chat_id: String,
    pub message: String,
    pub delivery: String,
    pub expect_reply: bool,
    pub request_id: String,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ListInput {
    pub parent_chat_id: Option<String>,
    pub child_chat_id: Option<String>,
    pub root_task_id: Option<String>,
    pub workspace_id: Option<String>,
    pub project_id: Option<String>,
    pub host_id: Option<String>,
    pub statuses: Vec<ChatOrchestrationTaskStatus>,
    pub attention: Option<bool>,
    pub limit: Option<i64>,
    pub cursor: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WaitInput {
    pub task_ids: Vec<String>,
    pub wait_seconds: u64,
    pub until: WaitUntil,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum OrchestrationRequest {
    Capabilities {
        workspace_id: Option<String>,
        host_id: Option<String>,
    },
    Delegate(Box<DelegateInput>),
    Send(SendInput),
    Task {
        task_id: String,
        acknowledge: bool,
        request_id: Option<String>,
    },
    TasksList(ListInput),
    Wait(WaitInput),
    Cancel {
        task_id: String,
        request_id: String,
        reason: Option<String>,
    },
    Interrupt {
        chat_id: String,
        turn_id: Option<String>,
        request_id: String,
    },
    Requests {
        task_id: Option<String>,
        chat_id: Option<String>,
    },
    Respond {
        chat_id: String,
        runtime_request_id: String,
        response: Value,
        request_id: String,
    },
    Configure {
        chat_id: String,
        request_id: String,
        provider: Option<String>,
        provider_instance_id: Option<String>,
        model: Option<Option<String>>,
        reasoning_effort: Option<Option<String>>,
        runtime_mode: Option<String>,
        interaction_mode: Option<String>,
    },
    Read {
        chat_id: String,
        limit: usize,
    },
    ListChats {
        workspace_id: Option<String>,
        project_id: Option<String>,
        host_id: Option<String>,
        include_archived: bool,
    },
}
