use std::fs;

use super::*;
use tempfile::tempdir;

#[test]
fn cancelled_search_stops_before_walking() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "needle\n").unwrap();
    let request_id = "cancel-before-start".to_string();
    cancel_workspace_search(request_id.clone());

    let error = search_workspace_cancelable(
        WorkspaceSearchOptions {
            workspace_path: dir.path().to_string_lossy().to_string(),
            query: "needle".to_string(),
            case_sensitive: true,
            whole_word: false,
            use_regex: false,
            include_pattern: None,
            exclude_pattern: None,
            include_ignored: false,
            max_results: None,
        },
        request_id,
    )
    .unwrap_err();

    assert_eq!(error.kind, WorkspaceSearchErrorKind::Cancelled);
}
