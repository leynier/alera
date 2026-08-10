//! Projection of persisted app-server turns into Alera's bounded timeline.

use serde_json::{json, Value};

use super::codex_history_metadata::{
    apply_persisted_turn_timestamps, public_history_turn, record_history_completeness,
    HISTORY_ITEMS_COMPLETE,
};
use super::{bound_snapshot, normalize_snapshot, trim_events};

const HISTORY_CURSOR_PREFIX: &str = "turn-before:";
const HISTORY_ITEM_CURSOR_PREFIX: &str = "turn-items-before:";
const HISTORY_START_MARKER: &str = "__alera_history_page_start__";
const MAX_HISTORY_PAGE_ITEMS: usize = 96;
const MAX_HISTORY_SOURCE_BYTES: usize = 256 * 1024;

#[derive(Clone)]
pub(crate) struct CodexTurnHistoryPage {
    pub snapshot: Value,
    pub turns: Vec<Value>,
    pub next_cursor: Option<String>,
}

pub(crate) fn latest_turn_page(response: &Value, limit: usize) -> Option<CodexTurnHistoryPage> {
    turn_page(response, None, limit).ok()
}

pub(crate) fn older_turn_page(
    response: &Value,
    cursor: &str,
    limit: usize,
) -> Result<CodexTurnHistoryPage, &'static str> {
    turn_page(response, Some(cursor), limit)
}

fn turn_page(
    response: &Value,
    cursor: Option<&str>,
    limit: usize,
) -> Result<CodexTurnHistoryPage, &'static str> {
    let raw_turns = response
        .pointer("/thread/turns")
        .and_then(Value::as_array)
        .ok_or("Codex thread history is unavailable.")?;
    let normalized_turns = super::codex_review_transition::normalize_history_turns(raw_turns);
    let turns = normalized_turns.as_slice();
    let Some((mut turn_index, mut item_end)) = page_end(turns, cursor)? else {
        return Ok(CodexTurnHistoryPage {
            snapshot: project_turns(&[]),
            turns: Vec::new(),
            next_cursor: None,
        });
    };
    let mut page_turns = Vec::new();
    let mut page_snapshot = project_turns(&[]);
    let mut included_turns = 0;
    let mut next_cursor = None;
    loop {
        if item_end == 0 {
            if turn_has_projectable_status(&turns[turn_index]) {
                let turn = turns[turn_index].clone();
                if let Some(snapshot) = page_candidate_projection(&turn, &page_turns) {
                    page_turns.insert(0, turn);
                    page_snapshot = snapshot;
                    included_turns += 1;
                    if included_turns >= limit.max(1) {
                        next_cursor = cursor_before_turn(&turns[turn_index], turn_index > 0);
                        break;
                    }
                }
            }
            if turn_index == 0 {
                break;
            }
            turn_index -= 1;
            item_end = turn_item_count(&turns[turn_index]);
            continue;
        }
        let selected_items = page_turns.iter().map(turn_item_count).sum::<usize>();
        let remaining_items = MAX_HISTORY_PAGE_ITEMS.saturating_sub(selected_items);
        let selected_bytes = page_item_source_bytes(&page_turns);
        let remaining_bytes = MAX_HISTORY_SOURCE_BYTES.saturating_sub(selected_bytes);
        let budgeted_start = budgeted_item_suffix_start(
            &turns[turn_index],
            item_end,
            remaining_items,
            remaining_bytes,
        );
        if budgeted_start == item_end {
            next_cursor = cursor_before_items(&turns[turn_index], item_end, turn_index > 0);
            break;
        }
        let budgeted_prefix = turn_with_item_range(&turns[turn_index], budgeted_start, item_end);
        if let Some(snapshot) = page_candidate_projection(&budgeted_prefix, &page_turns) {
            page_turns.insert(0, budgeted_prefix);
            page_snapshot = snapshot;
            if budgeted_start > 0 {
                next_cursor =
                    cursor_before_items(&turns[turn_index], budgeted_start, turn_index > 0);
                break;
            }
            included_turns += 1;
            if included_turns >= limit.max(1) {
                next_cursor = cursor_before_turn(&turns[turn_index], turn_index > 0);
                break;
            }
            if turn_index == 0 {
                break;
            }
            turn_index -= 1;
            item_end = turn_item_count(&turns[turn_index]);
            continue;
        }

        if let Some((item_start, snapshot)) =
            first_fitting_item_suffix(&turns[turn_index], budgeted_start, item_end, &page_turns)
        {
            page_turns.insert(
                0,
                turn_with_item_range(&turns[turn_index], item_start, item_end),
            );
            page_snapshot = snapshot;
            next_cursor = cursor_before_items(&turns[turn_index], item_start, turn_index > 0);
        } else if page_turns.is_empty() {
            let item_start = item_end - 1;
            page_turns.push(turn_with_item_range(
                &turns[turn_index],
                item_start,
                item_end,
            ));
            page_snapshot = project_turns(&page_turns);
            next_cursor = cursor_before_items(&turns[turn_index], item_start, turn_index > 0);
        } else {
            next_cursor = cursor_before_items(&turns[turn_index], item_end, turn_index > 0);
        }
        break;
    }
    Ok(CodexTurnHistoryPage {
        snapshot: page_snapshot,
        turns: page_turns.into_iter().map(public_history_turn).collect(),
        next_cursor,
    })
}

fn page_end(turns: &[Value], cursor: Option<&str>) -> Result<Option<(usize, usize)>, &'static str> {
    if turns.is_empty() {
        return cursor.map_or(Ok(None), |_| Err("Codex history cursor is stale."));
    }
    let Some(cursor) = cursor else {
        let turn_index = turns.len() - 1;
        return Ok(Some((turn_index, turn_item_count(&turns[turn_index]))));
    };
    if let Some(turn_id) = cursor.strip_prefix(HISTORY_CURSOR_PREFIX) {
        let turn_index = turn_position(turns, turn_id)?;
        if turn_index == 0 {
            return Ok(None);
        }
        let previous = turn_index - 1;
        return Ok(Some((previous, turn_item_count(&turns[previous]))));
    }
    let value = cursor
        .strip_prefix(HISTORY_ITEM_CURSOR_PREFIX)
        .ok_or("Codex history cursor is invalid.")?;
    let (turn_id, item_end) = value
        .rsplit_once(':')
        .ok_or("Codex history cursor is invalid.")?;
    let item_end = item_end
        .parse::<usize>()
        .map_err(|_| "Codex history cursor is invalid.")?;
    let turn_index = turn_position(turns, turn_id)?;
    if item_end > turn_item_count(&turns[turn_index]) {
        return Err("Codex history cursor is stale.");
    }
    Ok(Some((turn_index, item_end)))
}

fn turn_position(turns: &[Value], turn_id: &str) -> Result<usize, &'static str> {
    if turn_id.trim().is_empty() {
        return Err("Codex history cursor is invalid.");
    }
    turns
        .iter()
        .position(|turn| turn.get("id").and_then(Value::as_str) == Some(turn_id))
        .ok_or("Codex history cursor is stale.")
}

fn turn_item_count(turn: &Value) -> usize {
    turn.get("items")
        .and_then(Value::as_array)
        .map_or(0, Vec::len)
}

fn turn_has_projectable_status(turn: &Value) -> bool {
    turn.get("id")
        .and_then(Value::as_str)
        .is_some_and(|turn_id| !turn_id.trim().is_empty())
        && matches!(
            turn.get("status").and_then(Value::as_str),
            Some("inProgress" | "completed" | "interrupted" | "failed")
        )
}

fn turn_with_item_range(turn: &Value, start: usize, end: usize) -> Value {
    let mut selected = turn.clone();
    let item_count = turn_item_count(turn);
    let items = turn
        .get("items")
        .and_then(Value::as_array)
        .map(|items| items[start..end].iter().map(bounded_history_item).collect())
        .unwrap_or_default();
    if let Some(object) = selected.as_object_mut() {
        object.insert("items".to_string(), Value::Array(items));
        object.insert(
            HISTORY_ITEMS_COMPLETE.to_string(),
            Value::Bool(start == 0 && end == item_count),
        );
    }
    selected
}

fn page_item_source_bytes(turns: &[Value]) -> usize {
    turns
        .iter()
        .flat_map(|turn| turn.get("items").and_then(Value::as_array))
        .flatten()
        .map(|item| serde_json::to_vec(item).map_or(0, |bytes| bytes.len()))
        .fold(0, usize::saturating_add)
}

fn budgeted_item_suffix_start(
    turn: &Value,
    item_end: usize,
    max_items: usize,
    max_bytes: usize,
) -> usize {
    if max_items == 0 {
        return item_end;
    }
    let Some(items) = turn.get("items").and_then(Value::as_array) else {
        return item_end;
    };
    let mut start = item_end;
    let mut bytes = 0_usize;
    while start > 0 && item_end - start < max_items {
        let item_bytes = history_item_source_bytes(&items[start - 1]);
        if bytes.saturating_add(item_bytes) > max_bytes {
            break;
        }
        start -= 1;
        bytes = bytes.saturating_add(item_bytes);
    }
    start
}

fn history_item_source_bytes(item: &Value) -> usize {
    serde_json::to_vec(&bounded_history_item(item)).map_or(usize::MAX, |value| value.len())
}

fn bounded_history_item(item: &Value) -> Value {
    if serde_json::to_vec(item).is_ok_and(|value| value.len() <= MAX_HISTORY_SOURCE_BYTES) {
        return item.clone();
    }
    let notice = "Historical item content was truncated because it exceeds the history size limit.";
    let mut bounded = serde_json::Map::new();
    if let Some(object) = item.as_object() {
        for key in [
            "id", "type", "status", "phase", "title", "name", "tool", "path", "cwd", "command",
        ] {
            let Some(value) = object.get(key) else {
                continue;
            };
            if serde_json::to_vec(value).is_ok_and(|bytes| bytes.len() <= 16 * 1024) {
                bounded.insert(key.to_string(), value.clone());
            }
        }
    }
    bounded.insert("text".to_string(), Value::String(notice.to_string()));
    bounded.insert(
        "aggregatedOutput".to_string(),
        Value::String(notice.to_string()),
    );
    bounded.insert(
        "content".to_string(),
        json!([{"type": "text", "text": notice}]),
    );
    bounded.insert("truncated".to_string(), Value::Bool(true));
    Value::Object(bounded)
}

fn first_fitting_item_suffix(
    turn: &Value,
    minimum_start: usize,
    item_end: usize,
    newer_turns: &[Value],
) -> Option<(usize, Value)> {
    let mut low = minimum_start;
    let mut high = item_end;
    while low < high {
        let middle = low + (high - low) / 2;
        let candidate = turn_with_item_range(turn, middle, item_end);
        if page_candidate_projection(&candidate, newer_turns).is_some() {
            high = middle;
        } else {
            low = middle + 1;
        }
    }
    if low >= item_end {
        return None;
    }
    let snapshot =
        page_candidate_projection(&turn_with_item_range(turn, low, item_end), newer_turns)?;
    Some((low, snapshot))
}

fn page_candidate_projection(older_turn: &Value, newer_turns: &[Value]) -> Option<Value> {
    let mut turns = Vec::with_capacity(newer_turns.len() + 1);
    turns.push(older_turn.clone());
    turns.extend_from_slice(newer_turns);
    project_turns_with_start_marker(&turns)
}

fn project_turns_with_start_marker(turns: &[Value]) -> Option<Value> {
    let mut snapshot = json!({
        "schemaVersion": 2,
        "events": [],
        "timelineCells": [{
            "id": HISTORY_START_MARKER,
            "kind": "progressText",
            "status": "completed",
        }],
        "pendingRequests": [],
    });
    for turn in turns {
        project_turn(&mut snapshot, turn);
    }
    super::codex_review_transition::restore_active_history_transition(&mut snapshot, turns);
    let mut snapshot = normalize_snapshot(snapshot);
    bound_snapshot(&mut snapshot);
    let cells = snapshot["timelineCells"].as_array_mut()?;
    let marker = cells
        .iter()
        .position(|cell| cell["id"] == HISTORY_START_MARKER)?;
    cells.remove(marker);
    Some(snapshot)
}

fn cursor_before_turn(turn: &Value, has_older_turns: bool) -> Option<String> {
    has_older_turns
        .then(|| turn.get("id").and_then(Value::as_str))
        .flatten()
        .filter(|turn_id| !turn_id.trim().is_empty())
        .map(|turn_id| format!("{HISTORY_CURSOR_PREFIX}{turn_id}"))
}

fn cursor_before_items(turn: &Value, item_end: usize, has_older_turns: bool) -> Option<String> {
    if item_end == 0 {
        return cursor_before_turn(turn, has_older_turns);
    }
    let turn_id = turn
        .get("id")
        .and_then(Value::as_str)
        .filter(|turn_id| !turn_id.trim().is_empty())?;
    Some(format!("{HISTORY_ITEM_CURSOR_PREFIX}{turn_id}:{item_end}"))
}

pub(super) fn project_turns(turns: &[Value]) -> Value {
    let mut snapshot = json!({
        "schemaVersion": 2,
        "events": [],
        "timelineCells": [],
        "pendingRequests": [],
    });
    let normalized_turns = super::codex_review_transition::normalize_history_turns(turns);
    for turn in &normalized_turns {
        project_turn(&mut snapshot, turn);
    }
    super::codex_review_transition::restore_active_history_transition(&mut snapshot, turns);
    let mut snapshot = normalize_snapshot(snapshot);
    bound_snapshot(&mut snapshot);
    snapshot
}

fn project_turn(snapshot: &mut Value, turn: &Value) {
    let Some(turn_id) = turn.get("id").and_then(Value::as_str) else {
        return;
    };
    if turn_id.trim().is_empty() {
        return;
    }
    record_history_completeness(snapshot, turn_id, turn);
    let turn = public_history_turn(turn.clone());
    append_event(
        snapshot,
        json!({
            "method": "turn/started",
            "params": {
                "turnId": turn_id,
                "turn": &turn,
            },
        }),
    );
    if let Some(items) = turn.get("items").and_then(Value::as_array) {
        for item in items {
            let item_id = item.get("id").and_then(Value::as_str).unwrap_or_default();
            append_event(
                snapshot,
                json!({
                    "method": projected_item_method(item),
                    "params": {
                        "turnId": turn_id,
                        "itemId": item_id,
                        "item": item,
                    },
                }),
            );
        }
    }
    let status = turn
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if status == "failed"
        && turn
            .get("items")
            .and_then(Value::as_array)
            .is_none_or(Vec::is_empty)
    {
        append_event(
            snapshot,
            json!({
                "method": "error",
                "params": {
                    "turnId": turn_id,
                    "message": persisted_turn_failure_message(&turn),
                },
            }),
        );
    }
    if let Some(method) = terminal_turn_method(status) {
        append_event(
            snapshot,
            json!({
                "method": method,
                "params": {
                    "turnId": turn_id,
                    "turn": turn,
                },
            }),
        );
    }
    apply_persisted_turn_timestamps(snapshot, turn_id, &turn);
}

fn persisted_turn_failure_message(turn: &Value) -> &str {
    turn.pointer("/error/message")
        .or_else(|| turn.get("error"))
        .and_then(Value::as_str)
        .filter(|message| !message.trim().is_empty())
        .unwrap_or("The Codex turn failed before producing output.")
}

fn projected_item_method(item: &Value) -> &'static str {
    match item.get("status").and_then(Value::as_str) {
        Some("inProgress" | "pending" | "running") => "item/started",
        _ => "item/completed",
    }
}

fn terminal_turn_method(status: &str) -> Option<&'static str> {
    match status {
        "inProgress" => None,
        "failed" => Some("turn/failed"),
        "aborted" => Some("turn/aborted"),
        "interrupted" | "cancelled" | "canceled" => Some("turn/interrupted"),
        _ => Some("turn/completed"),
    }
}

fn append_event(snapshot: &mut Value, event: Value) {
    if let Some(events) = snapshot.get_mut("events").and_then(Value::as_array_mut) {
        events.push(event.clone());
        trim_events(events);
    }
    super::codex_timeline_state::reduce_timeline(snapshot, &event);
    super::update_turn_and_pending(snapshot, &event);
}

#[cfg(test)]
#[path = "codex_history_projection_tests.rs"]
mod tests;
