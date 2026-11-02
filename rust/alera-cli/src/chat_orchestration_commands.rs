//! CLI clients for chat-to-chat orchestration.
//!
//! This group is intentionally separate from the terminal orchestration
//! group. Every operation goes through the chat runtime host so receipts,
//! lineage, workspace routing, and mode ceilings stay in one implementation.

use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::chat_orchestration_commands_args::{
    ChatAction, ChatBackgroundWaitArgs, ChatCancelArgs, ChatCapabilitiesArgs, ChatCommand,
    ChatConfigureArgs, ChatDelegateArgs, ChatInterruptArgs, ChatListArgs, ChatReadArgs,
    ChatRequestsArgs, ChatRespondArgs, ChatSendArgs, ChatTaskArgs, ChatTaskListArgs,
    ChatUpdateTitleArgs, ChatWaitArgs,
};
use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::WAIT_CLIENT_GRACE_MS;

#[path = "chat_orchestration_commands_input.rs"]
mod input;
pub(crate) use input::validate_response;
use input::{
    optional_text, parse_object, parse_target, read_json_source, read_text_source, request_id,
    require_text,
};

pub(crate) const CHAT_ORCHESTRATION_CAPABILITY: &str = "chatOrchestrationV1";
const MAX_WAIT_SECONDS: u64 = 50;
const MAX_BACKGROUND_TASK_IDS: usize = 20;

pub(crate) async fn run(command: ChatCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    let action = match command.action {
        ChatAction::Secret(args) => {
            return crate::chat_secret_commands::secret(&runtime, args).await
        }
        action => action,
    };
    let result = match action {
        ChatAction::Human(args) => crate::chat_task_commands::run(&runtime, args).await,
        ChatAction::Capabilities(args) => capabilities(&runtime, args).await,
        ChatAction::List(args) => list(&runtime, args).await,
        ChatAction::Read(args) => read(&runtime, args).await,
        ChatAction::Transfers(args) => crate::chat_transfers::run(&runtime, args).await,
        ChatAction::Delegate(args) => delegate(&runtime, *args).await,
        ChatAction::Send(args) => send(&runtime, args).await,
        ChatAction::Task(args) => task(&runtime, args).await,
        ChatAction::TaskList(args) => task_list(&runtime, args).await,
        ChatAction::Wait(args) => wait(&runtime, args).await,
        ChatAction::Cancel(args) => cancel(&runtime, args).await,
        ChatAction::Interrupt(args) => interrupt(&runtime, args).await,
        ChatAction::BackgroundWait(args) => background_wait(&runtime, args).await,
        ChatAction::Requests(args) => requests(&runtime, args).await,
        ChatAction::Respond(args) => respond(&runtime, args).await,
        ChatAction::Configure(args) => configure(&runtime, args).await,
        ChatAction::UpdateTitle(args) => update_title(&runtime, args).await,
        ChatAction::RequestSecret(args) => {
            crate::chat_secret_commands::request_secret(&runtime, args).await
        }
        ChatAction::Secret(_) => unreachable!("handled above"),
        ChatAction::PullRequest(args) => {
            crate::chat_pull_request_commands::run(&runtime, args).await
        }
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

async fn capabilities(runtime: &RuntimeDirArgs, args: ChatCapabilitiesArgs) -> Result<Value> {
    request(
        runtime,
        "chatOrchestration.capabilities",
        json!({
            "search": optional_text(args.search, "search")?,
            "workspaceId": optional_text(args.workspace_id, "workspace-id")?,
            "hostId": optional_text(args.host_id, "host-id")?,
        }),
    )
    .await
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

async fn update_title(runtime: &RuntimeDirArgs, args: ChatUpdateTitleArgs) -> Result<Value> {
    let mut payload = json!({"requestId": request_id(args.request_id)?});
    if let Some(chat_id) = optional_text(args.chat_id, "chat-id")? {
        payload["chatId"] = json!(chat_id);
    }
    if args.regenerate {
        payload["regenerate"] = json!(true);
    } else {
        payload["title"] = json!(require_text(
            args.title.as_deref().unwrap_or_default(),
            "title"
        )?);
    }
    request(runtime, "chatOrchestration.updateTitle", payload).await
}

async fn background_wait(runtime: &RuntimeDirArgs, args: ChatBackgroundWaitArgs) -> Result<Value> {
    let task_ids = args
        .task_ids
        .iter()
        .map(|task_id| require_text(task_id, "task-id"))
        .collect::<Result<Vec<_>>>()?;
    if task_ids.len() > MAX_BACKGROUND_TASK_IDS {
        bail!("task-id accepts at most {MAX_BACKGROUND_TASK_IDS} task ids");
    }
    request(
        runtime,
        "chatOrchestration.backgroundWait",
        json!({
            "requestId": request_id(args.request_id)?,
            "taskIds": task_ids,
            "waiting": !args.stop_waiting,
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

#[cfg(test)]
#[path = "chat_orchestration_commands_tests.rs"]
mod tests;
