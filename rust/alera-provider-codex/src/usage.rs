//! Codex usage reports: live context fill from `thread/tokenUsage/updated`,
//! and rate-limit windows that only report a change, as T3 Code c3f5e363e5.

use crate::provider::CodexProvider;
use serde_json::{json, Value};
use std::collections::HashMap;

/// The canonical usage of a token tick: the turn's latest counts and the
/// context the thread holds now (`last.totalTokens`, not the cumulative
/// total) against the model's window.
pub(crate) fn thread_token_usage(params: &Value) -> Value {
    let usage = params.get("tokenUsage").unwrap_or(&Value::Null);
    let last = usage.get("last").unwrap_or(&Value::Null);
    let mut payload = json!({
        "usageStatus": "partial",
        "usageScope": "main_agent",
        "hasSubagents": false,
    });
    for (native, canonical) in [
        ("inputTokens", "inputTokens"),
        ("cachedInputTokens", "cachedInputTokens"),
        ("outputTokens", "outputTokens"),
        ("reasoningOutputTokens", "reasoningTokens"),
        ("totalTokens", "contextTokens"),
    ] {
        if let Some(value) = last.get(native).filter(|value| value.is_u64()) {
            payload[canonical] = value.clone();
        }
    }
    if let Some(window) = usage
        .get("modelContextWindow")
        .and_then(Value::as_u64)
        .filter(|window| *window > 0)
    {
        payload["contextWindow"] = json!(window);
    }
    payload
}

/// The fields that make two reports of one window differ.
const WINDOW_FIELDS: [&str; 4] = ["kind", "usedPercent", "resetsAt", "windowDurationMins"];

/// The last reported state of each rate-limit window, by id.
#[derive(Debug, Default)]
pub(crate) struct RateWindows {
    last: HashMap<String, Value>,
}

impl RateWindows {
    /// Keeps only the windows that changed since their last report. Codex
    /// repeats its cached snapshot on every token tick, which must not
    /// overwrite a newer view of the same window.
    pub(crate) fn changed(&mut self, payload: &mut Value) {
        let Some(windows) = payload
            .get_mut("limits")
            .and_then(|limits| limits.get_mut("windows"))
            .and_then(Value::as_array_mut)
        else {
            return;
        };
        windows.retain(|window| {
            let Some(id) = window["id"].as_str() else {
                return true;
            };
            let state = WINDOW_FIELDS
                .iter()
                .map(|field| window.get(*field).cloned().unwrap_or(Value::Null))
                .collect::<Value>();
            self.last.insert(id.to_owned(), state.clone()) != Some(state)
        });
    }
}

impl<T> CodexProvider<T> {
    pub(crate) fn report_changed_windows(&mut self, payload: &mut Value) {
        self.rate_windows.changed(payload);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_tick_reports_the_current_context() {
        let params = json!({"tokenUsage": {
            "total": {"totalTokens": 900},
            "last": {"totalTokens": 300, "inputTokens": 200, "cachedInputTokens": 50,
                     "outputTokens": 100, "reasoningOutputTokens": 20},
            "modelContextWindow": 1000,
        }});
        let usage = thread_token_usage(&params);
        assert_eq!(usage["contextTokens"], 300);
        assert_eq!(usage["contextWindow"], 1000);
        assert_eq!(usage["inputTokens"], 200);
        assert_eq!(usage["reasoningTokens"], 20);
        assert!(thread_token_usage(&json!({}))
            .get("contextTokens")
            .is_none());
    }

    #[test]
    fn only_changed_windows_are_reported_again() {
        let report = |used: f64| {
            json!({"limits": {"windows": [
                {"id": "primary", "kind": "session", "usedPercent": used},
                {"id": "secondary", "kind": "weekly", "usedPercent": 10.0},
            ]}})
        };
        let mut windows = RateWindows::default();
        let mut first = report(50.0);
        windows.changed(&mut first);
        assert_eq!(first["limits"]["windows"].as_array().unwrap().len(), 2);
        let mut repeat = report(50.0);
        windows.changed(&mut repeat);
        assert_eq!(repeat["limits"]["windows"], json!([]));
        let mut moved = report(60.0);
        windows.changed(&mut moved);
        assert_eq!(moved["limits"]["windows"][0]["usedPercent"], 60.0);
        assert_eq!(moved["limits"]["windows"].as_array().unwrap().len(), 1);
    }
}
