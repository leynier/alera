use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{Map, Value};

use super::{
    active_turn_id, CODEX_SNAPSHOT_VERSION, MAX_SNAPSHOT_BYTES, MAX_SNAPSHOT_CELLS,
    MAX_SNAPSHOT_EVENTS,
};

pub(super) fn update_context_usage(object: &mut Map<String, Value>, message: &Value, method: &str) {
    if !method.to_lowercase().contains("token") && method != "token_count" {
        return;
    }
    let token_usage = message.pointer("/params/tokenUsage");
    let total_usage = token_usage.and_then(|usage| usage.get("total"));
    let candidates = [
        message.pointer("/params/tokenUsage/totalTokens"),
        message.pointer("/params/tokenUsage/total_tokens"),
        token_usage.and_then(|usage| usage.pointer("/total/totalTokens")),
        token_usage.and_then(|usage| usage.pointer("/total/total_tokens")),
        message.pointer("/params/usage/totalTokens"),
        message.pointer("/params/totalTokens"),
        message.pointer("/params/total_tokens"),
        message.pointer("/params/msg/total_tokens"),
    ];
    let component_total = [
        "inputTokens",
        "input_tokens",
        "cachedInputTokens",
        "cached_input_tokens",
        "outputTokens",
        "output_tokens",
        "reasoningOutputTokens",
        "reasoning_output_tokens",
    ]
    .into_iter()
    .filter_map(|key| {
        total_usage
            .and_then(|usage| usage.get(key))
            .and_then(Value::as_i64)
    })
    .sum::<i64>();
    if let Some(value) = candidates
        .into_iter()
        .flatten()
        .find_map(Value::as_i64)
        .or_else(|| (component_total > 0).then_some(component_total))
    {
        object.insert("contextUsed".to_string(), Value::Number(value.into()));
    }
    let limits = [
        message.pointer("/params/tokenUsage/contextWindow"),
        message.pointer("/params/tokenUsage/contextWindowTokens"),
        message.pointer("/params/tokenUsage/context_window"),
        message.pointer("/params/tokenUsage/modelContextWindow"),
        message.pointer("/params/contextWindow"),
        message.pointer("/params/context_window"),
    ];
    if let Some(value) = limits.into_iter().flatten().find_map(Value::as_i64) {
        object.insert("contextLimit".to_string(), Value::Number(value.into()));
    }
}

pub(super) fn normalize_snapshot(mut value: Value) -> Value {
    let object = ensure_payload_object(&mut value);
    object.insert(
        "schemaVersion".to_string(),
        Value::Number(CODEX_SNAPSHOT_VERSION.into()),
    );
    object
        .entry("events".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    object
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    object
        .entry("pendingRequests".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    value
}

pub(super) fn bound_snapshot(snapshot: &mut Value) {
    loop {
        let too_large = serde_json::to_vec(snapshot)
            .map(|bytes| bytes.len() > MAX_SNAPSHOT_BYTES)
            .unwrap_or(false);
        if !too_large {
            break;
        }
        let removed_event = snapshot
            .get_mut("events")
            .and_then(Value::as_array_mut)
            .filter(|events| events.len() > 1)
            .map(|events| events.remove(0));
        if removed_event.is_some() {
            continue;
        }
        let removed_cell = snapshot
            .get_mut("timelineCells")
            .and_then(Value::as_array_mut)
            .filter(|cells| cells.len() > 1)
            .map(|cells| cells.remove(0));
        if removed_cell.is_none() {
            break;
        }
    }
}

pub(super) fn persist_snapshot(tab: &mut WorkspaceTabRecord, next: Value) {
    let active_turn = active_turn_id(&next);
    if let Some(payload) = tab.payload.as_object_mut() {
        payload.insert("codexSnapshot".to_string(), next);
        match active_turn {
            Some(turn_id) => {
                payload.insert("codexActiveTurnId".to_string(), Value::String(turn_id));
            }
            None => {
                payload.remove("codexActiveTurnId");
            }
        }
    }
    tab.updated_at = Utc::now();
}

pub(super) fn trim_events(events: &mut Vec<Value>) {
    if events.len() > MAX_SNAPSHOT_EVENTS {
        let excess = events.len() - MAX_SNAPSHOT_EVENTS;
        events.drain(0..excess);
    }
}

pub(super) fn trim_cells(cells: &mut Vec<Value>) {
    if cells.len() > MAX_SNAPSHOT_CELLS {
        let excess = cells.len() - MAX_SNAPSHOT_CELLS;
        cells.drain(0..excess);
    }
}

pub(super) fn ensure_payload_object(value: &mut Value) -> &mut Map<String, Value> {
    if !value.is_object() {
        *value = Value::Object(Map::new());
    }
    value
        .as_object_mut()
        .expect("value was normalized to an object")
}
