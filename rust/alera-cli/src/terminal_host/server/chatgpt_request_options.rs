use alera_core::runtime::RuntimeAiAssistSettings;
use serde_json::Value;
use std::collections::HashMap;

use super::ai_assist_requests::{resolved_agent, resolved_model};
use super::chatgpt_inference::ConfiguredThinking;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn resolved_thinking_level(
    settings: &RuntimeAiAssistSettings,
    operation: &str,
    model: &str,
) -> Option<String> {
    settings
        .selected_thinking_by_operation
        .get(operation)
        .and_then(|values| values.get(model))
        .or_else(|| settings.selected_thinking_by_model.get(model))
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn chatgpt_options_required(
    settings: &RuntimeAiAssistSettings,
    operation: &str,
) -> bool {
    if resolved_agent(settings, operation) != "chatgpt" {
        return false;
    }
    if settings
        .chat_gpt_service_tier
        .trim()
        .eq_ignore_ascii_case("fast")
    {
        return true;
    }
    let model = resolved_model(settings, operation);
    if resolved_thinking_level(settings, operation, &model).is_some() {
        return true;
    }
    model.is_empty()
        && (settings
            .selected_thinking_by_operation
            .get(operation)
            .is_some_and(|values| !values.is_empty())
            || !settings.selected_thinking_by_model.is_empty())
}

pub(super) fn parse_thinking_context(
    value: Option<&Value>,
) -> HostResult<Option<ConfiguredThinking>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let Some(object) = value.as_object() else {
        return Err(HostError::format("ChatGPT thinking context is invalid."));
    };
    let operation = object
        .get("operation")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    let selected_by_model = parse_string_map(object.get("selectedThinkingByModel"))?;
    let operation_values = parse_string_map(object.get("selectedThinkingByOperation"))?;
    let selected_by_operation = match operation.as_ref() {
        Some(operation) => HashMap::from([(operation.clone(), operation_values)]),
        None if operation_values.is_empty() => HashMap::new(),
        None => {
            return Err(HostError::format("ChatGPT thinking context is invalid."));
        }
    };
    Ok(Some(ConfiguredThinking {
        operation,
        selected_by_model,
        selected_by_operation,
    }))
}

fn parse_string_map(value: Option<&Value>) -> HostResult<HashMap<String, String>> {
    let Some(value) = value else {
        return Ok(HashMap::new());
    };
    let Some(object) = value.as_object() else {
        return Err(HostError::format("ChatGPT thinking context is invalid."));
    };
    object
        .iter()
        .map(|(key, value)| {
            let value = value
                .as_str()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| HostError::format("ChatGPT thinking context is invalid."))?;
            Ok((key.trim().to_string(), value.to_string()))
        })
        .collect()
}
