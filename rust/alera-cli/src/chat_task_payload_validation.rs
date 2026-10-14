//! Validates the exact request schemas without formatting supplied values.

use anyhow::{bail, Result};
use serde_json::Value;

use crate::chat_task_command_contract::{payload_schema, OPERATIONS};

pub(crate) fn validate(operation: &str, payload: &Value) -> Result<()> {
    if !OPERATIONS.contains(&operation) {
        bail!("Unknown human chat-task operation.");
    }
    if serde_json::to_vec(payload)?.len() > 256 * 1024 {
        bail!("payload exceeds 256 KiB");
    }
    if !matches_schema(payload, &payload_schema(operation)) {
        bail!("Invalid payload for {operation}; use its exact canonical fields and limits.");
    }
    for key in ["task", "message"] {
        if payload
            .get(key)
            .and_then(Value::as_str)
            .is_some_and(|text| text.len() > 65_536)
        {
            bail!("Task and message text must not exceed 64 KiB.");
        }
    }
    let effort = payload
        .pointer("/agent/options/reasoningEffort")
        .or_else(|| payload.get("reasoningEffort"))
        .and_then(Value::as_str);
    if effort.is_some_and(|value| value.len() > 128) {
        bail!("Reasoning effort must not exceed 128 bytes.");
    }
    if operation == "respond" {
        crate::chat_orchestration_commands::validate_response(&payload["response"])?;
    }
    Ok(())
}

fn has_type(value: &Value, kind: &str) -> bool {
    match kind {
        "object" => value.is_object(),
        "array" => value.is_array(),
        "string" => value.is_string(),
        "boolean" => value.is_boolean(),
        "integer" => value.as_u64().is_some(),
        "null" => value.is_null(),
        _ => false,
    }
}

fn matches_schema(value: &Value, schema: &Value) -> bool {
    if let Some(kind) = schema.get("type") {
        let valid = match kind {
            Value::String(kind) => has_type(value, kind),
            Value::Array(kinds) => kinds
                .iter()
                .filter_map(Value::as_str)
                .any(|kind| has_type(value, kind)),
            _ => false,
        };
        if !valid {
            return false;
        }
    }
    if let Some(allowed) = schema["enum"].as_array() {
        if !allowed.contains(value) {
            return false;
        }
    }
    if let Some(alternatives) = schema["oneOf"].as_array() {
        if alternatives
            .iter()
            .filter(|alternative| matches_schema(value, alternative))
            .count()
            != 1
        {
            return false;
        }
    }
    if let Some(alternatives) = schema["anyOf"].as_array() {
        if !alternatives
            .iter()
            .any(|alternative| matches_schema(value, alternative))
        {
            return false;
        }
    }
    if let Some(object) = value.as_object() {
        if schema["required"].as_array().is_some_and(|required| {
            required
                .iter()
                .filter_map(Value::as_str)
                .any(|key| !object.contains_key(key))
        }) {
            return false;
        }
        if schema["minProperties"]
            .as_u64()
            .is_some_and(|n| object.len() < n as usize)
            || schema["maxProperties"]
                .as_u64()
                .is_some_and(|n| object.len() > n as usize)
        {
            return false;
        }
        if let Some(properties) = schema["properties"].as_object() {
            for (key, field) in object {
                match properties.get(key) {
                    Some(field_schema) if !matches_schema(field, field_schema) => return false,
                    None if schema["additionalProperties"] == false => return false,
                    _ => {}
                }
            }
        }
    }
    if let Some(items) = value.as_array() {
        if schema["minItems"]
            .as_u64()
            .is_some_and(|n| items.len() < n as usize)
            || schema["maxItems"]
                .as_u64()
                .is_some_and(|n| items.len() > n as usize)
        {
            return false;
        }
        if let Some(item_schema) = schema.get("items") {
            if !items.iter().all(|item| matches_schema(item, item_schema)) {
                return false;
            }
        }
    }
    if let Some(text) = value.as_str() {
        if schema["minLength"]
            .as_u64()
            .is_some_and(|n| text.trim().chars().count() < n as usize)
            || schema["maxLength"]
                .as_u64()
                .is_some_and(|n| text.chars().count() > n as usize)
        {
            return false;
        }
    }
    if let Some(number) = value.as_u64() {
        if schema["minimum"].as_u64().is_some_and(|n| number < n)
            || schema["maximum"].as_u64().is_some_and(|n| number > n)
        {
            return false;
        }
    }
    true
}
