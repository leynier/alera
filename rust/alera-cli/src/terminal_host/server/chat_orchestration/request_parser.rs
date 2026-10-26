use alera_core::runtime::{
    ChatOrchestrationNewWorkspace, ChatOrchestrationNotify, ChatOrchestrationSetupMode,
    ChatOrchestrationTaskStatus, ChatOrchestrationWorkspaceMode,
};
use serde_json::{json, Value};

use super::models::*;
use super::MAX_WAIT_SECONDS;
use crate::terminal_host::host_error::{HostError, HostResult};

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

/// The most background tasks one `backgroundWait` names.
pub(crate) const MAX_BACKGROUND_TASK_IDS: usize = 20;

fn request_id(payload: &Value) -> HostResult<String> {
    required_string(payload, "requestId")
}

/// The ids of background tasks the agent saw: 1 to 20 nonempty strings.
fn parse_background_task_ids(payload: &Value) -> HostResult<Vec<String>> {
    let values = payload
        .get("taskIds")
        .and_then(Value::as_array)
        .ok_or_else(|| HostError::format("taskIds must be an array"))?;
    if values.is_empty() || values.len() > MAX_BACKGROUND_TASK_IDS {
        return Err(HostError::format(format!(
            "taskIds must hold 1 to {MAX_BACKGROUND_TASK_IDS} task ids"
        )));
    }
    values
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(str::trim)
                .filter(|id| !id.is_empty())
                .map(str::to_owned)
                .ok_or_else(|| HostError::format("taskIds entries must be nonempty strings"))
        })
        .collect()
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
                Ok(Self::Delegate(Box::new(DelegateInput {
                    task: required_string(payload, "task")?,
                    parent_chat_id: optional_string(payload, "parentChatId")?,
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
                })))
            }
            "send" => Ok(Self::Send(SendInput {
                parent_chat_id: optional_string(payload, "parentChatId")?,
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
            "task" => {
                let acknowledge = payload
                    .get("acknowledge")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                Ok(Self::Task {
                    task_id: required_string(payload, "taskId")?,
                    acknowledge,
                    request_id: if acknowledge && payload.get("requestId").is_some() {
                        Some(request_id(payload)?)
                    } else {
                        None
                    },
                })
            }
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
            "backgroundWait" => Ok(Self::BackgroundWait {
                task_ids: parse_background_task_ids(payload)?,
                waiting: match payload.get("waiting") {
                    None | Some(Value::Null) => true,
                    Some(Value::Bool(waiting)) => *waiting,
                    Some(_) => return Err(HostError::format("waiting must be a boolean")),
                },
                request_id: request_id(payload)?,
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
                model: optional_reset_string(payload, "model")?,
                reasoning_effort: optional_reset_string(payload, "reasoningEffort")?,
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
            "transfers" => Ok(Self::Transfers {
                chat_id: optional_string(payload, "chatId")?,
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

fn optional_reset_string(payload: &Value, key: &str) -> HostResult<Option<Option<String>>> {
    match payload.get(key) {
        None => Ok(None),
        Some(Value::Null) => Ok(Some(None)),
        Some(Value::String(value)) => Ok(Some(Some(value.trim().to_owned()))),
        Some(_) => Err(HostError::format(format!("{key} must be a string or null"))),
    }
}
