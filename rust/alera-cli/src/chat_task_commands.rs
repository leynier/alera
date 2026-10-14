//! Structured human chat-task requests without agent identity substitution.

use anyhow::{bail, Result};
use clap::Args;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::agent_chat_commands::{insert_field, read_payload, require_human_scope};
use crate::agent_chat_commands_args::AgentChatRequestArgs;
use crate::chat_task_command_contract::{is_mutation, verb, OPERATIONS};
use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::WAIT_CLIENT_GRACE_MS;

#[derive(Debug, Args)]
pub struct ChatHumanArgs {
    /// Exact canonical operation over chatOrchestration.* for a human caller.
    #[arg(value_parser = clap::builder::PossibleValuesParser::new(OPERATIONS.iter().copied()))]
    pub operation: String,
    #[command(flatten)]
    pub input: AgentChatRequestArgs,
    /// Human originating chat for delegate/send; never an agent identity.
    #[arg(long = "parent-chat-id")]
    pub parent_chat_id: Option<String>,
}

pub(crate) async fn run(runtime: &RuntimeDirArgs, args: ChatHumanArgs) -> Result<Value> {
    require_human_scope(std::env::var_os(crate::mcp_tools::CHAT_CREDENTIAL_FILE_ENV).is_some())?;
    let operation = args.operation.clone();
    let payload = prepare(args)?;
    let deadline = deadline_ms(&operation, &payload);
    crate::chat_orchestration_request::request(
        runtime,
        &format!("chatOrchestration.{}", verb(&operation)),
        payload,
        deadline,
    )
    .await
}

pub(crate) fn prepare(args: ChatHumanArgs) -> Result<Value> {
    let operation = &args.operation;
    let input = args.input;
    let mut payload = read_payload(&input, operation)?;
    let object = payload
        .as_object_mut()
        .expect("read_payload returns an object");
    insert_field(object, "chatId", input.chat_id.map(Value::String))?;
    insert_field(object, "workspaceId", input.workspace_id.map(Value::String))?;
    insert_field(object, "hostId", input.host_id.map(Value::String))?;
    insert_field(
        object,
        "parentChatId",
        args.parent_chat_id.map(Value::String),
    )?;
    insert_field(object, "requestId", input.request_id.map(Value::String))?;
    insert_field(object, "limit", input.limit.map(|limit| json!(limit)))?;
    insert_field(object, "model", input.model.map(Value::String))?;
    if input.reset_model {
        if operation != "configure" {
            bail!("--reset-model is only supported by configure");
        }
        insert_field(object, "model", Some(Value::Null))?;
    }
    let request_id = object.remove("requestId");
    if let Some(id) = &request_id {
        if !is_mutation(operation) {
            bail!("Read-only operations do not accept requestId.");
        }
        if !id.as_str().is_some_and(|id| !id.trim().is_empty()) {
            bail!("requestId must be a nonempty string");
        }
    }
    crate::chat_task_payload_validation::validate(operation, &payload)?;
    let object = payload.as_object_mut().expect("payload remains an object");
    if matches!(operation.as_str(), "read" | "task-list") {
        object.entry("limit").or_insert_with(|| json!(100));
    }
    if operation == "wait"
        || operation == "delegate" && object.get("mode").and_then(Value::as_str) == Some("wait")
    {
        object.entry("waitSeconds").or_insert_with(|| json!(50));
    }
    if is_mutation(operation) {
        object.insert(
            "requestId".into(),
            request_id.unwrap_or_else(|| json!(format!("cli-{}", Uuid::new_v4()))),
        );
    }
    if operation == "acknowledge" {
        object.insert("acknowledge".into(), json!(true));
    }
    Ok(payload)
}

pub(crate) fn deadline_ms(operation: &str, payload: &Value) -> Option<u64> {
    if operation != "wait" && !(operation == "delegate" && payload["mode"] == "wait") {
        return None;
    }
    Some(
        payload["waitSeconds"]
            .as_u64()
            .unwrap_or(50)
            .min(50)
            .saturating_mul(1000)
            .saturating_add(WAIT_CLIENT_GRACE_MS),
    )
}

#[cfg(test)]
#[path = "chat_task_commands_tests.rs"]
mod tests;
