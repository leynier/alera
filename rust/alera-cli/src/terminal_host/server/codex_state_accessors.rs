use super::*;

pub(in crate::terminal_host::server) fn render_markdown(text: &str) -> String {
    codex_markdown::render_markdown(text)
}

pub(in crate::terminal_host::server) fn persist_snapshot(
    tab: &mut WorkspaceTabRecord,
    next: Value,
) {
    codex_state_snapshot::persist_snapshot(tab, next);
}

pub(in crate::terminal_host::server) fn trim_cells(cells: &mut Vec<Value>) {
    codex_state_snapshot::trim_cells(cells);
}

pub(in crate::terminal_host::server) fn clear_review_transition(snapshot: &mut Value) {
    codex_review_transition::clear_live_transition(snapshot);
}

pub(in crate::terminal_host::server) fn snapshot(tab: &WorkspaceTabRecord) -> Value {
    tab.payload
        .get("codexSnapshot")
        .filter(|value| value.is_object())
        .cloned()
        .unwrap_or_else(|| {
            json!({
                "schemaVersion": CODEX_SNAPSHOT_VERSION,
                "events": [],
                "timelineCells": [],
                "pendingRequests": [],
            })
        })
}

pub(in crate::terminal_host::server) fn is_turn_completion(message: &Value) -> bool {
    matches!(
        message.get("method").and_then(Value::as_str),
        Some(
            "turn/completed"
                | "turn/failed"
                | "turn/aborted"
                | "turn/interrupted"
                | "codex/event/task_complete"
                | "codex/event/task_failed"
                | "codex/event/turn_aborted"
                | "codex/event/turn_interrupted"
        )
    )
}
