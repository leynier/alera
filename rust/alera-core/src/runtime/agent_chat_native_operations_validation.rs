use anyhow::Result;
use serde_json::Value;

use super::models::*;
use crate::runtime::agent_chat_validation::{require_chat_id, require_id};
use crate::runtime::AgentChatStoreError;

pub(super) fn invalid(reason: &str) -> anyhow::Error {
    AgentChatStoreError::Invalid(reason.into()).into()
}

pub(super) fn require_kind(kind: &str) -> Result<()> {
    if !matches!(
        kind,
        AGENT_CHAT_NATIVE_REWIND | AGENT_CHAT_NATIVE_REWIND_FILES
    ) {
        return Err(invalid("unsupported native operation kind"));
    }
    Ok(())
}

pub(super) fn bounded(value: &Value) -> Result<String> {
    let json = serde_json::to_string(value)?;
    if json.len() > AGENT_CHAT_NATIVE_OPERATION_MAX_BYTES {
        return Err(invalid("native operation identity exceeds its byte budget"));
    }
    crate::runtime::agent_chat_secrets::reject_secret_fields("native operation identity", value)?;
    Ok(json)
}

fn object_keys(value: &Value, keys: &[&str]) -> Result<()> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid("native operation evidence must be an object"))?;
    if object.len() != keys.len() || object.keys().any(|key| !keys.contains(&key.as_str())) {
        return Err(invalid(
            "native operation evidence contains unsupported fields",
        ));
    }
    bounded(value)?;
    Ok(())
}

pub(super) fn require_boundary(kind: &str, boundary: &Value) -> Result<()> {
    if kind == AGENT_CHAT_NATIVE_REWIND {
        object_keys(boundary, &["type", "value"])?;
        match boundary["type"].as_str() {
            Some("beforeTurn") => require_id(
                "native turn boundary",
                boundary["value"].as_str().unwrap_or(""),
            ),
            _ => Err(invalid("native conversation rewind boundary is invalid")),
        }
    } else if kind == AGENT_CHAT_NATIVE_REWIND_FILES {
        object_keys(boundary, &["type", "id"])?;
        if boundary["type"] != "message" {
            return Err(invalid("native file rewind requires a message boundary"));
        }
        require_id(
            "native user message boundary",
            boundary["id"].as_str().unwrap_or(""),
        )
    } else {
        Err(invalid("unsupported native operation kind"))
    }
}

pub(super) fn require_input(
    input: &AgentChatNativeOperationInput,
    receipt: &AgentChatNativeOperationReceipt,
) -> Result<()> {
    require_chat_id(&input.chat_id)?;
    for (label, id) in [
        ("operationId", &input.operation_id),
        ("nativeThreadId", &input.expected_native_thread_id),
        ("processEpoch", &input.process_epoch),
        ("turnId", &input.turn_id),
        ("actor", &input.actor),
        ("callerScope", &receipt.caller_scope),
        ("verb", &receipt.verb),
        ("requestId", &receipt.request_id),
        ("digest", &receipt.digest),
    ] {
        require_id(label, id)?;
    }
    if input.expected_cursor < 0 || input.expected_generation < 1 {
        return Err(invalid("native operation cursor or generation is invalid"));
    }
    if input.expected_native_thread_id.starts_with("pending:") {
        return Err(invalid(
            "native operation requires an observed native thread",
        ));
    }
    require_boundary(&input.kind, &input.boundary)
}

pub(super) fn require_ack(operation: &AgentChatNativeOperation, ack: &Value) -> Result<()> {
    require_kind(&operation.kind)?;
    let keys = if operation.kind == AGENT_CHAT_NATIVE_REWIND {
        ["threadId", "nativeThreadId", "boundary"]
    } else {
        ["threadId", "nativeThreadId", "nativeUserMessageId"]
    };
    object_keys(ack, &keys)?;
    if ack["threadId"].as_str() != Some(operation.native_thread_id.as_str()) {
        return Err(invalid(
            "native acknowledgment belongs to another source thread",
        ));
    }
    let observed = ack["nativeThreadId"].as_str().unwrap_or("");
    require_id("observed native thread", observed)?;
    if observed.starts_with("pending:") {
        return Err(invalid(
            "native acknowledgment lacks an observed thread identity",
        ));
    }
    let matching = if operation.kind == AGENT_CHAT_NATIVE_REWIND {
        ack["boundary"] == operation.boundary
    } else {
        ack["nativeUserMessageId"] == operation.boundary["id"]
    };
    if !matching {
        return Err(invalid("native acknowledgment belongs to another boundary"));
    }
    Ok(())
}

pub(super) fn require_transition_evidence(
    operation: &AgentChatNativeOperation,
    new_state: &str,
    evidence: Option<&Value>,
) -> Result<()> {
    if new_state == "acknowledged" {
        return require_ack(
            operation,
            evidence.ok_or_else(|| invalid("native acknowledgment evidence is required"))?,
        );
    }
    let Some(evidence) = evidence else {
        return Ok(());
    };
    if new_state == "executing" {
        object_keys(evidence, &["processEpoch"])?;
        if evidence["processEpoch"].as_str() != Some(operation.process_epoch.as_str()) {
            return Err(invalid("native operation execution epoch changed"));
        }
    } else {
        object_keys(evidence, &["reason"])?;
        if !matches!(
            evidence["reason"].as_str(),
            Some("runtimeRestarted" | "providerError" | "unknown" | "cancelledBeforeExecution")
        ) {
            return Err(invalid("native operation reason must be an allowed code"));
        }
    }
    Ok(())
}

pub(super) fn require_observations(observations: &Value) -> Result<Option<bool>> {
    let object = observations
        .as_object()
        .ok_or_else(|| invalid("filesystem observations must be an object"))?;
    if object.keys().any(|key| {
        !matches!(
            key.as_str(),
            "filesystemChangesReverted" | "observedFileCount" | "observationId"
        )
    }) {
        return Err(invalid(
            "filesystem observations contain unsupported fields",
        ));
    }
    bounded(observations)?;
    let Some(observed) = object
        .get("filesystemChangesReverted")
        .filter(|value| !value.is_null())
    else {
        return Ok(None);
    };
    let observed = observed
        .as_bool()
        .ok_or_else(|| invalid("filesystem effect must be a boolean or null"))?;
    if object
        .get("observedFileCount")
        .and_then(Value::as_u64)
        .is_none()
    {
        return Err(invalid("filesystem effect requires an observed file count"));
    }
    require_id(
        "filesystem observation id",
        object
            .get("observationId")
            .and_then(Value::as_str)
            .unwrap_or(""),
    )?;
    Ok(Some(observed))
}
