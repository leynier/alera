//! Capability validation for both lineage-bound and human CLI requests.

use anyhow::{Context, Result};
use serde_json::Value;

use crate::chat_orchestration_commands::CHAT_ORCHESTRATION_CAPABILITY;
use crate::chat_task_command_contract::{EFFORT_CAPABILITY, PERSON_PARENT_CAPABILITY};
use crate::cli::RuntimeDirArgs;
use crate::runtime_host_client::RuntimeHostRpcClient;

pub(crate) fn extra_capabilities(verb: &str, payload: &Value) -> Vec<&'static str> {
    let verb = verb.strip_prefix("chatOrchestration.").unwrap_or(verb);
    let mut capabilities = Vec::new();
    if matches!(verb, "delegate" | "send")
        && payload
            .get("parentChatId")
            .is_some_and(|value| !value.is_null())
    {
        capabilities.push(PERSON_PARENT_CAPABILITY);
    }
    if (verb == "delegate" && payload.pointer("/agent/options/reasoningEffort").is_some())
        || (verb == "configure" && payload.get("reasoningEffort").is_some())
    {
        capabilities.push(EFFORT_CAPABILITY);
    }
    capabilities
}

pub(crate) async fn request(
    runtime: &RuntimeDirArgs,
    verb: &str,
    payload: Value,
    deadline_ms: Option<u64>,
) -> Result<Value> {
    let runtime_dir = crate::runtime_dir(runtime);
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir,
        CHAT_ORCHESTRATION_CAPABILITY,
    )
    .await?;
    for capability in extra_capabilities(verb, &payload) {
        RuntimeHostRpcClient::connect_with_required_capability(&runtime_dir, capability)
            .await?
            .context("The runtime disconnected before capability validation.")?;
    }
    match deadline_ms {
        Some(deadline) => {
            client
                .request_value_with_deadline(verb, &payload, deadline)
                .await
        }
        None => client.request_value(verb, &payload).await,
    }
}
