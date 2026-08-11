use super::{
    apply_manual_thread_title, pending_thread_name, request_cwd, steer_params,
    tab_has_pending_request,
};
use alera_core::runtime::{
    Workspace, WorkspaceKind, WorkspaceStatus, WorkspaceTabRecord, LOCAL_HOST_ID,
};
use chrono::Utc;
use serde_json::json;

fn tab(snapshot: serde_json::Value) -> WorkspaceTabRecord {
    WorkspaceTabRecord {
        id: "tab-1".to_string(),
        workspace_id: "workspace-1".to_string(),
        kind: "codex".to_string(),
        title: "Codex Chat".to_string(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        payload: json!({"codexSnapshot": snapshot}),
    }
}

fn workspace(id: &str, path: &str) -> Workspace {
    Workspace {
        id: id.to_string(),
        instance_id: format!("instance-{id}"),
        host_id: LOCAL_HOST_ID.to_string(),
        project_id: "project".to_string(),
        name: id.to_string(),
        branch: None,
        path: path.to_string(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind: WorkspaceKind::Main,
        status: WorkspaceStatus::Active,
        source_branch: None,
        reuses_existing_branch: false,
        is_pinned: false,
        tag_ids: Vec::new(),
        tag_names: Vec::new(),
        parent_workspace_id: None,
        child_count: 0,
    }
}

#[test]
fn file_inputs_follow_the_resumed_thread_directory() {
    let root = tempfile::tempdir().unwrap();
    let original_path = root.path().join("original");
    let resumed_path = root.path().join("resumed");
    std::fs::create_dir_all(&original_path).unwrap();
    std::fs::create_dir_all(&resumed_path).unwrap();
    let original = workspace("original", &original_path.to_string_lossy());
    let resumed = workspace("resumed", &resumed_path.to_string_lossy());
    let mut active_tab = tab(json!({}));
    active_tab.payload["codexCwd"] = json!(resumed_path);

    let cwd = request_cwd(&active_tab, &original, &[original.clone(), resumed]).unwrap();

    assert_eq!(
        cwd,
        std::fs::canonicalize(resumed_path)
            .unwrap()
            .to_string_lossy()
    );
}

#[test]
fn pending_rename_is_forwarded_when_the_first_thread_is_created() {
    let pending = tab(json!({"title": "  Planned name  "}));
    let mut opened = tab(json!({"title": "Opened"}));
    opened.payload["codexThreadId"] = json!("thread-1");

    assert_eq!(
        pending_thread_name(&pending).as_deref(),
        Some("Planned name")
    );
    assert_eq!(pending_thread_name(&opened), None);
}

#[test]
fn scoped_response_requires_the_request_on_the_originating_tab() {
    let matching = tab(json!({"pendingRequests": [{"id": 7}]}));
    let stale = tab(json!({"pendingRequests": [{"id": 8}]}));

    assert!(tab_has_pending_request(&matching, &json!(7)));
    assert!(!tab_has_pending_request(&stale, &json!(7)));
}

#[test]
fn manual_title_marker_prevents_generated_titles_from_replacing_a_rename() {
    let mut renamed = tab(json!({"title": "Old title"}));
    apply_manual_thread_title(&mut renamed, "Manual title");

    assert_eq!(renamed.title, "Manual title");
    assert_eq!(renamed.payload["manualTitle"], true);
    assert_eq!(renamed.payload["codexSnapshot"]["title"], "Manual title");
}

#[test]
fn steer_forwards_normalized_inputs_to_the_app_server() {
    let params = steer_params(
        "thread-1",
        "turn-1",
        "message-1",
        json!([
            {"type": "text", "text": "docs/notes.md", "text_elements": [{"byteRange": {"start": 0, "end": 13}}]},
            {"type": "text", "text": "Review it"}
        ]),
    );

    assert_eq!(params["input"][0]["type"], "text");
    assert_eq!(params["input"][0]["text"], "docs/notes.md");
    assert_eq!(params["input"][1]["text"], "Review it");
}
