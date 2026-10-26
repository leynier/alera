//! General Agent Chat tools. Never included in the credential-bound catalog.

use serde_json::{json, Value};

use super::{admin, execute, read};
use crate::agent_chat_command_contract::{
    CONTROL_OPERATIONS, QUERY_OPERATIONS, SETTINGS_READ_OPERATIONS, SETTINGS_UPDATE_OPERATIONS,
};
use crate::mcp_tools::schema::{object, one_of};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    let query = read(
        "agent_chat_query", "Read Agent Chat",
        "Read the provider catalog, chats, transcript, approval history, or turn diff. History reads are bounded and capability gated.",
        || schema(QUERY_OPERATIONS), build,
    );
    let mut control = execute(
        "agent_chat_control", "Control Agent Chat",
        "Create, send, configure, answer, close, steer, fork, rewind, rewind files, configure file checkpoints, reconcile native history, delete, or mark read. Rewind defaults to transcript; mode:native is explicit and independently gated. Read native-history-operation before resolving native ambiguity, never repeat an uncertain provider action.",
        || schema(CONTROL_OPERATIONS), build,
    );
    control.client_request_flag = Some("--request-id");
    control.destructive = true;
    let settings_read = admin(
        "agent_chat_settings_read", "Read Agent Chat Settings",
        "Read host-shared preferences, provider launch definitions without secret values, or instance removal impact. Requires admin access.",
        || schema(SETTINGS_READ_OPERATIONS), build,
    );
    let mut settings_update = admin(
        "agent_chat_settings_update", "Update Agent Chat Settings",
        "Apply preference operations, edit or remove provider instances, or set/clear write-only secrets. Requires admin access and expectedRevision; inspect removal impact first. Secret payloads travel on stdin.",
        || schema(SETTINGS_UPDATE_OPERATIONS), build,
    );
    settings_update.client_request_flag = Some("--request-id");
    settings_update.destructive = true;
    vec![query, control, settings_read, settings_update]
}

fn schema(operations: &[&str]) -> Value {
    let mut schema = object(
        &[
            (
                "operation",
                one_of("Named agent-chat CLI operation.", operations),
            ),
            (
                "payload",
                json!({
                    "type": "object",
                    "description": "Canonical agentChat request fields, including explicit chatId/workspaceId/hostId as applicable. Configure accepts model:null and reasoningEffort:null. Settings edits require expectedRevision. Receipt ids are supplied through clientRequestId.",
                }),
            ),
        ],
        &["operation", "payload"],
    );
    schema["oneOf"] = Value::Array(operations.iter().map(|operation| json!({
        "properties":{
            "operation":{"enum":[operation]},
            "payload":crate::agent_chat_native_history_contract::schema(operation).unwrap_or_else(|| json!({"type":"object"})),
        },
        "required":["operation","payload"],
    })).collect());
    schema
}

fn build(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let operation = arguments.required("operation")?;
    let payload = arguments
        .object("payload")
        .ok_or_else(|| ToolInputError("payload must be an object".into()))?;
    if payload.contains_key("requestId")
        || payload.contains_key("actor")
        || payload.contains_key("scope")
    {
        return Err(ToolInputError(
            "Use clientRequestId for retries; caller identity is host-derived.".into(),
        ));
    }
    if crate::agent_chat_native_history_contract::schema(&operation).is_some() {
        crate::agent_chat_commands::validate(&operation, payload)
            .map_err(|error| ToolInputError(error.to_string()))?;
    }
    let payload = Value::Object(payload.clone()).to_string();
    if payload.len() > 256 * 1024 {
        return Err(ToolInputError("payload exceeds 256 KiB".into()));
    }
    Ok(Invocation::new("agent-chat", &[&operation])
        .flag("--payload-stdin")
        .stdin(payload))
}

#[cfg(test)]
#[path = "agent_chat_tests.rs"]
mod tests;
