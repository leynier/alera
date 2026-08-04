//! Content extraction and turn metrics for Codex timeline cells.

use serde_json::{json, Value};

use super::codex_timeline_cells::first_string;

pub(super) fn update_turn_separator_metrics(
    cells: &mut [Value],
    turn_id: &str,
    params: &Value,
    now: &str,
) {
    let turn = params.get("turn").unwrap_or(&Value::Null);
    let duration = turn
        .get("durationMs")
        .cloned()
        .or_else(|| duration_from_separator(cells, turn_id, now));
    let Some(separator) = cells.iter_mut().find(|cell| {
        cell.get("kind").and_then(Value::as_str) == Some("turnSeparator")
            && cell.get("turnId").and_then(Value::as_str) == Some(turn_id)
    }) else {
        return;
    };
    let Some(map) = separator.as_object_mut() else {
        return;
    };
    map.insert("updatedAt".to_string(), Value::String(now.to_string()));
    let metadata = map
        .entry("metadata")
        .or_insert_with(|| json!({}))
        .as_object_mut();
    if let Some(metadata) = metadata {
        metadata.insert(
            "startedAt".to_string(),
            turn.get("startedAt").cloned().unwrap_or(Value::Null),
        );
        metadata.insert(
            "completedAt".to_string(),
            turn.get("completedAt").cloned().unwrap_or(Value::Null),
        );
        if let Some(duration) = duration {
            metadata.insert("computedDurationMs".to_string(), duration);
        }
    }
}

fn duration_from_separator(cells: &[Value], turn_id: &str, now: &str) -> Option<Value> {
    let started = cells.iter().find(|cell| {
        cell.get("kind").and_then(Value::as_str) == Some("turnSeparator")
            && cell.get("turnId").and_then(Value::as_str) == Some(turn_id)
    })?;
    let started = started.get("createdAt")?.as_str()?;
    let started = chrono::DateTime::parse_from_rfc3339(started).ok()?;
    let completed = chrono::DateTime::parse_from_rfc3339(now).ok()?;
    Some(json!((completed - started).num_milliseconds().max(0)))
}

pub(super) fn item_markdown(item: &Value) -> String {
    let direct = first_string(&[item.get("text"), item.get("message")]);
    if !direct.is_empty() {
        return direct;
    }
    for key in ["summary", "content", "fragments"] {
        let Some(values) = item.get(key).and_then(Value::as_array) else {
            continue;
        };
        let text = values
            .iter()
            .filter_map(|value| {
                value
                    .as_str()
                    .or_else(|| value.get("text").and_then(Value::as_str))
            })
            .collect::<Vec<_>>()
            .join("\n");
        if !text.is_empty() {
            return text;
        }
    }
    first_string(&[item.get("review")])
}

pub(super) fn item_details(item: &Value) -> String {
    for key in [
        "aggregatedOutput",
        "output",
        "result",
        "error",
        "diff",
        "commandOutput",
        "changes",
        "contentItems",
        "action",
    ] {
        let Some(value) = item.get(key).filter(|value| !value.is_null()) else {
            continue;
        };
        if let Some(text) = value.as_str() {
            if !text.is_empty() {
                return text.to_string();
            }
        } else {
            return value.to_string();
        }
    }
    String::new()
}
