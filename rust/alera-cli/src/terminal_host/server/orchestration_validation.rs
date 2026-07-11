use alera_core::runtime::{
    OrchestrationMessagePriority, OrchestrationMessageType, ORCHESTRATION_SUBJECT_MAX_BYTES,
};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

const MAX_WAIT_TIMEOUT_MS: u64 = 600_000;
const DEFAULT_WAIT_TIMEOUT_MS: u64 = 120_000;

pub(super) fn optional_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn require_string(payload: &Value, key: &str) -> HostResult<String> {
    optional_string(payload, key).ok_or_else(|| HostError::format(format!("{key} is required.")))
}

pub(super) fn parse_message_type(payload: &Value) -> HostResult<OrchestrationMessageType> {
    match payload.get("type").and_then(Value::as_str) {
        None => Ok(OrchestrationMessageType::Status),
        Some(raw) => OrchestrationMessageType::parse(raw)
            .ok_or_else(|| HostError::format(format!("unknown message type: {raw}"))),
    }
}

pub(super) fn parse_priority(payload: &Value) -> HostResult<OrchestrationMessagePriority> {
    match payload.get("priority").and_then(Value::as_str) {
        None => Ok(OrchestrationMessagePriority::Normal),
        Some(raw) => OrchestrationMessagePriority::parse(raw)
            .ok_or_else(|| HostError::format(format!("unknown message priority: {raw}"))),
    }
}

pub(super) fn parse_type_filter(payload: &Value) -> HostResult<Vec<OrchestrationMessageType>> {
    let Some(types) = payload.get("types") else {
        return Ok(Vec::new());
    };
    let Some(items) = types.as_array() else {
        return Err(HostError::format("types must be an array of strings."));
    };
    items
        .iter()
        .map(|item| {
            item.as_str()
                .and_then(OrchestrationMessageType::parse)
                .ok_or_else(|| HostError::format(format!("unknown message type: {item}")))
        })
        .collect()
}

pub(super) fn wait_timeout_ms(payload: &Value) -> u64 {
    payload
        .get("timeoutMs")
        .and_then(Value::as_u64)
        .unwrap_or(DEFAULT_WAIT_TIMEOUT_MS)
        .min(MAX_WAIT_TIMEOUT_MS)
}

pub(super) fn state_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

pub(super) fn prefixed_subject(prefix: &str, subject: &str) -> String {
    let mut end = subject
        .len()
        .min(ORCHESTRATION_SUBJECT_MAX_BYTES.saturating_sub(prefix.len()));
    while !subject.is_char_boundary(end) {
        end = end.saturating_sub(1);
    }
    format!("{prefix}{}", &subject[..end])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefixed_subject_stays_within_the_storage_limit_on_utf8_boundaries() {
        let subject = "á".repeat(ORCHESTRATION_SUBJECT_MAX_BYTES);
        let prefixed = prefixed_subject("Re: ", &subject);
        assert!(prefixed.starts_with("Re: "));
        assert!(prefixed.len() <= ORCHESTRATION_SUBJECT_MAX_BYTES);
        assert!(prefixed.is_char_boundary(prefixed.len()));
    }
}
