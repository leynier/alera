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

#[tokio::test]
async fn remote_search_and_replace_never_use_a_matching_local_path() {
    use alera_core::runtime::{Workspace, WorkspaceKind, WorkspaceStatus};
    let root = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(root.path()).await.unwrap();
    let folder = root.path().join("checkout");
    fs::create_dir(&folder).unwrap();
    fs::write(folder.join("notes.txt"), "one").unwrap();
    let now = chrono::Utc::now();
    store
        .upsert_workspace(Workspace {
            id: "remote".into(),
            instance_id: "remote-instance".into(),
            host_id: "ssh:owner".into(),
            project_id: "p".into(),
            name: "Remote".into(),
            path: folder.to_string_lossy().into_owned(),
            branch: None,
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: vec![],
            tag_names: vec![],
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    let searched = result_json(search_workspace(options(&folder, "one")).unwrap());
    let payload = json!({
        "workspaceId":"remote", "query":"one", "replacement":"two",
        "matchIds":[searched["files"][0]["matches"][0]["id"]],
        "expectedFiles":[{"relativePath":"notes.txt", "contentToken":searched["files"][0]["contentToken"]}]
    });
    for operation in [
        "mobile.workspaceSearch.run",
        "mobile.workspaceSearch.replace",
    ] {
        let error = handle_mobile_workspace_search_request(&store, 1, operation, &payload)
            .await
            .unwrap_err();
        assert!(error
            .to_string()
            .contains("only available for workspaces on this runtime"));
        assert_eq!(fs::read_to_string(folder.join("notes.txt")).unwrap(), "one");
    }
}

#[tokio::test]
async fn an_explicit_empty_replacement_produces_a_deletion_preview() {
    use alera_core::runtime::{Workspace, WorkspaceKind, WorkspaceStatus};
    let root = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(root.path()).await.unwrap();
    let folder = root.path().join("checkout");
    fs::create_dir(&folder).unwrap();
    fs::write(folder.join("notes.txt"), "one two").unwrap();
    let now = chrono::Utc::now();
    store
        .upsert_workspace(Workspace {
            id: "task".into(),
            instance_id: "task-instance".into(),
            host_id: "local".into(),
            project_id: "p".into(),
            name: "Task".into(),
            path: folder.to_string_lossy().into_owned(),
            branch: None,
            created_at: now,
            updated_at: now,
            kind: WorkspaceKind::Linked,
            status: WorkspaceStatus::Active,
            source_branch: None,
            reuses_existing_branch: false,
            is_pinned: false,
            is_archived: false,
            tag_ids: vec![],
            tag_names: vec![],
            parent_workspace_id: None,
            section_id: None,
            child_count: 0,
        })
        .await
        .unwrap();
    let result = handle_mobile_workspace_search_request(
        &store,
        1,
        "mobile.workspaceSearch.run",
        &json!({"workspaceId":"task", "query":"one", "replacement":""}),
    )
    .await
    .unwrap();
    assert_eq!(result["files"][0]["matches"][0]["replacementPreview"], "");
    assert_eq!(
        fs::read_to_string(folder.join("notes.txt")).unwrap(),
        "one two"
    );
}

#[test]
fn repeated_large_previews_fit_the_relay_envelope_and_disable_replace_all() {
    let workspace = tempfile::tempdir().unwrap();
    for index in 0..4 {
        fs::write(
            workspace.path().join(format!("notes-{index}.md")),
            "one\n".repeat(50),
        )
        .unwrap();
    }
    for replacement in ["x".repeat(6000), "x".repeat(20000), "\"".repeat(6000)] {
        let preview = preview_workspace_replace(WorkspaceReplaceOptions {
            search: WorkspaceSearchOptions {
                max_results: Some(500),
                ..options(workspace.path(), "one")
            },
            replacement,
            preserve_case: false,
        })
        .unwrap();
        assert!(!preview.result.truncated);
        let value = result_json(preview.result);
        assert_eq!(value["truncated"], true);
        assert_eq!(value["totalMatches"], 200);
        let payload = serde_json::to_vec(&value).unwrap();
        assert!(payload.len() < 256 * 1024);
        assert!(crate::terminal_host::relay_wire::fragment(&payload).is_ok());
    }
}
