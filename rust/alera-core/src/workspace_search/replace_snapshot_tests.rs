use super::*;
use std::fs;

fn options(root: &std::path::Path, query: &str) -> WorkspaceReplaceOptions {
    WorkspaceReplaceOptions {
        search: WorkspaceSearchOptions {
            workspace_path: root.to_string_lossy().into_owned(),
            query: query.into(),
            case_sensitive: true,
            whole_word: false,
            use_regex: false,
            include_pattern: None,
            exclude_pattern: None,
            include_ignored: false,
            max_results: None,
        },
        replacement: "new".into(),
        preserve_case: false,
    }
}

fn request(options: WorkspaceReplaceOptions) -> WorkspaceReplaceRequest {
    let preview = preview_workspace_replace(options.clone()).unwrap();
    WorkspaceReplaceRequest {
        options,
        match_ids: Vec::new(),
        expected_files: preview
            .result
            .files
            .into_iter()
            .map(|file| WorkspaceReplaceFileExpectation {
                relative_path: file.relative_path,
                content_token: file.content_token,
            })
            .collect(),
    }
}

#[test]
fn replacements_reject_changes_after_search_and_before_write() {
    for change_before_write in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.txt");
        fs::write(&path, "foo\n").unwrap();
        let request = request(options(dir.path(), "foo"));
        let result = replace::replace_with_file_checkpoint(request, |path, before_write| {
            if before_write == change_before_write {
                fs::write(path, "bar\n").unwrap();
            }
        })
        .unwrap();
        assert_eq!(result.files_changed, 0);
        assert_eq!(result.matches_replaced, 0);
        assert_eq!(result.conflicts[0].reason, "File changed on disk");
        assert_eq!(fs::read_to_string(path).unwrap(), "bar\n");
    }
}

#[test]
fn replacement_search_does_not_retain_large_lines_per_match() {
    let dir = tempfile::tempdir().unwrap();
    let content = format!("{}{}", "foo ".repeat(100), "x".repeat(4 * 1024 * 1024));
    fs::write(dir.path().join("minified.txt"), content).unwrap();
    let compiled = compile::compile_search(&options(dir.path(), "foo").search).unwrap();
    let found = engine::run_search(&compiled, true, None).unwrap();
    assert_eq!(found.total_matches, 100);
    assert!(found.files[0]
        .matches
        .iter()
        .all(|m| m.line_content.is_empty()));
}

#[test]
fn regex_replacements_preserve_boundary_context_and_capture_expansion() {
    for (pattern, source, replacement, expected) in [
        (r"\B(foo)", "xfoo\n", "${1}z", "xfooz\n"),
        (r"(foo)\B", "foox\n", "${1}z", "foozx\n"),
        (r"\b(foo)\b", "x foo y\n", "${1}z", "x fooz y\n"),
    ] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("a.txt");
        fs::write(&path, source).unwrap();
        let mut options = options(dir.path(), pattern);
        options.search.use_regex = true;
        options.replacement = replacement.into();
        let preview = preview_workspace_replace(options.clone()).unwrap();
        assert_eq!(
            preview.result.files[0].matches[0]
                .replacement_preview
                .as_deref(),
            Some("fooz")
        );
        let result = replace_workspace_matches(request(options)).unwrap();
        assert_eq!(result.matches_replaced, 1);
        assert_eq!(fs::read_to_string(path).unwrap(), expected);
    }
}
