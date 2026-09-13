use std::fs;

use serde_json::json;

use super::*;

fn options(root: &std::path::Path, query: &str) -> WorkspaceSearchOptions {
    search_options(
        root.to_string_lossy().into_owned(),
        query.to_string(),
        &json!({}),
    )
}

#[test]
fn search_json_carries_content_tokens_and_replacement_previews() {
    let workspace = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("notes.md"), "Alpha alpha\n").unwrap();
    let preview = preview_workspace_replace(WorkspaceReplaceOptions {
        search: options(workspace.path(), "alpha"),
        replacement: "beta".into(),
        preserve_case: true,
    })
    .unwrap();

    let value = result_json(preview.result);

    let file = &value["files"][0];
    assert_eq!(file["relativePath"], "notes.md");
    assert!(file["contentToken"]
        .as_str()
        .is_some_and(|token| !token.is_empty()));
    assert_eq!(file["matches"].as_array().unwrap().len(), 2);
    assert_eq!(file["matches"][0]["id"], "notes.md:1:1:0");
    assert_eq!(file["matches"][0]["replacementPreview"], "Beta");
    assert_eq!(file["matches"][1]["replacementPreview"], "beta");
    assert_eq!(value["totalMatches"], 2);
}

#[test]
fn replace_request_parses_selected_ids_and_expected_tokens() {
    let workspace = tempfile::tempdir().unwrap();
    let path = workspace.path().join("notes.md");
    fs::write(&path, "one one\n").unwrap();
    let searched = result_json(search_workspace(options(workspace.path(), "one")).unwrap());
    let payload = json!({
        "matchIds": [searched["files"][0]["matches"][1]["id"]],
        "expectedFiles": [{
            "relativePath": "notes.md",
            "contentToken": searched["files"][0]["contentToken"],
        }],
    });

    let result = replace_workspace_matches(WorkspaceReplaceRequest {
        options: WorkspaceReplaceOptions {
            search: options(workspace.path(), "one"),
            replacement: "two".into(),
            preserve_case: false,
        },
        match_ids: string_list(&payload, "matchIds"),
        expected_files: expected_files(&payload),
    })
    .unwrap();

    assert_eq!(replace_result_json(result)["matchesReplaced"], 1);
    assert_eq!(fs::read_to_string(&path).unwrap(), "one two\n");
}

#[test]
fn replace_with_stale_token_reports_conflict_without_writing() {
    let workspace = tempfile::tempdir().unwrap();
    let path = workspace.path().join("notes.md");
    fs::write(&path, "one\n").unwrap();
    let payload = json!({
        "expectedFiles": [{ "relativePath": "notes.md", "contentToken": "0:0" }],
    });

    let value = replace_result_json(
        replace_workspace_matches(WorkspaceReplaceRequest {
            options: WorkspaceReplaceOptions {
                search: options(workspace.path(), "one"),
                replacement: "two".into(),
                preserve_case: false,
            },
            match_ids: Vec::new(),
            expected_files: expected_files(&payload),
        })
        .unwrap(),
    );

    assert_eq!(value["filesChanged"], 0);
    assert_eq!(value["conflicts"][0]["reason"], "File changed on disk");
    assert_eq!(fs::read_to_string(&path).unwrap(), "one\n");
}

#[test]
fn request_ids_are_scoped_to_the_client() {
    let payload = json!({ "requestId": "search-1" });

    assert_eq!(
        scoped_request_id(7, &payload).as_deref(),
        Some("mobile:7:search-1")
    );
    assert_ne!(
        scoped_request_id(7, &payload),
        scoped_request_id(8, &payload)
    );
    assert_eq!(scoped_request_id(7, &json!({ "requestId": "" })), None);
    assert_eq!(scoped_request_id(7, &json!({})), None);
}

#[test]
fn search_options_read_flags_and_trim_patterns() {
    let options = search_options(
        "/tmp".into(),
        "q".into(),
        &json!({
            "caseSensitive": true,
            "wholeWord": true,
            "useRegex": true,
            "includeIgnored": true,
            "includePattern": " *.rs ",
            "excludePattern": "   ",
            "maxResults": 50,
        }),
    );

    assert!(options.case_sensitive && options.whole_word && options.use_regex);
    assert!(options.include_ignored);
    assert_eq!(options.include_pattern.as_deref(), Some("*.rs"));
    assert_eq!(options.exclude_pattern, None);
    assert_eq!(options.max_results, Some(50));
}
