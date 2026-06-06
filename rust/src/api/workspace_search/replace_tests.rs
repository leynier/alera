use std::fs;

use super::*;
use tempfile::tempdir;

#[cfg(unix)]
#[test]
fn replace_reports_file_write_failures_as_conflicts() {
    use std::os::unix::fs::PermissionsExt;

    let dir = tempdir().unwrap();
    fs::write(dir.path().join("a.txt"), "hello\n").unwrap();
    let locked_path = dir.path().join("b.txt");
    fs::write(&locked_path, "hello\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: Some("*.txt".to_string()),
        exclude_pattern: None,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "bye".to_string(),
        preserve_case: false,
    })
    .unwrap();
    let mut permissions = fs::metadata(&locked_path).unwrap().permissions();
    permissions.set_mode(0o444);
    fs::set_permissions(&locked_path, permissions).unwrap();

    let replaced = replace_workspace_matches(WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search,
            replacement: "bye".to_string(),
            preserve_case: false,
        },
        match_ids: Vec::new(),
        expected_files: preview
            .result
            .files
            .iter()
            .map(|file| WorkspaceReplaceFileExpectation {
                relative_path: file.relative_path.clone(),
                content_token: file.content_token.clone(),
            })
            .collect(),
    })
    .unwrap();

    let mut permissions = fs::metadata(&locked_path).unwrap().permissions();
    permissions.set_mode(0o644);
    fs::set_permissions(&locked_path, permissions).unwrap();
    assert_eq!(replaced.files_changed, 1);
    assert_eq!(replaced.matches_replaced, 1);
    assert_eq!(
        fs::read_to_string(dir.path().join("a.txt")).unwrap(),
        "bye\n"
    );
    assert_eq!(fs::read_to_string(locked_path).unwrap(), "hello\n");
    assert_eq!(replaced.conflicts.len(), 1);
    assert_eq!(replaced.conflicts[0].relative_path, "b.txt");
    assert!(replaced.conflicts[0]
        .reason
        .starts_with("Could not write file:"));
}
