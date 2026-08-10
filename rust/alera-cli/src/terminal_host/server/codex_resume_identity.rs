//! Stable identity fallbacks for reconciling persisted and resumed messages.

use serde_json::Value;
use std::collections::HashSet;

pub(super) fn message_identity_key(cell: &Value) -> Option<String> {
    let kind = cell.get("kind").and_then(Value::as_str)?;
    if !matches!(kind, "userMessage" | "assistantMessage") {
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
    Some(format!("message:{turn_id}:{kind}:{markdown}"))
}

pub(super) fn message_turn_id(cell: &Value) -> Option<&str> {
    matches!(
        cell.get("kind").and_then(Value::as_str),
        Some("userMessage" | "assistantMessage")
    )
    .then(|| cell.get("turnId").and_then(Value::as_str))
    .flatten()
}

pub(super) fn is_assistant_message(cell: &Value) -> bool {
    cell.get("kind").and_then(Value::as_str) == Some("assistantMessage")
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
