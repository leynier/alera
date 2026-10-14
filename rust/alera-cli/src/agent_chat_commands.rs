//! Human CLI controls for persistent Agent Chat. Bound agents use `chat`.

use std::io::Read;

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Map, Value};
use uuid::Uuid;

use crate::agent_chat_command_contract::{is_mutation, required_capability, spec};
use crate::agent_chat_commands_args::{AgentChatCommand, AgentChatRequestArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;

const MAX_PAYLOAD_BYTES: usize = 256 * 1024;

pub(crate) async fn run(command: AgentChatCommand) -> i32 {
    let (operation, args) = command.action.into_parts();
    let result = async {
        require_human_scope(
            std::env::var_os(crate::mcp_tools::CHAT_CREDENTIAL_FILE_ENV).is_some(),
        )?;
        let payload = prepare(operation, args)?;
        let request_spec = spec(operation);
        let runtime_dir = crate::runtime_dir(&command.runtime);
        let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
            &runtime_dir,
            required_capability(operation, &payload),
        )
        .await?;
        for capability in extra_capabilities(operation, &payload) {
            RuntimeHostRpcClient::connect_with_required_capability(&runtime_dir, capability)
                .await?
                .context("The runtime disconnected before capability validation.")?;
        }
        client
            .request_value(&format!("agentChat.{}", request_spec.suffix), &payload)
            .await
    }
    .await;
    match result {
        Ok(value) => {
            crate::print_value(&value, command.output.json, "agent chat request completed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

fn extra_capabilities(operation: &str, payload: &Value) -> Vec<&'static str> {
    let mut capabilities = Vec::new();
    if payload.get("reasoningEffort").is_some() {
        capabilities.push("agentChatEffortV1");
    }
    if operation == "create"
        && payload.get("provider").is_none()
        && payload.get("providerInstanceId").is_none()
    {
        capabilities.push("agentChatUnselectedDraftV1");
    }
    capabilities
}

pub(crate) fn require_human_scope(chat_bound: bool) -> Result<()> {
    if chat_bound {
        bail!("Human chat controls require a human client. Use alera chat for credential-bound lineage operations.");
    }
    Ok(())
}

pub(crate) fn read_payload(args: &AgentChatRequestArgs, operation: &str) -> Result<Value> {
    if operation == "secrets-set" && args.payload.is_some() {
        bail!("Secret payloads require --payload-file or --payload-stdin.");
    }
    let mut source: Box<dyn Read + '_> = if let Some(raw) = &args.payload {
        Box::new(std::io::Cursor::new(raw.as_bytes()))
    } else if let Some(path) = &args.payload_file {
        Box::new(std::fs::File::open(path).context("could not open the payload file")?)
    } else if args.payload_stdin {
        Box::new(std::io::stdin())
    } else {
        return Ok(json!({}));
    };
    let mut bytes = Vec::new();
    source
        .by_ref()
        .take((MAX_PAYLOAD_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .context("could not read the payload")?;
    if bytes.len() > MAX_PAYLOAD_BYTES {
        bail!("payload exceeds 256 KiB");
    }
    let value: Value =
        serde_json::from_slice(&bytes).map_err(|_| anyhow!("payload is invalid JSON"))?;
    if !value.is_object() {
        bail!("payload must be a JSON object");
    }
    Ok(value)
}

pub(crate) fn insert_field(
    object: &mut Map<String, Value>,
    key: &str,
    value: Option<Value>,
) -> Result<()> {
    if let Some(value) = value {
        if object.contains_key(key) {
            bail!("{key} was supplied in both payload and flags");
        }
        object.insert(key.into(), value);
    }
    Ok(())
}

pub(crate) fn prepare(operation: &str, args: AgentChatRequestArgs) -> Result<Value> {
    let mut payload = read_payload(&args, operation)?;
    let object = payload
        .as_object_mut()
        .expect("read_payload returns an object");
    insert_field(object, "chatId", args.chat_id.map(Value::String))?;
    insert_field(object, "workspaceId", args.workspace_id.map(Value::String))?;
    insert_field(object, "hostId", args.host_id.map(Value::String))?;
    insert_field(object, "requestId", args.request_id.map(Value::String))?;
    insert_field(object, "limit", args.limit.map(|limit| json!(limit)))?;
    insert_field(object, "model", args.model.map(Value::String))?;
    if args.reset_model {
        if operation != "configure" {
            bail!("--reset-model is only supported by configure");
        }
        insert_field(object, "model", Some(Value::Null))?;
    }
    validate(operation, object)?;
    if is_mutation(operation) {
        object
            .entry("requestId")
            .or_insert_with(|| json!(format!("cli-{}", Uuid::new_v4())));
        if operation == "send" && !object.contains_key("clientMessageId") {
            object.insert("clientMessageId".into(), object["requestId"].clone());
        }
    }
    if matches!(operation, "history" | "approval-history" | "payload") {
        object.entry("limit").or_insert_with(|| json!(100));
    }
    Ok(payload)
}

pub(crate) fn validate(operation: &str, object: &Map<String, Value>) -> Result<()> {
    let request_spec = spec(operation);
    for key in object.keys() {
        let scoped = matches!(key.as_str(), "chatId" | "workspaceId" | "hostId");
        let receipt = key == "requestId" && is_mutation(operation);
        if !scoped && !receipt && !request_spec.fields.contains(&key.as_str()) {
            bail!("{key} is not supported by {operation}");
        }
    }
    for key in request_spec.required {
        if !object.contains_key(*key) {
            bail!("{key} is required");
        }
    }
    for key in [
        "chatId",
        "workspaceId",
        "hostId",
        "requestId",
        "provider",
        "providerInstanceId",
        "turnId",
        "queueId",
        "title",
        "runtimeRequestId",
        "itemId",
        "name",
        "clientMessageId",
        "operationId",
    ] {
        if let Some(value) = object.get(key) {
            if !value.as_str().is_some_and(|text| !text.trim().is_empty()) {
                bail!("{key} must be a nonempty string");
            }
        }
    }
    if operation == "rewind"
        && object
            .get("mode")
            .is_some_and(|value| !matches!(value.as_str(), Some("transcript" | "native")))
    {
        bail!("rewind mode must be transcript or native");
    }
    if operation == "file-checkpoints-configure"
        && !object.get("enabled").is_some_and(Value::is_boolean)
    {
        bail!("enabled must be a boolean");
    }
    if operation == "native-history-reconcile"
        && !object.get("action").is_some_and(|value| {
            matches!(
                value.as_str(),
                Some(
                    "finishAcknowledged"
                        | "restartFromTranscript"
                        | "cancelUnstarted"
                        | "continueFromCurrentFiles"
                )
            )
        })
    {
        bail!("Unknown native history reconciliation action.");
    }
    if operation == "native-history-reconcile"
        && object
            .get("expectedRevision")
            .is_some_and(|value| !value.as_i64().is_some_and(|revision| revision >= 0))
    {
        bail!("expectedRevision must be a nonnegative integer");
    }
    for key in ["model", "reasoningEffort"] {
        if let Some(value) = object.get(key) {
            if !(operation == "configure" && value.is_null())
                && !value.as_str().is_some_and(|text| !text.trim().is_empty())
            {
                bail!("{key} must be a nonempty id; configure accepts null to reset");
            }
        }
    }
    for key in ["cursor", "index", "expectedRevision"] {
        if object
            .get(key)
            .is_some_and(|value| value.as_u64().is_none())
        {
            bail!("{key} must be a nonnegative integer");
        }
    }
    if object
        .get("limit")
        .is_some_and(|value| !value.as_u64().is_some_and(|n| (1..=500).contains(&n)))
    {
        bail!("limit must be between 1 and 500");
    }
    if operation == "configure"
        && !request_spec
            .fields
            .iter()
            .any(|field| object.contains_key(*field))
    {
        bail!("at least one configuration field is required");
    }
    if operation == "send"
        && !object
            .get("text")
            .is_some_and(|v| v.as_str().is_some_and(|s| !s.trim().is_empty()))
        && !object
            .get("attachments")
            .is_some_and(|v| v.as_array().is_some_and(|a| !a.is_empty()))
    {
        bail!("send requires text or attachments");
    }
    if object.get("text").is_some_and(|value| !value.is_string()) {
        bail!("text must be a string");
    }
    if object.get("value").is_some_and(|value| !value.is_string()) {
        bail!("secret value must be a string");
    }
    Ok(())
}

#[cfg(test)]
#[path = "agent_chat_commands_tests.rs"]
mod tests;
