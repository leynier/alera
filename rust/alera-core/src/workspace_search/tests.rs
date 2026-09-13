use std::fs;

use super::globs::split_search_glob_patterns;
use super::paths::should_walk_entry;
use super::preview::preserve_case;
use super::*;
use tempfile::tempdir;

#[test]
fn searches_literal_with_include_and_exclude() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("src")).unwrap();
    fs::create_dir_all(dir.path().join("dist")).unwrap();
    fs::write(dir.path().join("src/main.dart"), "hello\nhello again\n").unwrap();
    fs::write(dir.path().join("dist/main.dart"), "hello\n").unwrap();

    let result = search_workspace(WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: Some("*.dart".to_string()),
        exclude_pattern: Some("dist/**".to_string()),
        include_ignored: false,
        max_results: None,
    })
    .unwrap();

    assert_eq!(result.total_matches, 2);
    assert_eq!(result.files.len(), 1);
    assert_eq!(result.files[0].relative_path, "src/main.dart");
}

#[test]
fn previews_and_replaces_selected_match() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "hello hello\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "bye".to_string(),
        preserve_case: false,
    })
    .unwrap();
    let file = &preview.result.files[0];
    let request = WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search,
            replacement: "bye".to_string(),
            preserve_case: false,
        },
        match_ids: vec![file.matches[0].id.clone()],
        expected_files: vec![WorkspaceReplaceFileExpectation {
            relative_path: file.relative_path.clone(),
            content_token: file.content_token.clone(),
        }],
    };
    let replaced = replace_workspace_matches(request).unwrap();

    assert_eq!(replaced.files_changed, 1);
    assert_eq!(replaced.matches_replaced, 1);
    assert_eq!(
        fs::read_to_string(dir.path().join("note.txt")).unwrap(),
        "bye hello\n"
    );
}

#[cfg(unix)]
#[test]
fn search_ignores_symlinked_files() {
    use std::os::unix::fs::symlink;

    let workspace = tempdir().unwrap();
    let external = tempdir().unwrap();
    fs::write(external.path().join("secret.txt"), "needle\n").unwrap();
    symlink(
        external.path().join("secret.txt"),
        workspace.path().join("link.txt"),
    )
    .unwrap();

    let result = search_workspace(WorkspaceSearchOptions {
        workspace_path: workspace.path().to_string_lossy().to_string(),
        query: "needle".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    })
    .unwrap();

    assert_eq!(result.total_matches, 0);
    assert!(result.files.is_empty());
}

#[cfg(unix)]
#[test]
fn replace_all_does_not_write_symlinked_files() {
    use std::os::unix::fs::symlink;

    let workspace = tempdir().unwrap();
    let external = tempdir().unwrap();
    let external_file = external.path().join("secret.txt");
    fs::write(&external_file, "hello\n").unwrap();
    symlink(&external_file, workspace.path().join("link.txt")).unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: workspace.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };

    let replaced = replace_workspace_matches(WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search,
            replacement: "bye".to_string(),
            preserve_case: false,
        },
        match_ids: Vec::new(),
        expected_files: Vec::new(),
    })
    .unwrap();

    assert_eq!(replaced.files_changed, 0);
    assert_eq!(replaced.matches_replaced, 0);
    assert_eq!(fs::read_to_string(external_file).unwrap(), "hello\n");
}

#[test]
fn replace_all_conflicts_on_files_missing_from_preview() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("a.txt"), "hello\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: Some("*.txt".to_string()),
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "bye".to_string(),
        preserve_case: false,
    })
    .unwrap();
    fs::write(dir.path().join("b.txt"), "hello\n").unwrap();

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

    assert_eq!(replaced.files_changed, 1);
    assert_eq!(replaced.matches_replaced, 1);
    assert_eq!(
        fs::read_to_string(dir.path().join("a.txt")).unwrap(),
        "bye\n"
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("b.txt")).unwrap(),
        "hello\n"
    );
    assert_eq!(replaced.conflicts.len(), 1);
    assert_eq!(replaced.conflicts[0].relative_path, "b.txt");
    assert_eq!(
        replaced.conflicts[0].reason,
        "File was not part of the preview"
    );
}

#[test]
fn replace_all_rejects_truncated_results_without_writing() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "hello hello\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: Some(1),
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "bye".to_string(),
        preserve_case: false,
    })
    .unwrap();
    assert!(preview.result.truncated);

    let error = replace_workspace_matches(WorkspaceReplaceRequest {
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
    .unwrap_err();

    assert_eq!(error.kind, WorkspaceSearchErrorKind::InvalidPattern);
    assert_eq!(
        error.context,
        "Replace all is unavailable while results are truncated."
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("note.txt")).unwrap(),
        "hello hello\n"
    );
}

#[test]
fn selected_replace_reports_stale_missing_match_as_conflict() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "hello\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "bye".to_string(),
        preserve_case: false,
    })
    .unwrap();
    let file = &preview.result.files[0];
    let match_id = file.matches[0].id.clone();
    fs::write(dir.path().join("note.txt"), "goodbye\n").unwrap();

    let replaced = replace_workspace_matches(WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search,
            replacement: "bye".to_string(),
            preserve_case: false,
        },
        match_ids: vec![match_id],
        expected_files: vec![WorkspaceReplaceFileExpectation {
            relative_path: file.relative_path.clone(),
            content_token: file.content_token.clone(),
        }],
    })
    .unwrap();

    assert_eq!(replaced.files_changed, 0);
    assert_eq!(replaced.matches_replaced, 0);
    assert_eq!(replaced.conflicts.len(), 1);
    assert_eq!(replaced.conflicts[0].relative_path, "note.txt");
    assert_eq!(
        replaced.conflicts[0].reason,
        "Selected match is no longer available"
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("note.txt")).unwrap(),
        "goodbye\n"
    );
}

#[test]
fn protected_directories_are_pruned_before_walk() {
    let dir = tempdir().unwrap();
    let nested_workspace = dir.path().join(".git/workspace");

    assert!(should_walk_entry(dir.path(), dir.path()));
    assert!(!should_walk_entry(dir.path(), &dir.path().join(".git")));
    assert!(!should_walk_entry(
        dir.path(),
        &dir.path().join(".git/objects")
    ));
    assert!(should_walk_entry(&nested_workspace, &nested_workspace));
    assert!(should_walk_entry(
        &nested_workspace,
        &nested_workspace.join("note.txt")
    ));
    assert!(!should_walk_entry(
        &nested_workspace,
        &nested_workspace.join("src/.git/config")
    ));
}

#[test]
fn preserve_case_leaves_caseless_matches_unchanged() {
    assert_eq!(preserve_case("123", "abc"), "abc");
    assert_eq!(preserve_case("ABC", "abc"), "ABC");
    assert_eq!(preserve_case("Needle", "mixedCASE"), "Mixedcase");
}

#[test]
fn fixed_string_replacement_treats_dollar_as_literal() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "foo foo\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "foo".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: search.clone(),
        replacement: "$HOME".to_string(),
        preserve_case: false,
    })
    .unwrap();
    let file = &preview.result.files[0];

    replace_workspace_matches(WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search,
            replacement: "$1".to_string(),
            preserve_case: false,
        },
        match_ids: vec![file.matches[0].id.clone()],
        expected_files: vec![WorkspaceReplaceFileExpectation {
            relative_path: file.relative_path.clone(),
            content_token: file.content_token.clone(),
        }],
    })
    .unwrap();

    assert_eq!(
        preview.result.files[0].matches[0].replacement_preview,
        Some("$HOME".to_string())
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("note.txt")).unwrap(),
        "$1 foo\n"
    );
}

#[test]
fn regex_replacement_still_expands_captures() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "foo\n").unwrap();
    let search = WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "(foo)".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: true,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    };
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search,
        replacement: "${1}bar".to_string(),
        preserve_case: false,
    })
    .unwrap();

    assert_eq!(
        preview.result.files[0].matches[0].replacement_preview,
        Some("foobar".to_string())
    );
}

#[test]
fn whitespace_only_queries_are_searchable() {
    let dir = tempdir().unwrap();
    fs::write(dir.path().join("note.txt"), "a b\n\tc\n").unwrap();

    let space = search_workspace(WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: " ".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    })
    .unwrap();
    let tab = search_workspace(WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "\t".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    })
    .unwrap();

    assert_eq!(space.total_matches, 1);
    assert_eq!(tab.total_matches, 1);
}

#[test]
fn windows_style_globs_preserve_backslash_separators() {
    let dir = tempdir().unwrap();
    fs::create_dir_all(dir.path().join("src")).unwrap();
    fs::write(dir.path().join("src/main.dart"), "hello\n").unwrap();

    let result = search_workspace(WorkspaceSearchOptions {
        workspace_path: dir.path().to_string_lossy().to_string(),
        query: "hello".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: Some(r"src\*.dart".to_string()),
        exclude_pattern: None,
        include_ignored: false,
        max_results: None,
    })
    .unwrap();

    assert_eq!(result.total_matches, 1);
    assert_eq!(result.files[0].relative_path, "src/main.dart");
}

#[test]
fn glob_splitter_only_escapes_commas() {
    assert_eq!(
        split_search_glob_patterns(r"src\*.dart,src/foo\,bar.dart"),
        vec!["src\\*.dart".to_string(), "src/foo,bar.dart".to_string()]
    );
}
