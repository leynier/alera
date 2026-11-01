//! Folds usage reports into the header's `usage`. Providers report usage in
//! parts (turn counts, live context fill, one rate-limit window at a time),
//! so each part keeps its last value until the provider reports it again.

use serde_json::{json, Map, Value};

use super::session::ChatSession;

/// Canonical event field and header wire key of each turn token count.
const COUNT_FIELDS: [(&str, &str); 4] = [
    ("inputTokens", "input"),
    ("outputTokens", "output"),
    ("cachedInputTokens", "cached"),
    ("reasoningTokens", "reasoning"),
];

/// Canonical event field and header wire key of the context group.
const CONTEXT_FIELDS: [(&str, &str); 3] = [
    ("contextTokens", "context"),
    ("contextWindow", "contextWindow"),
    ("autoCompactTokens", "autoCompact"),
];

impl ChatSession {
    pub(super) fn apply_token_usage(&mut self, usage: &Value) {
        let current = self
            .header
            .usage
            .as_ref()
            .and_then(|usage| usage.get("tokens"));
        if let Some(tokens) = merge_token_usage(current, usage) {
            self.header.usage.get_or_insert_with(|| json!({}))["tokens"] = tokens;
        }
    }

    pub(super) fn apply_usage_windows(&mut self, payload: &Value) {
        let current = self
            .header
            .usage
            .as_ref()
            .and_then(|usage| usage.get("windows"));
        if let Some(windows) = merge_usage_windows(current, &payload["limits"]["windows"]) {
            self.header.usage.get_or_insert_with(|| json!({}))["windows"] = windows;
        }
    }
}

/// Merges one usage report into the header tokens, or returns None when it
/// reports nothing. The turn counts are replaced together when the report
/// carries any of them. The context group is replaced together only when the
/// report carries a window: a live context tick can arrive before the window
/// is known (Claude's first turn after a resume), and it must not erase it.
pub(super) fn merge_token_usage(current: Option<&Value>, usage: &Value) -> Option<Value> {
    let counts = reported(usage, &COUNT_FIELDS);
    let context = reported(usage, &CONTEXT_FIELDS);
    if counts.is_empty() && context.is_empty() {
        return None;
    }
    let mut tokens = current
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    if !counts.is_empty() {
        remove_wire_keys(&mut tokens, &COUNT_FIELDS);
    }
    if context.contains_key("contextWindow") {
        remove_wire_keys(&mut tokens, &CONTEXT_FIELDS);
    }
    tokens.extend(counts);
    tokens.extend(context);
    Some(Value::Object(tokens))
}

/// Merges reported rate-limit windows into the header's by window id, or
/// returns None when nothing is reported. Codex sends partial snapshots and
/// Claude one window per event, so a window a report leaves out keeps its
/// last value and an empty list changes nothing.
pub(super) fn merge_usage_windows(current: Option<&Value>, incoming: &Value) -> Option<Value> {
    let mut merged = current
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut changed = false;
    for window in incoming.as_array().into_iter().flatten() {
        let Some(id) = window_id(window) else {
            continue;
        };
        match merged
            .iter_mut()
            .find(|existing| window_id(existing) == Some(id))
        {
            Some(existing) => *existing = window.clone(),
            None => merged.push(window.clone()),
        }
        changed = true;
    }
    changed.then_some(Value::Array(merged))
}

fn reported(usage: &Value, fields: &[(&str, &str)]) -> Map<String, Value> {
    fields
        .iter()
        .filter_map(|(canonical, wire)| {
            usage
                .get(canonical)
                .filter(|value| value.is_u64())
                .map(|value| ((*wire).to_string(), value.clone()))
        })
        .collect()
}

fn remove_wire_keys(tokens: &mut Map<String, Value>, fields: &[(&str, &str)]) {
    for (_, wire) in fields {
        tokens.remove(*wire);
    }
}

fn window_id(window: &Value) -> Option<&str> {
    window["id"].as_str().filter(|id| !id.is_empty())
}

#[cfg(test)]
#[path = "session_projection_usage_tests.rs"]
mod tests;
