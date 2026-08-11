use super::*;

pub(in crate::terminal_host::server) fn session_response(
    tab: &WorkspaceTabRecord,
    already_bound: bool,
    operation: Option<&str>,
    history_next_cursor: Option<String>,
) -> Value {
    json!({
        "tab": tab,
        "tabId": tab.id,
        "threadId": tab_thread_id(tab),
        "cwd": active_cwd(tab),
        "snapshot": snapshot(tab),
        "configuration": configuration(tab),
        "historyNextCursor": history_next_cursor,
        "alreadyBound": already_bound,
        "boundTabId": if already_bound { Value::String(tab.id.clone()) } else { Value::Null },
        "boundWorkspaceId": if already_bound { Value::String(tab.workspace_id.clone()) } else { Value::Null },
        "operation": operation,
    })
}

pub(in crate::terminal_host::server) fn append_thread_boundary(
    snapshot: &mut serde_json::Map<String, Value>,
    thread_id: &str,
) {
    let cells = snapshot
        .entry("timelineCells".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    let Value::Array(cells) = cells else {
        return;
    };
    cells.push(json!({
        "id": format!("thread-boundary-{thread_id}"),
        "kind": "systemNotice",
        "title": "New Codex Chat",
        "markdownText": "Started a new Codex thread in this tab.",
        "status": "completed",
        "metadata": {
            "noticeType": "threadBoundary",
            "threadId": thread_id,
        },
    }));
}
