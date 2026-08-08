//! Durable per-tab configuration and recovery helpers for Codex chat tabs.

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Map, Value};

const CONFIGURATION_KEY: &str = "codexConfiguration";
const ACTIVE_CWD_KEY: &str = "codexCwd";
const THREAD_OWNED_BY_ALERA_KEY: &str = "codexThreadOwnedByAlera";

pub(super) fn configuration(tab: &WorkspaceTabRecord) -> Option<Value> {
    tab.payload
        .get(CONFIGURATION_KEY)
        .filter(|value| value.is_object())
        .cloned()
}

pub(super) fn active_cwd(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get(ACTIVE_CWD_KEY)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(super) fn set_active_cwd(tab: &mut WorkspaceTabRecord, cwd: &str) {
    if let Some(object) = tab.payload.as_object_mut() {
        object.insert(ACTIVE_CWD_KEY.to_string(), Value::String(cwd.to_string()));
    }
    tab.updated_at = Utc::now();
}

pub(super) fn thread_owned_by_alera(tab: &WorkspaceTabRecord) -> bool {
    match tab
        .payload
        .get(THREAD_OWNED_BY_ALERA_KEY)
        .and_then(Value::as_bool)
    {
        Some(owned) => owned,
        None => tab
            .payload
            .get("codexThreadId")
            .and_then(Value::as_str)
            .is_some_and(|thread_id| !thread_id.trim().is_empty()),
    }
}

pub(super) fn set_thread_owned_by_alera(tab: &mut WorkspaceTabRecord, owned: bool) {
    payload_object(tab).insert(THREAD_OWNED_BY_ALERA_KEY.to_string(), Value::Bool(owned));
    tab.updated_at = Utc::now();
}

pub(super) fn normalize_configuration(value: &Value) -> Result<Value, &'static str> {
    let source = value
        .as_object()
        .ok_or("Codex configuration must be an object.")?;
    let selected_model = optional_non_empty_string(source, "selectedModel")?;
    let reasoning_effort = required_non_empty_string(source, "reasoningEffort")?;
    let speed_mode = required_choice(source, "speedMode", &["normal", "fast"])?;
    let permission_mode = required_choice(
        source,
        "permissionMode",
        &["untrusted", "on-request", "auto-review", "never"],
    )?;
    let plan_mode = source
        .get("planMode")
        .and_then(Value::as_bool)
        .ok_or("Codex configuration planMode must be a boolean.")?;
    let collaboration_mode = optional_non_empty_string(source, "collaborationMode")?;
    Ok(json!({
        "selectedModel": selected_model,
        "reasoningEffort": reasoning_effort,
        "speedMode": speed_mode,
        "permissionMode": permission_mode,
        "planMode": plan_mode,
        "collaborationMode": collaboration_mode,
    }))
}

pub(super) fn set_configuration(tab: &mut WorkspaceTabRecord, value: Value) {
    payload_object(tab).insert(CONFIGURATION_KEY.to_string(), value);
    tab.updated_at = Utc::now();
}

pub(super) fn clear_thread_identity(tab: &mut WorkspaceTabRecord) {
    let payload = payload_object(tab);
    payload.remove("codexThreadId");
    payload.remove("codexActiveTurnId");
    payload.remove(THREAD_OWNED_BY_ALERA_KEY);
    tab.updated_at = Utc::now();
}

pub(super) fn clear_stale_thread_activity(snapshot: &mut Value) {
    let Some(snapshot) = snapshot.as_object_mut() else {
        return;
    };
    snapshot.remove("activeTurnId");
    snapshot.insert("pendingRequests".to_string(), Value::Array(Vec::new()));
}

pub(super) fn has_materialized_conversation(snapshot: &Value) -> bool {
    if snapshot
        .get("activeTurnId")
        .and_then(Value::as_str)
        .is_some_and(|value| !value.trim().is_empty())
    {
        return true;
    }
    if snapshot
        .get("pendingRequests")
        .and_then(Value::as_array)
        .is_some_and(|requests| !requests.is_empty())
    {
        return true;
    }
    snapshot
        .get("timelineCells")
        .and_then(Value::as_array)
        .is_some_and(|cells| {
            cells.iter().any(|cell| {
                cell.get("turnId")
                    .and_then(Value::as_str)
                    .is_some_and(|value| !value.trim().is_empty())
                    || matches!(
                        cell.get("kind").and_then(Value::as_str),
                        Some(
                            "userMessage"
                                | "assistantMessage"
                                | "reasoning"
                                | "plan"
                                | "command"
                                | "toolCall"
                                | "diff"
                                | "questionAnswer"
                        )
                    )
            })
        })
}

pub(super) fn missing_rollout(error: &str, thread_id: &str) -> bool {
    error.contains("no rollout found for thread id") && error.contains(thread_id)
}

pub(super) fn append_context_reset_notice(snapshot: &mut Value) {
    let now = Utc::now();
    if !snapshot.is_object() {
        *snapshot = json!({});
    }
    let object = snapshot
        .as_object_mut()
        .expect("snapshot normalized to an object above");
    object.remove("activeTurnId");
    object
        .entry("events".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    object.insert("pendingRequests".to_string(), Value::Array(Vec::new()));
    let cells = object
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    let Value::Array(cells) = cells else {
        return;
    };
    let message = "The previous Codex context is unavailable. Earlier messages remain visible, but the next message will start a new model context.";
    cells.push(json!({
        "id": format!("context-reset-{}", now.timestamp_nanos_opt().unwrap_or_default()),
        "kind": "systemNotice",
        "status": "completed",
        "createdAt": now.to_rfc3339(),
        "updatedAt": now.to_rfc3339(),
        "isStreaming": false,
        "isCollapsed": false,
        "title": "Context Reset",
        "markdownText": message,
        "renderedMarkdownText": message,
        "metadata": {"noticeType": "contextReset"},
    }));
}

fn payload_object(tab: &mut WorkspaceTabRecord) -> &mut Map<String, Value> {
    if !tab.payload.is_object() {
        tab.payload = json!({});
    }
    tab.payload
        .as_object_mut()
        .expect("workspace tab payload normalized above")
}

fn required_non_empty_string(
    source: &Map<String, Value>,
    key: &'static str,
) -> Result<String, &'static str> {
    source
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or("Codex configuration contains an invalid string value.")
}

fn optional_non_empty_string(
    source: &Map<String, Value>,
    key: &'static str,
) -> Result<Option<String>, &'static str> {
    match source.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if !value.trim().is_empty() => {
            Ok(Some(value.trim().to_string()))
        }
        _ => Err("Codex configuration contains an invalid optional string value."),
    }
}

fn required_choice(
    source: &Map<String, Value>,
    key: &'static str,
    allowed: &[&str],
) -> Result<String, &'static str> {
    let value = required_non_empty_string(source, key)?;
    allowed
        .contains(&value.as_str())
        .then_some(value)
        .ok_or("Codex configuration contains an unsupported choice.")
}

#[cfg(test)]
mod tests {
    use super::{
        append_context_reset_notice, clear_thread_identity, has_materialized_conversation,
        missing_rollout, normalize_configuration, set_thread_owned_by_alera, thread_owned_by_alera,
    };
    use alera_core::runtime::WorkspaceTabRecord;
    use chrono::Utc;
    use serde_json::json;

    fn tab(payload: serde_json::Value) -> WorkspaceTabRecord {
        let now = Utc::now();
        WorkspaceTabRecord {
            id: "tab-1".into(),
            workspace_id: "workspace-1".into(),
            kind: "codexChat".into(),
            title: "Codex Chat".into(),
            created_at: now,
            updated_at: now,
            payload,
        }
    }

    #[test]
    fn configuration_normalization_preserves_supported_values() {
        let value = normalize_configuration(&json!({
            "selectedModel": "gpt-5.6-luna",
            "reasoningEffort": "low",
            "speedMode": "fast",
            "permissionMode": "on-request",
            "planMode": true,
            "collaborationMode": "plan",
        }))
        .unwrap();
        assert_eq!(value["reasoningEffort"], "low");
        assert_eq!(value["selectedModel"], "gpt-5.6-luna");

        let auto_review = normalize_configuration(&json!({
            "selectedModel": null,
            "reasoningEffort": "medium",
            "speedMode": "normal",
            "permissionMode": "auto-review",
            "planMode": false,
            "collaborationMode": null,
        }))
        .unwrap();
        assert_eq!(auto_review["permissionMode"], "auto-review");
    }

    #[test]
    fn legacy_threads_are_owned_until_an_explicit_marker_says_otherwise() {
        let mut tab = tab(json!({"codexThreadId": "thread-1"}));
        assert!(thread_owned_by_alera(&tab));

        set_thread_owned_by_alera(&mut tab, false);
        assert!(!thread_owned_by_alera(&tab));

        set_thread_owned_by_alera(&mut tab, true);
        assert!(thread_owned_by_alera(&tab));

        clear_thread_identity(&mut tab);
        assert!(!thread_owned_by_alera(&tab));
        assert!(tab.payload.get("codexThreadId").is_none());
        assert!(tab.payload.get("codexThreadOwnedByAlera").is_none());
    }

    #[test]
    fn startup_notices_do_not_materialize_a_conversation() {
        let snapshot = json!({
            "timelineCells": [{"kind": "systemNotice", "title": "Warning"}],
            "pendingRequests": [],
        });
        assert!(!has_materialized_conversation(&snapshot));
        assert!(has_materialized_conversation(&json!({
            "timelineCells": [{"kind": "userMessage"}],
        })));
    }

    #[test]
    fn missing_rollout_must_name_the_expected_thread() {
        assert!(missing_rollout(
            "Bad state: no rollout found for thread id thread-1",
            "thread-1"
        ));
        assert!(!missing_rollout(
            "Bad state: no rollout found for thread id thread-2",
            "thread-1"
        ));
    }

    #[test]
    fn context_reset_discards_requests_from_the_missing_rollout() {
        let mut snapshot = json!({
            "activeTurnId": "turn-old",
            "pendingRequests": [{"id": 9}],
            "timelineCells": [],
        });
        append_context_reset_notice(&mut snapshot);
        assert!(snapshot.get("activeTurnId").is_none());
        assert_eq!(snapshot["pendingRequests"], json!([]));
    }
}
