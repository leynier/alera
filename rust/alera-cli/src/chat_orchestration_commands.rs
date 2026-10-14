//! CLI clients for chat-to-chat orchestration.
//!
//! This group is intentionally separate from the terminal orchestration
//! group. Every operation goes through the chat runtime host so receipts,
//! lineage, workspace routing, and mode ceilings stay in one implementation.

use std::io::Read;

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::chat_orchestration_commands_args::{
    ChatAction, ChatCancelArgs, ChatCommand, ChatConfigureArgs, ChatDelegateArgs,
    ChatInterruptArgs, ChatListArgs, ChatReadArgs, ChatRequestsArgs, ChatRespondArgs, ChatSendArgs,
    ChatTaskArgs, ChatTaskListArgs, ChatWaitArgs,
};
use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::WAIT_CLIENT_GRACE_MS;

pub(crate) const CHAT_ORCHESTRATION_CAPABILITY: &str = "chatOrchestrationV1";
const MAX_WAIT_SECONDS: u64 = 50;

pub(crate) async fn run(command: ChatCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    let action = command.action;
    let result = match action {
        ChatAction::Human(args) => crate::chat_task_commands::run(&runtime, args).await,
        ChatAction::Capabilities => {
            request(&runtime, "chatOrchestration.capabilities", json!({})).await
        }
        ChatAction::List(args) => list(&runtime, args).await,
        ChatAction::Read(args) => read(&runtime, args).await,
        ChatAction::Delegate(args) => delegate(&runtime, *args).await,
        ChatAction::Send(args) => send(&runtime, args).await,
        ChatAction::Task(args) => task(&runtime, args).await,
        ChatAction::TaskList(args) => task_list(&runtime, args).await,
        ChatAction::Wait(args) => wait(&runtime, args).await,
        ChatAction::Cancel(args) => cancel(&runtime, args).await,
        ChatAction::Interrupt(args) => interrupt(&runtime, args).await,
        ChatAction::Requests(args) => requests(&runtime, args).await,
        ChatAction::Respond(args) => respond(&runtime, args).await,
        ChatAction::Configure(args) => configure(&runtime, args).await,
    };
    match result {
        Ok(value) => {
            crate::print_value(&value, json_output, "chat orchestration request completed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn request(runtime: &RuntimeDirArgs, verb: &str, payload: Value) -> Result<Value> {
    crate::chat_orchestration_request::request(runtime, verb, payload, None).await
}

async fn request_with_deadline(
    runtime: &RuntimeDirArgs,
    verb: &str,
    payload: Value,
    deadline_ms: u64,
) -> Result<Value> {
    crate::chat_orchestration_request::request(runtime, verb, payload, Some(deadline_ms)).await
}

async fn list(runtime: &RuntimeDirArgs, args: ChatListArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.list",
        json!({
            "workspaceId": optional_text(args.workspace_id, "workspace-id")?,
            "projectId": optional_text(args.project_id, "project-id")?,
            "hostId": optional_text(args.host_id, "host-id")?,
            "includeArchived": args.include_archived,
        }),
    )
    .await
}

async fn read(runtime: &RuntimeDirArgs, args: ChatReadArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.read",
        json!({
            "chatId": require_text(&args.chat_id, "chat-id")?,
            "limit": args.limit,
        }),
    )
    .await
}

async fn delegate(runtime: &RuntimeDirArgs, args: ChatDelegateArgs) -> Result<Value> {
    let deadline_ms = (args.mode == "wait").then(|| {
        args.wait_seconds
            .min(MAX_WAIT_SECONDS)
            .saturating_mul(1_000)
            .saturating_add(WAIT_CLIENT_GRACE_MS)
    });
    let payload = delegate_payload(args)?;
    match deadline_ms {
        Some(deadline_ms) => {
            request_with_deadline(runtime, "chatOrchestration.delegate", payload, deadline_ms).await
        }
        None => request(runtime, "chatOrchestration.delegate", payload).await,
    }
}

fn delegate_payload(args: ChatDelegateArgs) -> Result<Value> {
    let task = read_text_source(
        args.source.task,
        args.source.task_file.as_deref(),
        args.source.task_stdin,
        "task",
    )?;
    let target = parse_target(&args.target)?;
    let agent = args
        .agent
        .as_deref()
        .map(|value| parse_object(value, "agent"))
        .transpose()?;
    let request_id = request_id(args.request_id)?;
    let mut payload = json!({
        "requestId": request_id,
        "task": task,
        "title": args.title,
        "role": args.role,
        "notify": args.notify,
        "mode": args.mode,
        "waitSeconds": args.wait_seconds.min(MAX_WAIT_SECONDS),
        "runtimeMode": args.runtime_mode,
        "interactionMode": args.interaction_mode,
        "target": target,
    });
    if let Some(agent) = agent {
        payload["agent"] = agent;
    }
    if let Some(parent) = optional_text(args.parent_chat_id, "parent-chat-id")? {
        payload["parentChatId"] = json!(parent);
    }
    Ok(payload)
}

async fn send(runtime: &RuntimeDirArgs, args: ChatSendArgs) -> Result<Value> {
    let message = read_text_source(
        args.source.message,
        args.source.message_file.as_deref(),
        args.source.message_stdin,
        "message",
    )?;
    let request_id = request_id(args.request_id)?;
    let mut payload = json!({
        "requestId": request_id.clone(),
        "clientMessageId": request_id,
        "chatId": require_text(&args.chat_id, "chat-id")?,
        "message": message,
        "delivery": args.delivery,
        "expectReply": args.expect_reply,
    });
    if let Some(parent) = optional_text(args.parent_chat_id, "parent-chat-id")? {
        payload["parentChatId"] = json!(parent);
    }
    request(runtime, "chatOrchestration.send", payload).await
}

async fn task_list(runtime: &RuntimeDirArgs, args: ChatTaskListArgs) -> Result<Value> {
    let statuses = args
        .statuses
        .into_iter()
        .map(|status| require_text(&status, "status"))
        .collect::<Result<Vec<_>>>()?;
    request(
        runtime,
        "chatOrchestration.tasks.list",
        json!({
            "parentChatId": optional_text(args.parent_chat_id, "parent-chat-id")?,
            "childChatId": optional_text(args.child_chat_id, "child-chat-id")?,
            "rootTaskId": optional_text(args.root_task_id, "root-task-id")?,
            "projectId": optional_text(args.project_id, "project-id")?,
            "workspaceId": optional_text(args.workspace_id, "workspace-id")?,
            "hostId": optional_text(args.host_id, "host-id")?,
            "statuses": statuses,
            "attention": args.attention,
            "limit": args.limit,
            "cursor": args.cursor,
        }),
    )
    .await
}

async fn task(runtime: &RuntimeDirArgs, args: ChatTaskArgs) -> Result<Value> {
    request(runtime, "chatOrchestration.task", task_payload(args)?).await
}

fn task_payload(args: ChatTaskArgs) -> Result<Value> {
    let mut payload =
        json!({"taskId":require_text(&args.task_id,"task-id")?,"acknowledge":args.acknowledge});
    if let Some(id) = optional_text(args.request_id, "request-id")? {
        if !args.acknowledge {
            bail!("request-id requires acknowledge");
        }
        payload["requestId"] = json!(id);
    }
    Ok(payload)
}

async fn wait(runtime: &RuntimeDirArgs, args: ChatWaitArgs) -> Result<Value> {
    let task_ids = args
        .task_ids
        .iter()
        .map(|task_id| require_text(task_id, "task-id"))
        .collect::<Result<Vec<_>>>()?;
    request_with_deadline(
        runtime,
        "chatOrchestration.wait",
        json!({
            "taskIds": task_ids,
            "waitSeconds": args.timeout_seconds,
            "until": args.until,
        }),
        args.timeout_seconds
            .saturating_mul(1_000)
            .saturating_add(WAIT_CLIENT_GRACE_MS),
    )
    .await
}

async fn requests(runtime: &RuntimeDirArgs, args: ChatRequestsArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.requests",
        json!({
            "chatId": optional_text(args.chat_id, "chat-id")?,
            "taskId": optional_text(args.task_id, "task-id")?,
        }),
    )
    .await
}

async fn cancel(runtime: &RuntimeDirArgs, args: ChatCancelArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.cancel",
        json!({
            "requestId": request_id(args.request_id)?,
            "taskId": require_text(&args.task_id, "task-id")?,
            "reason": optional_text(args.reason, "reason")?,
        }),
    )
    .await
}

async fn interrupt(runtime: &RuntimeDirArgs, args: ChatInterruptArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.interrupt",
        json!({
            "requestId": request_id(args.request_id)?,
            "chatId": require_text(&args.chat_id, "chat-id")?,
            "turnId": optional_text(args.turn_id, "turn-id")?,
        }),
    )
    .await
}

async fn respond(runtime: &RuntimeDirArgs, args: ChatRespondArgs) -> Result<Value> {
    let response = read_json_source(
        args.response,
        args.response_file.as_deref(),
        args.response_stdin,
        "response",
    )?;
    validate_response(&response)?;
    request(
        runtime,
        "chatOrchestration.respond",
        json!({
            "requestId": request_id(args.request_id)?,
            "chatId": require_text(&args.chat_id, "chat-id")?,
            "runtimeRequestId": require_text(&args.runtime_request_id, "runtime-request-id")?,
            "response": response,
        }),
    )
    .await
}

async fn configure(runtime: &RuntimeDirArgs, args: ChatConfigureArgs) -> Result<Value> {
    let payload = configure_payload(args)?;
    request(runtime, "chatOrchestration.configure", payload).await
}

fn configure_payload(args: ChatConfigureArgs) -> Result<Value> {
    if args.provider.is_none()
        && args.provider_instance_id.is_none()
        && args.model.is_none()
        && !args.reset_model
        && args.reasoning_effort.is_none()
        && !args.reset_reasoning_effort
        && args.runtime_mode.is_none()
        && args.interaction_mode.is_none()
    {
        bail!("at least one configuration field is required");
    }
    let mut payload = json!({
        "requestId": request_id(args.request_id)?,
        "chatId": require_text(&args.chat_id, "chat-id")?,
        "provider": optional_text(args.provider, "provider")?,
        "providerInstanceId": optional_text(args.provider_instance_id, "provider-instance-id")?,
        "runtimeMode": optional_text(args.runtime_mode, "runtime-mode")?,
        "interactionMode": optional_text(args.interaction_mode, "interaction-mode")?,
    });
    if args.reset_model {
        payload["model"] = Value::Null;
    } else if let Some(model) = optional_text(args.model, "model")? {
        payload["model"] = json!(model);
    }
    if args.reset_reasoning_effort {
        payload["reasoningEffort"] = Value::Null;
    } else if let Some(effort) = optional_text(args.reasoning_effort, "reasoning-effort")? {
        payload["reasoningEffort"] = json!(effort);
    }
    Ok(payload)
}

fn parse_target(raw: &str) -> Result<Value> {
    let value = parse_object(raw, "target")?;
    let object = value.as_object().expect("parse_object returns an object");
    let keys = ["chat", "workspace", "newWorkspace"];
    let present = keys
        .iter()
        .filter(|key| object.get(**key).is_some())
        .count();
    if present != 1 || object.len() != 1 {
        bail!("target must contain exactly one of chat, workspace, or newWorkspace");
    }
    if let Some(chat) = object.get("chat") {
        require_nested_id(chat, "chatId", "target.chat")?;
    }
    if let Some(workspace) = object.get("workspace") {
        require_nested_id(workspace, "workspaceId", "target.workspace")?;
    }
    if let Some(workspace) = object.get("newWorkspace") {
        let object = workspace
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("target.newWorkspace must be an object"))?;
        require_nested_id(workspace, "projectId", "target.newWorkspace")?;
        require_nested_id(workspace, "hostId", "target.newWorkspace")?;
        match object.get("mode").and_then(Value::as_str) {
            Some("worktree") | Some("shared") => {}
            _ => bail!("target.newWorkspace.mode must be worktree or shared"),
        }
        if let Some(setup) = object.get("setup").and_then(Value::as_str) {
            if !matches!(setup, "inline" | "deferred") {
                bail!("target.newWorkspace.setup must be inline or deferred");
            }
        }
    }
    Ok(value)
}

pub(crate) fn validate_response(response: &Value) -> Result<()> {
    let object = response
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("response must be a JSON object"))?;
    let kind = object
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("response.type is required"))?;
    match kind {
        "approval" => match object.get("decision").and_then(Value::as_str) {
            Some("accept")
            | Some("acceptForSession")
            | Some("acceptAlways")
            | Some("decline")
            | Some("cancel") => Ok(()),
            _ => bail!("approval.decision is unsupported"),
        },
        "userInput" => {
            if object.get("answers").is_some_and(Value::is_object) {
                Ok(())
            } else {
                bail!("userInput.answers must be an object")
            }
        }
        "elicitation" => match object.get("action").and_then(Value::as_str) {
            Some("accept") | Some("decline") | Some("cancel") => Ok(()),
            _ => bail!("elicitation.action is unsupported"),
        },
        "native" => {
            if object.get("result").is_some() {
                Ok(())
            } else {
                bail!("native.result is required")
            }
        }
        _ => bail!("response.type must be approval, userInput, elicitation, or native"),
    }
}

fn parse_object(raw: &str, label: &str) -> Result<Value> {
    let value: Value =
        serde_json::from_str(raw).with_context(|| format!("{label} is invalid JSON"))?;
    if !value.is_object() {
        bail!("{label} must be a JSON object");
    }
    Ok(value)
}

fn require_nested_id(value: &Value, key: &str, label: &str) -> Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("{label} must be an object"))?;
    require_text(
        object.get(key).and_then(Value::as_str).unwrap_or_default(),
        &format!("{label}.{key}"),
    )?;
    Ok(())
}

fn require_text(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        bail!("{label} cannot be empty");
    }
    Ok(value.to_owned())
}

fn optional_text(value: Option<String>, label: &str) -> Result<Option<String>> {
    value.map(|value| require_text(&value, label)).transpose()
}

fn request_id(value: Option<String>) -> Result<String> {
    match value {
        Some(value) => require_text(&value, "request-id"),
        None => Ok(format!("cli-{}", Uuid::new_v4())),
    }
}

fn read_text_source(
    inline: Option<String>,
    file: Option<&str>,
    stdin: bool,
    label: &str,
) -> Result<String> {
    let raw = if let Some(value) = inline {
        value
    } else if let Some(path) = file {
        std::fs::read_to_string(path)
            .with_context(|| format!("could not read {label} file: {path}"))?
    } else if stdin {
        let mut value = String::new();
        std::io::stdin()
            .read_to_string(&mut value)
            .with_context(|| format!("could not read {label} from stdin"))?;
        value
    } else {
        bail!("{label} is required");
    };
    require_text(&raw, label)
}

fn read_json_source(
    inline: Option<String>,
    file: Option<&str>,
    stdin: bool,
    label: &str,
) -> Result<Value> {
    let raw = read_text_source(inline, file, stdin, label)?;
    serde_json::from_str(&raw).with_context(|| format!("{label} is invalid JSON"))
}

#[cfg(test)]
#[path = "chat_orchestration_commands_tests.rs"]
mod tests;
