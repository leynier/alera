//! Internal metadata retained while projecting bounded Codex history pages.

use chrono::{SecondsFormat, TimeZone, Utc};
use serde_json::Value;

pub(super) const HISTORY_ITEMS_COMPLETE: &str = "aleraHistoryItemsComplete";
const COMPLETE_HISTORY_TURN_IDS: &str = "completeHistoryTurnIds";

pub(super) fn record_history_completeness(snapshot: &mut Value, turn_id: &str, turn: &Value) {
    if turn.get(HISTORY_ITEMS_COMPLETE).and_then(Value::as_bool) != Some(true) {
        return;
    }
    let object = snapshot
        .as_object_mut()
        .expect("history snapshots are objects");
    let turn_ids = object
        .entry(COMPLETE_HISTORY_TURN_IDS.to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    if let Some(turn_ids) = turn_ids.as_array_mut() {
        turn_ids.push(Value::String(turn_id.to_string()));
    }
}

pub(super) fn public_history_turn(mut turn: Value) -> Value {
    if let Some(object) = turn.as_object_mut() {
        object.remove(HISTORY_ITEMS_COMPLETE);
    }
    turn
}

pub(super) fn apply_persisted_turn_timestamps(snapshot: &mut Value, turn_id: &str, turn: &Value) {
    let started_at = turn_timestamp(turn, "startedAt");
    let completed_at = turn_timestamp(turn, "completedAt");
    if started_at.is_none() && completed_at.is_none() {
        return;
    }
    let Some(cells) = snapshot
        .get_mut("timelineCells")
        .and_then(Value::as_array_mut)
    else {
        return;
    };
    for cell in cells
        .iter_mut()
        .filter(|cell| cell.get("turnId").and_then(Value::as_str) == Some(turn_id))
    {
        let Some(cell) = cell.as_object_mut() else {
            continue;
        };
        if let Some(started_at) = started_at.as_ref() {
            cell.insert("createdAt".to_string(), Value::String(started_at.clone()));
        }
        if let Some(updated_at) = completed_at.as_ref().or(started_at.as_ref()) {
            cell.insert("updatedAt".to_string(), Value::String(updated_at.clone()));
        }
    }
}

fn turn_timestamp(turn: &Value, key: &str) -> Option<String> {
    let seconds = turn.get(key)?.as_i64()?;
    Utc.timestamp_opt(seconds, 0)
        .single()
        .map(|value| value.to_rfc3339_opts(SecondsFormat::Secs, true))
}
