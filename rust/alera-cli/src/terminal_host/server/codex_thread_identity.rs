use alera_core::runtime::WorkspaceTabRecord;
#[cfg(test)]
use serde_json::json;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_state::{persist_snapshot, snapshot, tab_thread_id};

pub(super) fn ensure_expected_thread(
    payload: &Value,
    actual_thread_id: Option<&str>,
) -> HostResult<()> {
    let Some(expected) = payload.get("expectedThreadId") else {
        return Ok(());
    };
    let expected_thread_id = expected.as_str();
    if expected_thread_id == actual_thread_id {
        return Ok(());
    }
    Err(HostError::state(
        "The Codex conversation changed before this message was sent. Review the current conversation and try again.",
    ))
}

pub(super) fn pending_thread_name(tab: &WorkspaceTabRecord) -> Option<String> {
    if tab_thread_id(tab).is_some() {
        return None;
    }
    snapshot(tab)
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn apply_manual_thread_title(tab: &mut WorkspaceTabRecord, title: &str) {
    let mut next_snapshot = snapshot(tab);
    if let Some(snapshot) = next_snapshot.as_object_mut() {
        snapshot.insert("title".to_string(), Value::String(title.to_string()));
    }
    tab.title = title.to_string();
    if let Some(payload) = tab.payload.as_object_mut() {
        payload.insert("manualTitle".to_string(), Value::Bool(true));
    }
    persist_snapshot(tab, next_snapshot);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_a_turn_for_a_replaced_thread() {
        let payload = json!({"expectedThreadId": "thread-old"});

        assert!(ensure_expected_thread(&payload, Some("thread-new")).is_err());
    }

    #[test]
    fn distinguishes_an_expected_empty_tab_from_a_created_thread() {
        let payload = json!({"expectedThreadId": null});

        assert!(ensure_expected_thread(&payload, None).is_ok());
        assert!(ensure_expected_thread(&payload, Some("thread-new")).is_err());
    }

    #[test]
    fn keeps_legacy_turns_without_a_precondition_compatible() {
        assert!(ensure_expected_thread(&json!({}), Some("thread")).is_ok());
    }
}
