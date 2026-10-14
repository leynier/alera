//! Public human chat-task tools, separate from the injected `chat_*` catalog.

use serde_json::Value;

use super::{execute, read, LAUNCH_TIMEOUT, WAIT_TIMEOUT};
use crate::chat_task_command_contract::{tool_schema, CONTROL_OPERATIONS, QUERY_OPERATIONS};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut query = read(
        "chat_task_query", "Read Chat Tasks",
        "Read human-visible chat capabilities, chats, bounded transcript, task status, task pages, open requests, or wait up to 50 seconds. This tool never acknowledges results.",
        || tool_schema(QUERY_OPERATIONS), build,
    );
    query.timeout_seconds = WAIT_TIMEOUT;
    let mut delegate = execute(
        "chat_task_delegate", "Delegate Chat Task",
        "Delegate a brief as an authenticated human to a chat, workspace, or new managed/shared workspace. Optional parentChatId binds its task dock and idle-only wake without impersonating an agent. Effort uses agent.options.reasoningEffort and requires verified support. Retain returned task/chat/workspace ids.",
        || tool_schema(&["delegate"]), build,
    );
    delegate.timeout_seconds = LAUNCH_TIMEOUT;
    delegate.client_request_flag = Some("--request-id");
    let mut send = execute(
        "chat_task_send", "Send Chat Task Message",
        "Send a message as an authenticated human to an existing chat, optionally creating a completion task with expectReply. Optional parentChatId applies only to expectReply and requires person-parent capability. Delivery is auto or queue; no workspace navigation occurs.",
        || tool_schema(&["send"]), build,
    );
    send.client_request_flag = Some("--request-id");
    let mut control = execute(
        "chat_task_control", "Control Chat Task",
        "Acknowledge a result, cancel a task and descendants, interrupt a turn, answer an exact offered request, or configure a chat. Per-chat execution permissions apply; provider/global Settings require separate admin tools. Mutable requests, including acknowledgement on updated hosts, replay the supplied request receipt; legacy no-id acknowledgement remains compatible.",
        || tool_schema(CONTROL_OPERATIONS), build,
    );
    control.destructive = true;
    control.client_request_flag = Some("--request-id");
    vec![query, delegate, send, control]
}

fn build(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let operation = arguments.required("operation")?;
    let payload = Value::Object(
        arguments
            .object("payload")
            .ok_or_else(|| ToolInputError("payload must be an object".into()))?
            .clone(),
    );
    crate::chat_task_payload_validation::validate(&operation, &payload)
        .map_err(|error| ToolInputError(error.to_string()))?;
    Ok(Invocation::new("chat", &["human", &operation])
        .flag("--payload-stdin")
        .stdin(payload.to_string()))
}

#[cfg(test)]
#[path = "chat_tasks_tests.rs"]
mod tests;
