use std::fs;

use super::*;
use tempfile::tempdir;

#[test]
fn replace_preview_uses_unclamped_match_slice() {
    let dir = tempdir().unwrap();
    let matched = "a".repeat(600);
    fs::write(dir.path().join("note.txt"), format!("🙂{matched}\n")).unwrap();

    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: WorkspaceSearchOptions {
            workspace_path: dir.path().to_string_lossy().to_string(),
            query: "(a+)".to_string(),
            case_sensitive: true,
            whole_word: false,
            use_regex: true,
            include_pattern: None,
            exclude_pattern: None,
            include_ignored: false,
            max_results: None,
        },
        replacement: "${1}z".to_string(),
        preserve_case: false,
    })
    .unwrap();

    let m = &preview.result.files[0].matches[0];
    assert!(m.line_content.starts_with('…'));
    assert_eq!(m.replacement_preview, Some(format!("{matched}z")));
}
