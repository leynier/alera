use super::*;

const MAX_WORKSPACE_THREAD_SCAN_PAGES: usize = 4;

pub(in crate::terminal_host::server::codex_requests) fn eligible_thread(thread: &Value) -> bool {
    thread.get("archived").and_then(Value::as_bool) != Some(true) && thread_id(thread).is_some()
}

pub(in crate::terminal_host::server::codex_requests) fn thread_belongs_to_workspaces(
    thread: &Value,
    workspaces: &[Workspace],
) -> bool {
    string_value(thread, "cwd").is_some_and(|cwd| {
        workspaces
            .iter()
            .any(|workspace| path_matches(&cwd, &workspace.path))
    })
}

pub(in crate::terminal_host::server::codex_requests) fn source_kind(
    thread: &Value,
) -> Option<String> {
    let source = thread.get("source")?;
    source
        .as_str()
        .or_else(|| source.get("kind").and_then(Value::as_str))
        .or_else(|| source.get("type").and_then(Value::as_str))
        .map(str::to_string)
}

pub(in crate::terminal_host::server::codex_requests) fn thread_id(
    thread: &Value,
) -> Option<String> {
    thread
        .get("id")
        .or_else(|| thread.get("threadId"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(in crate::terminal_host::server::codex_requests) fn thread_title_value(
    thread: &Value,
) -> Option<String> {
    ["name", "title", "preview"]
        .into_iter()
        .filter_map(|key| thread.get(key).and_then(Value::as_str))
        .map(str::trim)
        .find(|value| !value.is_empty())
        .map(str::to_string)
}

pub(in crate::terminal_host::server::codex_requests) fn thread_title(thread: &Value) -> String {
    thread_title_value(thread).unwrap_or_else(|| "Untitled Codex Thread".to_string())
}

pub(in crate::terminal_host::server::codex_requests) fn resumed_snapshot_with_thread_title(
    mut snapshot: Value,
    response: &Value,
) -> Value {
    let has_title = snapshot
        .get("title")
        .and_then(Value::as_str)
        .is_some_and(|value| !value.trim().is_empty());
    if !has_title {
        if let Some(title) = response
            .get("thread")
            .and_then(thread_title_value)
            .or_else(|| thread_title_value(response))
        {
            snapshot["title"] = Value::String(title);
        }
    }
    snapshot
}

pub(in crate::terminal_host::server::codex_requests) fn most_specific_workspace<'a>(
    cwd: &str,
    workspaces: &'a [Workspace],
) -> Option<&'a Workspace> {
    workspaces
        .iter()
        .filter(|workspace| path_matches(cwd, &workspace.path))
        .max_by_key(|workspace| normalized_match_path(&workspace.path).len())
}

pub(in crate::terminal_host::server::codex_requests) fn string_value(
    value: &Value,
    key: &str,
) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(in crate::terminal_host::server::codex_requests) fn requested_cwd(
    payload: &Value,
) -> Option<String> {
    payload
        .get("cwd")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

pub(in crate::terminal_host::server::codex_requests) fn response_cursor(
    response: &Value,
) -> Option<String> {
    string_value(response, "nextCursor")
}

pub(in crate::terminal_host::server::codex_requests) fn should_continue_thread_scan(
    workspace_scoped: bool,
    collected: usize,
    limit: u64,
    has_next_cursor: bool,
    cursor_is_new: bool,
    scanned_pages: usize,
) -> bool {
    workspace_scoped
        && collected < limit as usize
        && has_next_cursor
        && cursor_is_new
        && scanned_pages < MAX_WORKSPACE_THREAD_SCAN_PAGES
}

pub(in crate::terminal_host::server::codex_requests) fn existing_thread_binding_response(
    bindings: &ThreadBindings,
    thread_id: &str,
) -> Option<Value> {
    let (bound_tab_id, bound_workspace_id) = bindings.get(thread_id)?;
    Some(json!({
        "alreadyBound": true,
        "boundTabId": bound_tab_id,
        "boundWorkspaceId": bound_workspace_id,
        "threadId": thread_id,
    }))
}

pub(in crate::terminal_host::server::codex_requests) fn allowed_cwd(
    candidate: &str,
    workspaces: &[Workspace],
) -> Option<String> {
    let candidate = fs::canonicalize(candidate).ok()?;
    workspaces
        .iter()
        .filter_map(|workspace| fs::canonicalize(&workspace.path).ok())
        .find(|root| candidate.starts_with(root))
        .map(|_| candidate.to_string_lossy().into_owned())
}

pub(in crate::terminal_host::server) fn path_matches(candidate: &str, root: &str) -> bool {
    let candidate = normalized_match_path(candidate);
    let root = normalized_match_path(root);
    candidate == root
        || candidate
            .strip_prefix(&root)
            .is_some_and(|suffix| suffix.starts_with('/'))
}

pub(in crate::terminal_host::server::codex_requests) fn normalized_match_path(
    value: &str,
) -> String {
    let path = Path::new(value);
    let resolved = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let normalized = resolved
        .to_string_lossy()
        .replace('\\', "/")
        .trim_end_matches('/')
        .to_string();
    #[cfg(windows)]
    {
        normalized.to_lowercase()
    }
    #[cfg(not(windows))]
    {
        normalized
    }
}

pub(in crate::terminal_host::server::codex_requests) fn cwd_options(
    workspaces: &[Workspace],
) -> Value {
    Value::Array(
        workspaces
            .iter()
            .map(|workspace| {
                json!({
                    "workspaceId": workspace.id,
                    "name": workspace.name,
                    "path": workspace.path,
                })
            })
            .collect(),
    )
}

pub(in crate::terminal_host::server::codex_requests) fn request_limit(payload: &Value) -> u64 {
    payload
        .get("limit")
        .or_else(|| payload.get("historyLimit"))
        .and_then(Value::as_u64)
        .unwrap_or(20)
        .clamp(1, 100)
}

pub(in crate::terminal_host::server::codex_requests) fn thread_resume_params(
    thread_id: &str,
    cwd: &str,
    history_limit: usize,
) -> Value {
    json!({
        "threadId": thread_id,
        "cwd": cwd,
        "excludeTurns": true,
        "initialTurnsPage": {
            "limit": history_limit.max(1).saturating_add(1),
            "sortDirection": "desc",
            "itemsView": "full",
        },
    })
}

pub(in crate::terminal_host::server::codex_requests) fn copy_optional(
    payload: &Value,
    target: &mut Value,
    key: &str,
) {
    if let Some(value) = payload.get(key) {
        if let Some(object) = target.as_object_mut() {
            object.insert(key.to_string(), value.clone());
        }
    }
}

pub(in crate::terminal_host::server::codex_requests) fn empty_snapshot() -> Value {
    json!({
        "schemaVersion": 2,
        "events": [],
        "timelineCells": [],
        "pendingRequests": [],
    })
}

pub(in crate::terminal_host::server::codex_requests) fn ensure_thread_switch_allowed(
    tab: &WorkspaceTabRecord,
) -> HostResult<()> {
    if active_turn_id(&snapshot(tab)).is_some() {
        return Err(HostError::state(
            "Stop the active Codex turn before switching threads.",
        ));
    }
    Ok(())
}

pub(in crate::terminal_host::server::codex_requests) fn reset_snapshot_for_new_thread(
    snapshot: &mut Value,
    thread_id: &str,
    append_boundary: bool,
) {
    clear_review_transition(snapshot);
    let Some(object) = snapshot.as_object_mut() else {
        return;
    };
    object.remove("activeTurnId");
    object.remove("contextUsed");
    object.remove("contextLimit");
    object.remove("title");
    object.insert("events".to_string(), Value::Array(Vec::new()));
    object.insert("pendingRequests".to_string(), Value::Array(Vec::new()));
    if append_boundary {
        append_thread_boundary(object, thread_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::server::codex_state::MAX_SNAPSHOT_CELLS;
    use chrono::Utc;

    #[test]
    fn thread_discovery_accepts_server_selected_legacy_and_future_sources() {
        for source in [json!("unknown"), json!("futureInteractive"), Value::Null] {
            assert!(eligible_thread(
                &json!({"id": "thread-1", "source": source})
            ));
        }
        assert!(!eligible_thread(&json!({
            "id": "thread-1",
            "source": "cli",
            "archived": true,
        })));
        assert!(!eligible_thread(&json!({"source": "cli"})));
    }

    #[test]
    fn descendant_thread_paths_belong_to_the_workspace() {
        assert!(path_matches("/repo/packages/app", "/repo"));
        assert!(path_matches("/repo", "/repo"));
        assert!(!path_matches("/repository", "/repo"));
    }

    #[cfg(not(windows))]
    #[test]
    fn workspace_path_matching_preserves_case() {
        assert!(!path_matches("/repo/Workspace/thread", "/repo/workspace"));
    }

    #[cfg(unix)]
    #[test]
    fn canonical_workspace_paths_match_symlinked_thread_directories() {
        let directory = tempfile::tempdir().unwrap();
        let workspace = directory.path().join("workspace");
        let linked = directory.path().join("linked");
        let child = workspace.join("packages/app");
        std::fs::create_dir_all(&child).unwrap();
        std::os::unix::fs::symlink(&workspace, &linked).unwrap();

        assert!(path_matches(
            &linked.join("packages/app").to_string_lossy(),
            &workspace.to_string_lossy(),
        ));
    }

    #[test]
    fn new_thread_snapshot_clears_conversation_accounting() {
        let mut value = json!({
            "activeTurnId": "turn-old",
            "aleraReviewTransition": {
                "entryTurnId": "review-entry",
                "workerTurnId": "review-worker",
            },
            "contextUsed": 900,
            "contextLimit": 1000,
            "title": "Old thread",
            "events": [{"method": "turn/completed", "params": {"turn": {"id": "turn-old"}}}],
            "pendingRequests": [{"id": 1}],
            "timelineCells": [],
        });

        reset_snapshot_for_new_thread(&mut value, "thread-new", true);

        assert!(value.get("activeTurnId").is_none());
        assert!(value.get("aleraReviewTransition").is_none());
        assert!(value.get("contextUsed").is_none());
        assert!(value.get("contextLimit").is_none());
        assert!(value.get("title").is_none());
        assert_eq!(value["events"], json!([]));
        assert_eq!(value["pendingRequests"], json!([]));
        assert_eq!(value["timelineCells"][0]["kind"], "systemNotice");
    }

    #[test]
    fn thread_switch_bounds_the_persisted_snapshot() {
        let cells = (0..(MAX_SNAPSHOT_CELLS + 20))
            .map(|index| json!({"id": format!("cell-{index}")}))
            .collect::<Vec<_>>();
        let mut tab = WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "codex".to_string(),
            title: "Codex Chat".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({}),
        };
        let mut next = json!({"events": [], "timelineCells": cells, "pendingRequests": []});
        reset_snapshot_for_new_thread(&mut next, "thread-new", true);

        set_thread_and_snapshot(&mut tab, "thread-new", next);

        let persisted = snapshot(&tab);
        assert_eq!(
            persisted["timelineCells"].as_array().unwrap().len(),
            MAX_SNAPSHOT_CELLS
        );
        assert_eq!(
            persisted["timelineCells"]
                .as_array()
                .unwrap()
                .last()
                .unwrap()["metadata"]["noticeType"],
            "threadBoundary"
        );
    }

    #[test]
    fn active_turns_cannot_switch_threads() {
        let mut tab = WorkspaceTabRecord {
            id: "tab-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            kind: "codex".to_string(),
            title: "Codex Chat".to_string(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
            payload: json!({
                "codexSnapshot": {"activeTurnId": "turn-live"},
            }),
        };
        assert!(ensure_thread_switch_allowed(&tab).is_err());
        tab.payload["codexSnapshot"]
            .as_object_mut()
            .unwrap()
            .remove("activeTurnId");
        assert!(ensure_thread_switch_allowed(&tab).is_ok());
    }

    #[test]
    fn resumed_history_inherits_the_thread_name() {
        let snapshot = resumed_snapshot_with_thread_title(
            empty_snapshot(),
            &json!({"thread": {"name": "Recovered conversation"}}),
        );

        assert_eq!(snapshot["title"], "Recovered conversation");
    }

    #[test]
    fn thread_resume_requests_a_bounded_full_history_page() {
        let params = thread_resume_params("thread-1", "/workspace", 20);

        assert_eq!(params["threadId"], "thread-1");
        assert_eq!(params["cwd"], "/workspace");
        assert_eq!(params["excludeTurns"], true);
        assert_eq!(params["initialTurnsPage"]["limit"], 21);
        assert_eq!(params["initialTurnsPage"]["sortDirection"], "desc");
        assert_eq!(params["initialTurnsPage"]["itemsView"], "full");
        assert_eq!(params.as_object().unwrap().len(), 4);
    }

    #[test]
    fn resuming_a_thread_already_bound_to_the_current_tab_is_a_no_op() {
        let bindings = HashMap::from([(
            "thread-1".to_string(),
            ("tab-1".to_string(), "workspace-1".to_string()),
        )]);

        let response = existing_thread_binding_response(&bindings, "thread-1").unwrap();

        assert_eq!(response["alreadyBound"], true);
        assert_eq!(response["boundTabId"], "tab-1");
        assert_eq!(response["boundWorkspaceId"], "workspace-1");
    }

    #[test]
    fn nested_thread_paths_use_the_most_specific_workspace() {
        let parent = workspace("parent", "/repo");
        let nested = workspace("nested", "/repo/packages/app");
        let workspaces = [parent, nested.clone()];

        let selected = most_specific_workspace("/repo/packages/app/src", &workspaces).unwrap();

        assert_eq!(selected.id, nested.id);
    }

    #[test]
    fn workspace_thread_scans_stop_at_the_page_budget() {
        assert!(should_continue_thread_scan(true, 0, 20, true, true, 3));
        assert!(!should_continue_thread_scan(true, 0, 20, true, true, 4));
        assert!(!should_continue_thread_scan(false, 0, 20, true, true, 1));
    }

    fn workspace(id: &str, path: &str) -> Workspace {
        let now = Utc::now();
        Workspace {
            id: id.to_string(),
            instance_id: format!("instance-{id}"),
            host_id: "local".to_string(),
            project_id: "project".to_string(),
            name: id.to_string(),
            branch: None,
            path: path.to_string(),
            created_at: now,
            updated_at: now,
            kind: alera_core::runtime::WorkspaceKind::Main,
            status: alera_core::runtime::WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            tag_ids: Vec::new(),
            tag_names: Vec::new(),
            parent_workspace_id: None,
            child_count: 0,
        }
    }
}
