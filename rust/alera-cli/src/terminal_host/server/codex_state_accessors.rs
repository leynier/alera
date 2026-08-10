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
