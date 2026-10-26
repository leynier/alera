use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::ChatOp;

pub(crate) fn encode_operation(operation: &ChatOp) -> Value {
    let mut value = serde_json::json!(operation);
    preserve_selection_presence(operation, &mut value);
    value
}

fn preserve_selection_presence(operation: &ChatOp, value: &mut Value) {
    match operation {
        ChatOp::Configure(input) => {
            if let Some(configure) = value["Configure"].as_object_mut() {
                if input.model.is_none() {
                    configure.remove("model");
                }
                if input.reasoning_effort.is_none() {
                    configure.remove("reasoning_effort");
                }
            }
        }
        ChatOp::WithinCeiling { operation, .. } => {
            preserve_selection_presence(operation, &mut value["WithinCeiling"]["operation"]);
        }
        _ => {}
    }
}

pub(crate) fn decode_operation(payload: &Value) -> HostResult<ChatOp> {
    let value = payload
        .get("op")
        .ok_or_else(|| HostError::format("op is required"))?;
    let mut operation = serde_json::from_value(value.clone())
        .map_err(|error| HostError::format(format!("Invalid op: {error}")))?;
    restore_explicit_resets(&mut operation, value);
    Ok(operation)
}

fn restore_explicit_resets(operation: &mut ChatOp, value: &Value) {
    match operation {
        ChatOp::Configure(input) => {
            if value["Configure"].get("model").is_some_and(Value::is_null) {
                input.model = Some(None);
            }
            if value["Configure"]
                .get("reasoning_effort")
                .is_some_and(Value::is_null)
            {
                input.reasoning_effort = Some(None);
            }
        }
        ChatOp::WithinCeiling { operation, .. } => {
            restore_explicit_resets(operation, &value["WithinCeiling"]["operation"]);
        }
        _ => {}
    }
}
