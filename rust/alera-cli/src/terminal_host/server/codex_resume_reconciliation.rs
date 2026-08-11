//! Cell lookup for merging persisted and freshly resumed timelines.

use std::collections::{HashMap, HashSet};

use serde_json::Value;

use super::codex_resume_identity::{
    has_explicit_stream_phase, message_identity_key, messages_are_prefix_compatible,
    phase_agnostic_agent_message_identity_key,
};

pub(super) fn cell_indexes(cells: &[Value]) -> HashMap<String, Vec<usize>> {
    let mut indexes = HashMap::new();
    for (index, cell) in cells.iter().enumerate() {
        index_cell(&mut indexes, cell, index);
    }
    indexes
}

pub(super) fn matching_cell_index(
    stored: &[Value],
    indexes: &HashMap<String, Vec<usize>>,
    claimed: &HashSet<usize>,
    cell: &Value,
) -> Option<usize> {
    let candidates = [
        cell_id(cell).map(|id| format!("id:{id}")),
        user_message_turn_id(cell).map(|turn_id| format!("legacy-user-turn:{turn_id}")),
        message_identity_key(cell),
    ];
    let exact = candidates
        .into_iter()
        .flatten()
        .find_map(|key| first_unclaimed_index(indexes, claimed, &key));
    exact
        .or_else(|| phase_agnostic_cell_index(indexes, claimed, cell))
        .or_else(|| unique_prefix_compatible_index(stored, claimed, cell))
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
    if let Some(key) = phase_agnostic_agent_message_identity_key(cell) {
        indexes
            .entry(any_phase_index_key(&key))
            .or_default()
            .push(index);
        if !has_explicit_stream_phase(cell) {
            indexes.entry(key).or_default().push(index);
        }
    }
}

fn phase_agnostic_cell_index(
    indexes: &HashMap<String, Vec<usize>>,
    claimed: &HashSet<usize>,
    resumed: &Value,
) -> Option<usize> {
    let key = phase_agnostic_agent_message_identity_key(resumed)?;
    if has_explicit_stream_phase(resumed) {
        return first_unclaimed_index(indexes, claimed, &key);
    }
    unique_unclaimed_index(indexes, claimed, &any_phase_index_key(&key))
}

fn any_phase_index_key(key: &str) -> String {
    format!("any-phase:{key}")
}

fn unique_prefix_compatible_index(
    stored: &[Value],
    claimed: &HashSet<usize>,
    resumed: &Value,
) -> Option<usize> {
    let mut matches = stored
        .iter()
        .enumerate()
        .filter(|(index, stored)| {
            !claimed.contains(index) && messages_are_prefix_compatible(stored, resumed)
        })
        .map(|(index, _)| index);
    let first = matches.next()?;
    matches.next().is_none().then_some(first)
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

fn unique_unclaimed_index(
    indexes: &HashMap<String, Vec<usize>>,
    claimed: &HashSet<usize>,
    key: &str,
) -> Option<usize> {
    let mut matches = indexes
        .get(key)
        .into_iter()
        .flatten()
        .copied()
        .filter(|index| !claimed.contains(index));
    let first = matches.next()?;
    matches.next().is_none().then_some(first)
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

fn cell_id(cell: &Value) -> Option<&str> {
    cell.get("id").and_then(Value::as_str)
}
