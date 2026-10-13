use alera_core::runtime::{
    ChatOrchestrationNewWorkspace, ChatOrchestrationNotify, ChatOrchestrationSetupMode,
    ChatOrchestrationTarget, ChatOrchestrationTaskStatus, ChatOrchestrationWorkspaceMode,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::MAX_WAIT_SECONDS;

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
    Delegate(DelegateInput),
    Send(SendInput),
    Task {
        task_id: String,
        acknowledge: bool,
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

fn required_string(payload: &Value, key: &str) -> HostResult<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| HostError::format(format!("{key} is required")))
}

fn optional_string(payload: &Value, key: &str) -> HostResult<Option<String>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => {
            Ok((!value.trim().is_empty()).then(|| value.trim().to_owned()))
        }
        Some(_) => Err(HostError::format(format!("{key} must be a string"))),
    }
}

fn request_id(payload: &Value) -> HostResult<String> {
    required_string(payload, "requestId")
}

fn parse_notify(payload: &Value, mode: DelegateMode) -> HostResult<ChatOrchestrationNotify> {
    let default = match mode {
        DelegateMode::Async => ChatOrchestrationNotify::Always,
        DelegateMode::Wait => ChatOrchestrationNotify::SettledOnly,
    };
    match payload.get("notify").and_then(Value::as_str) {
        None => Ok(default),
        Some(value) => ChatOrchestrationNotify::parse(value)
            .ok_or_else(|| HostError::format(format!("unknown notify value {value}"))),
    }
}

fn parse_wait_seconds(payload: &Value, default: u64) -> HostResult<u64> {
    let value = match payload.get("waitSeconds") {
        None => default,
        Some(value) => value
            .as_u64()
            .ok_or_else(|| HostError::format("waitSeconds must be a non-negative integer"))?,
    };
    if value > MAX_WAIT_SECONDS {
        return Err(HostError::format(format!(
            "waitSeconds cannot exceed {MAX_WAIT_SECONDS}"
        )));
    }
    Ok(value)
}

fn parse_mode(payload: &Value) -> HostResult<DelegateMode> {
    match payload
        .get("mode")
        .and_then(Value::as_str)
        .unwrap_or("async")
    {
        "async" => Ok(DelegateMode::Async),
        "wait" => Ok(DelegateMode::Wait),
        value => Err(HostError::format(format!(
            "mode must be async or wait, got {value}"
        ))),
    }
}

fn parse_agent(payload: &Value) -> HostResult<AgentChoice> {
    let Some(agent) = payload.get("agent") else {
        return Ok(AgentChoice {
            provider_instance_id: None,
            model: None,
            options: None,
        });
    };
    if !agent.is_object() {
        return Err(HostError::format("agent must be an object"));
    }
    Ok(AgentChoice {
        provider_instance_id: optional_string(agent, "providerInstanceId")?,
        model: optional_string(agent, "model")?,
        options: agent.get("options").cloned(),
    })
}

fn parse_target(payload: &Value) -> HostResult<ParsedTarget> {
    let target = payload
        .get("target")
        .ok_or_else(|| HostError::format("target is required"))?;
    let object = target
        .as_object()
        .ok_or_else(|| HostError::format("target must be an object"))?;
    if object.len() != 1 {
        return Err(HostError::conflict(
            "invalid_target",
            "target must contain exactly one destination",
            json!({}),
        ));
    }
    if let Some(chat) = object.get("chat") {
        return Ok(ParsedTarget::Chat {
            chat_id: required_string(chat, "chatId")?,
        });
    }
    if let Some(workspace) = object.get("workspace") {
        return Ok(ParsedTarget::Workspace {
            workspace_id: required_string(workspace, "workspaceId")?,
        });
    }
    if let Some(workspace) = object.get("newWorkspace") {
        let project_id = required_string(workspace, "projectId")?;
        let host_id = required_string(workspace, "hostId")?;
        if host_id.trim().is_empty() {
            return Err(HostError::conflict(
                "invalid_target",
                "hostId is invalid",
                json!({}),
            ));
        }
        let mode = match workspace
            .get("mode")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::format("newWorkspace.mode is required"))?
        {
            "worktree" => ChatOrchestrationWorkspaceMode::Worktree,
            "shared" => ChatOrchestrationWorkspaceMode::Shared,
            value => return Err(HostError::format(format!("unknown workspace mode {value}"))),
        };
        let setup = match workspace
            .get("setup")
            .and_then(Value::as_str)
            .unwrap_or("inline")
        {
            "inline" => ChatOrchestrationSetupMode::Inline,
            "deferred" => ChatOrchestrationSetupMode::Deferred,
            value => return Err(HostError::format(format!("unknown setup mode {value}"))),
        };
        return Ok(ParsedTarget::NewWorkspace(NewWorkspaceTarget {
            spec: ChatOrchestrationNewWorkspace {
                project_id,
                host_id,
                mode,
                branch: optional_string(workspace, "branch")?,
                source_branch: optional_string(workspace, "sourceBranch")?,
                reuse_existing_branch: workspace
                    .get("reuseExistingBranch")
                    .and_then(Value::as_bool),
                name: optional_string(workspace, "name")?,
                parent_workspace_id: optional_string(workspace, "parentWorkspaceId")?,
                setup,
            },
        }));
    }
    Err(HostError::conflict(
        "invalid_target",
        "unknown target kind",
        json!({}),
    ))
}

fn parse_statuses(payload: &Value) -> HostResult<Vec<ChatOrchestrationTaskStatus>> {
    let Some(values) = payload.get("statuses") else {
        return Ok(Vec::new());
    };
    let values = values
        .as_array()
        .ok_or_else(|| HostError::format("statuses must be an array"))?;
    values
        .iter()
        .map(|value| {
            let status = value
                .as_str()
                .ok_or_else(|| HostError::format("statuses entries must be strings"))?;
            ChatOrchestrationTaskStatus::parse(status)
                .ok_or_else(|| HostError::format(format!("unknown task status {status}")))
        })
        .collect()
}

impl OrchestrationRequest {
    pub(crate) fn parse(verb: &str, payload: &Value) -> HostResult<Self> {
        match verb {
            "capabilities" => Ok(Self::Capabilities {
                workspace_id: optional_string(payload, "workspaceId")?,
                host_id: optional_string(payload, "hostId")?,
            }),
            "delegate" => {
                let mode = parse_mode(payload)?;
                Ok(Self::Delegate(DelegateInput {
                    task: required_string(payload, "task")?,
                    title: optional_string(payload, "title")?,
                    role: optional_string(payload, "role")?,
                    notify: parse_notify(payload, mode)?,
                    mode,
                    wait_seconds: parse_wait_seconds(
                        payload,
                        if mode == DelegateMode::Wait {
                            MAX_WAIT_SECONDS
                        } else {
                            0
                        },
                    )?,
                    agent: parse_agent(payload)?,
                    runtime_mode: optional_string(payload, "runtimeMode")?,
                    interaction_mode: optional_string(payload, "interactionMode")?,
                    target: parse_target(payload)?,
                    request_id: request_id(payload)?,
                }))
            }
            "send" => Ok(Self::Send(SendInput {
                chat_id: required_string(payload, "chatId")?,
                message: required_string(payload, "message")?,
                delivery: payload
                    .get("delivery")
                    .and_then(Value::as_str)
                    .unwrap_or("auto")
                    .to_owned(),
                expect_reply: payload
                    .get("expectReply")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                request_id: request_id(payload)?,
            })),
            "task" => Ok(Self::Task {
                task_id: required_string(payload, "taskId")?,
                acknowledge: payload
                    .get("acknowledge")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            }),
            "tasks.list" => Ok(Self::TasksList(ListInput {
                parent_chat_id: optional_string(payload, "parentChatId")?,
                child_chat_id: optional_string(payload, "childChatId")?,
                root_task_id: optional_string(payload, "rootTaskId")?,
                workspace_id: optional_string(payload, "workspaceId")?,
                project_id: optional_string(payload, "projectId")?,
                host_id: optional_string(payload, "hostId")?,
                statuses: parse_statuses(payload)?,
                attention: payload.get("attention").and_then(Value::as_bool),
                limit: payload.get("limit").and_then(Value::as_i64),
                cursor: payload.get("cursor").and_then(Value::as_i64),
            })),
            "wait" => {
                let values = payload
                    .get("taskIds")
                    .and_then(Value::as_array)
                    .ok_or_else(|| HostError::format("taskIds must be an array"))?;
                let task_ids = values
                    .iter()
                    .map(|value| {
                        value
                            .as_str()
                            .map(ToOwned::to_owned)
                            .ok_or_else(|| HostError::format("taskIds entries must be strings"))
                    })
                    .collect::<HostResult<Vec<_>>>()?;
                if task_ids.is_empty() {
                    return Err(HostError::format("taskIds must not be empty"));
                }
                Ok(Self::Wait(WaitInput {
                    task_ids,
                    wait_seconds: parse_wait_seconds(payload, MAX_WAIT_SECONDS)?,
                    until: WaitUntil::parse(payload.get("until"))?,
                }))
            }
            "cancel" => Ok(Self::Cancel {
                task_id: required_string(payload, "taskId")?,
                request_id: request_id(payload)?,
                reason: optional_string(payload, "reason")?,
            }),
            "interrupt" => Ok(Self::Interrupt {
                chat_id: required_string(payload, "chatId")?,
                turn_id: optional_string(payload, "turnId")?,
                request_id: request_id(payload)?,
            }),
            "requests" => Ok(Self::Requests {
                task_id: optional_string(payload, "taskId")?,
                chat_id: optional_string(payload, "chatId")?,
            }),
            "respond" => Ok(Self::Respond {
                chat_id: required_string(payload, "chatId")?,
                runtime_request_id: required_string(payload, "runtimeRequestId")?,
                response: payload
                    .get("response")
                    .cloned()
                    .ok_or_else(|| HostError::format("response is required"))?,
                request_id: request_id(payload)?,
            }),
            "configure" => Ok(Self::Configure {
                chat_id: required_string(payload, "chatId")?,
                request_id: request_id(payload)?,
                provider: optional_string(payload, "provider")?,
                provider_instance_id: optional_string(payload, "providerInstanceId")?,
                model: match payload.get("model") {
                    None => None,
                    Some(Value::Null) => Some(None),
                    Some(Value::String(value)) => Some(Some(value.trim().to_owned())),
                    Some(_) => return Err(HostError::format("model must be a string or null")),
                },
                runtime_mode: optional_string(payload, "runtimeMode")?,
                interaction_mode: optional_string(payload, "interactionMode")?,
            }),
            "read" => Ok(Self::Read {
                chat_id: required_string(payload, "chatId")?,
                limit: payload
                    .get("limit")
                    .and_then(Value::as_u64)
                    .unwrap_or(100)
                    .clamp(1, 200) as usize,
            }),
            "list" => Ok(Self::ListChats {
                workspace_id: optional_string(payload, "workspaceId")?,
                project_id: optional_string(payload, "projectId")?,
                host_id: optional_string(payload, "hostId")?,
                include_archived: payload
                    .get("includeArchived")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            }),
            other => Err(HostError::format(format!(
                "unknown chat orchestration verb {other}"
            ))),
        }
    }
}
