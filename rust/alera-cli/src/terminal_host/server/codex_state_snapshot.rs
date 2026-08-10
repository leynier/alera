use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};

use super::codex_resume_identity::{
    complete_history_turn_ids, is_assistant_message, message_identity_key, message_turn_id,
};
use super::{
    active_turn_id, CODEX_SNAPSHOT_VERSION, MAX_SNAPSHOT_BYTES, MAX_SNAPSHOT_CELLS,
    MAX_SNAPSHOT_EVENTS,
};

pub(super) fn update_context_usage(object: &mut Map<String, Value>, message: &Value, method: &str) {
    if !method.to_lowercase().contains("token") && method != "token_count" {
        return;
    }
    let token_usage = message.pointer("/params/tokenUsage");
    let last_usage = token_usage.and_then(|usage| usage.get("last"));
    let total_usage = token_usage.and_then(|usage| usage.get("total"));
    let candidates = [
        last_usage.and_then(|usage| usage.get("totalTokens")),
        last_usage.and_then(|usage| usage.get("total_tokens")),
        message.pointer("/params/tokenUsage/totalTokens"),
        message.pointer("/params/tokenUsage/total_tokens"),
        token_usage.and_then(|usage| usage.pointer("/total/totalTokens")),
        token_usage.and_then(|usage| usage.pointer("/total/total_tokens")),
        message.pointer("/params/usage/totalTokens"),
        message.pointer("/params/totalTokens"),
        message.pointer("/params/total_tokens"),
        message.pointer("/params/msg/total_tokens"),
    ];
    if let Some(value) = candidates
        .into_iter()
        .flatten()
        .find_map(Value::as_i64)
        .or_else(|| usage_component_total(last_usage))
        .or_else(|| usage_component_total(total_usage))
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

fn usage_component_total(usage: Option<&Value>) -> Option<i64> {
    let usage = usage?;
    let input = usage
        .get("inputTokens")
        .or_else(|| usage.get("input_tokens"))
        .and_then(Value::as_i64)
        .unwrap_or_default();
    let output = usage
        .get("outputTokens")
        .or_else(|| usage.get("output_tokens"))
        .and_then(Value::as_i64)
        .unwrap_or_default();
    let total = input.saturating_add(output);
    (total > 0).then_some(total)
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

pub(crate) fn snapshot_delta(previous: &Value, next: &Value, messages: &[Value]) -> Value {
    let previous_cells = cells_by_id(previous);
    let next_cells = next
        .get("timelineCells")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let timeline_upserts = next_cells
        .iter()
        .filter(|cell| {
            cell_id(cell).is_none_or(|id| previous_cells.get(id).copied() != Some(*cell))
        })
        .cloned()
        .collect::<Vec<_>>();
    // Timeline reducers only append or upsert cells. A missing cell here is an
    // eviction from the bounded live window, not a semantic deletion from a
    // client's expanded history.
    let timeline_removed_ids = Vec::new();
    let mut delta = Map::from_iter([
        (
            "timelineUpserts".to_string(),
            Value::Array(timeline_upserts),
        ),
        (
            "timelineRemovedIds".to_string(),
            Value::Array(timeline_removed_ids),
        ),
        ("eventsAppend".to_string(), Value::Array(messages.to_vec())),
        (
            "eventLimit".to_string(),
            Value::Number(super::MAX_SNAPSHOT_EVENTS.into()),
        ),
    ]);
    let mut expected_events = previous
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    expected_events.extend_from_slice(messages);
    trim_events(&mut expected_events);
    let retained_events = next
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if retained_events != expected_events {
        delta.insert("eventsAppend".to_string(), Value::Array(Vec::new()));
        delta.insert("eventsReplace".to_string(), Value::Array(retained_events));
    }
    for key in ["activeTurnId", "contextUsed", "contextLimit", "title"] {
        delta.insert(
            key.to_string(),
            next.get(key).cloned().unwrap_or(Value::Null),
        );
    }
    if previous.get("pendingRequests") != next.get("pendingRequests") {
        delta.insert(
            "pendingRequests".to_string(),
            next.get("pendingRequests")
                .cloned()
                .unwrap_or_else(|| Value::Array(Vec::new())),
        );
    }
    Value::Object(delta)
}

pub(in crate::terminal_host::server) fn merge_resume_snapshot(
    stored: &Value,
    resumed: Value,
) -> Value {
    let Some(stored_cells) = stored.get("timelineCells").and_then(Value::as_array) else {
        return normalize_snapshot(resumed);
    };
    let mut next = normalize_snapshot(resumed);
    let complete_history_turns = complete_history_turn_ids(&next);
    let resumed_has_title = next
        .get("title")
        .and_then(Value::as_str)
        .is_some_and(|value| !value.trim().is_empty());
    if !resumed_has_title {
        if let Some(title) = stored
            .get("title")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
        {
            next["title"] = Value::String(title.to_string());
        }
    }
    let resumed_cells = next
        .get_mut("timelineCells")
        .and_then(Value::as_array_mut)
        .expect("normalized snapshots contain timeline cells");
    let merged = if let Some(boundary) = stored_cells.iter().rposition(is_context_boundary) {
        let mut cells = stored_cells[..=boundary].to_vec();
        cells.extend(merge_cells_in_resumed_order(
            &stored_cells[boundary + 1..],
            std::mem::take(resumed_cells),
            false,
            &complete_history_turns,
        ));
        cells
    } else {
        merge_cells_in_resumed_order(
            stored_cells,
            std::mem::take(resumed_cells),
            true,
            &complete_history_turns,
        )
    };
    *resumed_cells = merged;
    bound_snapshot(&mut next);
    next
}

fn merge_cells_in_resumed_order(
    stored: &[Value],
    resumed: Vec<Value>,
    preserve_all_stored: bool,
    complete_history_turns: &HashSet<String>,
) -> Vec<Value> {
    let stored_indexes = cell_indexes(stored);
    let mut claimed_stored = HashSet::new();
    let mut matches = Vec::with_capacity(resumed.len());
    for cell in &resumed {
        let index = matching_cell_index(&stored_indexes, &claimed_stored, cell);
        if let Some(index) = index {
            claimed_stored.insert(index);
        }
        matches.push(index);
    }
    for cell in &resumed {
        if let Some(id) = cell_id(cell) {
            if let Some(indexes) = stored_indexes.get(&format!("id:{id}")) {
                claimed_stored.extend(indexes);
            }
        }
        if is_assistant_message(cell)
            && message_turn_id(cell).is_some_and(|turn_id| complete_history_turns.contains(turn_id))
        {
            if let Some(key) = message_identity_key(cell) {
                if let Some(indexes) = stored_indexes.get(&key) {
                    claimed_stored.extend(indexes);
                }
            }
        }
    }
    let mut merged = Vec::new();
    let mut stored_cursor = 0;
    for (cell, stored_index) in resumed.into_iter().zip(matches) {
        if let Some(index) = stored_index.filter(|index| *index >= stored_cursor) {
            merged.extend(
                stored[stored_cursor..index]
                    .iter()
                    .enumerate()
                    .filter(|(offset, cell)| {
                        !claimed_stored.contains(&(stored_cursor + offset))
                            && (preserve_all_stored || is_alera_owned_cell(cell))
                    })
                    .map(|(_, cell)| cell)
                    .cloned(),
            );
            merged.push(merge_resumed_cell(&stored[index], cell));
            stored_cursor = index + 1;
        } else if let Some(index) = stored_index {
            merged.push(merge_resumed_cell(&stored[index], cell));
        } else {
            merged.push(cell);
        }
    }
    merged.extend(
        stored[stored_cursor..]
            .iter()
            .enumerate()
            .filter(|(offset, cell)| {
                !claimed_stored.contains(&(stored_cursor + offset))
                    && (preserve_all_stored || is_alera_owned_cell(cell))
            })
            .map(|(_, cell)| cell)
            .cloned(),
    );
    merged
}

fn cell_indexes(cells: &[Value]) -> HashMap<String, Vec<usize>> {
    let mut indexes = HashMap::new();
    for (index, cell) in cells.iter().enumerate() {
        index_cell(&mut indexes, cell, index);
    }
    indexes
}

fn index_cell(indexes: &mut HashMap<String, Vec<usize>>, cell: &Value, index: usize) {
    if let Some(id) = cell_id(cell) {
        indexes.entry(format!("id:{id}")).or_default().push(index);
    }
    if let Some(turn_id) = legacy_user_message_turn_id(cell) {
        indexes
            .entry(format!("legacy-user-turn:{turn_id}"))
            .or_default()
            .push(index);
    }
    if let Some(key) = message_identity_key(cell) {
        indexes.entry(key).or_default().push(index);
    }
}

fn matching_cell_index(
    indexes: &HashMap<String, Vec<usize>>,
    claimed: &HashSet<usize>,
    cell: &Value,
) -> Option<usize> {
    let candidates = [
        cell_id(cell).map(|id| format!("id:{id}")),
        user_message_turn_id(cell).map(|turn_id| format!("legacy-user-turn:{turn_id}")),
        message_identity_key(cell),
    ];
    candidates
        .into_iter()
        .flatten()
        .find_map(|key| first_unclaimed_index(indexes, claimed, &key))
}

fn first_unclaimed_index(
    indexes: &HashMap<String, Vec<usize>>,
    claimed: &HashSet<usize>,
    key: &str,
) -> Option<usize> {
    indexes
        .get(key)
        .into_iter()
        .flatten()
        .copied()
        .find(|index| !claimed.contains(index))
}

fn legacy_user_message_turn_id(cell: &Value) -> Option<&str> {
    let turn_id = user_message_turn_id(cell)?;
    cell_id(cell)
        .and_then(|id| id.strip_prefix("user-"))
        .is_some_and(|legacy_turn_id| legacy_turn_id == turn_id)
        .then_some(turn_id)
}

fn user_message_turn_id(cell: &Value) -> Option<&str> {
    (cell.get("kind").and_then(Value::as_str) == Some("userMessage"))
        .then(|| cell.get("turnId").and_then(Value::as_str))
        .flatten()
}

fn is_alera_owned_cell(cell: &Value) -> bool {
    if cell.get("kind").and_then(Value::as_str) == Some("questionAnswer") {
        return true;
    }
    cell.get("kind").and_then(Value::as_str) == Some("userMessage")
        && cell.get("metadata").is_some_and(|metadata| {
            metadata.get("clientUserMessageId").is_some()
                || metadata
                    .get("attachments")
                    .and_then(Value::as_array)
                    .is_some_and(|attachments| !attachments.is_empty())
        })
}

fn merge_resumed_cell(stored: &Value, mut resumed: Value) -> Value {
    let stores_user_presentation = stored.get("kind").and_then(Value::as_str)
        == Some("userMessage")
        && resumed.get("kind").and_then(Value::as_str) == Some("userMessage")
        && stored.get("metadata").is_some_and(|metadata| {
            metadata.get("clientUserMessageId").is_some()
                || metadata
                    .get("attachments")
                    .and_then(Value::as_array)
                    .is_some()
        });
    if !stores_user_presentation {
        return resumed;
    }
    let Some(resumed_map) = resumed.as_object_mut() else {
        return resumed;
    };
    for key in ["createdAt", "markdownText", "renderedMarkdownText"] {
        if let Some(value) = stored.get(key) {
            resumed_map.insert(key.to_string(), value.clone());
        }
    }
    let mut metadata = resumed_map
        .remove("metadata")
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default();
    if let Some(stored_metadata) = stored.get("metadata").and_then(Value::as_object) {
        for key in ["attachments", "clientUserMessageId", "isSteering"] {
            if let Some(value) = stored_metadata.get(key) {
                metadata.insert(key.to_string(), value.clone());
            }
        }
    }
    resumed_map.insert("metadata".to_string(), Value::Object(metadata));
    resumed
}

fn is_context_boundary(cell: &Value) -> bool {
    matches!(
        cell.pointer("/metadata/noticeType").and_then(Value::as_str),
        Some("threadBoundary" | "contextReset")
    )
}

fn cells_by_id(snapshot: &Value) -> HashMap<&str, &Value> {
    snapshot
        .get("timelineCells")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|cell| cell_id(cell).map(|id| (id, cell)))
        .collect()
}

fn cell_id(cell: &Value) -> Option<&str> {
    cell.get("id").and_then(Value::as_str)
}

pub(super) fn bound_snapshot(snapshot: &mut Value) {
    if let Some(events) = snapshot.get_mut("events").and_then(Value::as_array_mut) {
        trim_events(events);
    }
    if let Some(cells) = snapshot
        .get_mut("timelineCells")
        .and_then(Value::as_array_mut)
    {
        trim_cells(cells);
    }
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
            .filter(|events| !events.is_empty())
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
