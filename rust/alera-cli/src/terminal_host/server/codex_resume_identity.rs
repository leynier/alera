//! Stable identity fallbacks for reconciling persisted and resumed messages.

use serde_json::Value;
use std::collections::HashSet;

pub(super) fn message_identity_key(cell: &Value) -> Option<String> {
    let kind = cell.get("kind").and_then(Value::as_str)?;
    if !matches!(kind, "userMessage" | "assistantMessage" | "progressText") {
        return None;
    }
    let turn_id = cell
        .get("turnId")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())?;
    let markdown = cell
        .get("markdownText")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())?;
    let phase = cell
        .pointer("/metadata/streamPhase")
        .and_then(Value::as_str)
        .unwrap_or_default();
    Some(format!(
        "message:{turn_id}:{kind}:{phase}:{}",
        normalize_message_text(markdown)
    ))
}

pub(super) fn phase_agnostic_agent_message_identity_key(cell: &Value) -> Option<String> {
    is_agent_text(cell).then_some(())?;
    let kind = cell.get("kind").and_then(Value::as_str)?;
    let turn_id = message_turn_id(cell)?.trim();
    if turn_id.is_empty() {
        return None;
    }
    let markdown = normalized_message_text(cell)?;
    Some(format!("legacy-message:{turn_id}:{kind}:{markdown}"))
}

pub(super) fn has_explicit_stream_phase(cell: &Value) -> bool {
    stream_phase(cell).is_some()
}

pub(super) fn message_turn_id(cell: &Value) -> Option<&str> {
    matches!(
        cell.get("kind").and_then(Value::as_str),
        Some("userMessage" | "assistantMessage" | "progressText")
    )
    .then(|| cell.get("turnId").and_then(Value::as_str))
    .flatten()
}

pub(super) fn is_agent_text(cell: &Value) -> bool {
    matches!(
        cell.get("kind").and_then(Value::as_str),
        Some("assistantMessage" | "progressText")
    )
}

pub(super) fn messages_are_prefix_compatible(left: &Value, right: &Value) -> bool {
    if !is_agent_text(left) || !is_agent_text(right) {
        return false;
    }
    if message_turn_id(left) != message_turn_id(right)
        || left.get("kind").and_then(Value::as_str) != right.get("kind").and_then(Value::as_str)
        || !stream_phases_are_compatible(left, right)
    {
        return false;
    }
    if left.get("isStreaming").and_then(Value::as_bool) != Some(true)
        && right.get("isStreaming").and_then(Value::as_bool) != Some(true)
    {
        return false;
    }
    let Some(left_text) = normalized_message_text(left) else {
        return false;
    };
    let Some(right_text) = normalized_message_text(right) else {
        return false;
    };
    left_text != right_text
        && (left_text.starts_with(&right_text) || right_text.starts_with(&left_text))
}

fn normalized_message_text(cell: &Value) -> Option<String> {
    cell.get("markdownText")
        .and_then(Value::as_str)
        .map(normalize_message_text)
        .filter(|value| !value.is_empty())
}

fn stream_phase(cell: &Value) -> Option<&str> {
    cell.pointer("/metadata/streamPhase")
        .and_then(Value::as_str)
        .filter(|phase| !phase.trim().is_empty())
}

fn stream_phases_are_compatible(left: &Value, right: &Value) -> bool {
    match (stream_phase(left), stream_phase(right)) {
        (Some(left), Some(right)) => left == right,
        _ => true,
    }
}

fn normalize_message_text(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub(super) fn complete_history_turn_ids(snapshot: &Value) -> HashSet<String> {
    let mut turn_ids = snapshot
        .get("completeHistoryTurnIds")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|turn_id| !turn_id.trim().is_empty())
        .map(str::to_string)
        .collect::<HashSet<_>>();
    turn_ids.extend(
        snapshot
            .get("events")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|event| event.get("method").and_then(Value::as_str) == Some("turn/started"))
            .filter(|event| {
                event
                    .pointer("/params/turn/aleraHistoryItemsComplete")
                    .and_then(Value::as_bool)
                    == Some(true)
            })
            .filter_map(|event| {
                event
                    .pointer("/params/turnId")
                    .and_then(Value::as_str)
                    .map(str::to_string)
            }),
    );
    turn_ids
}
