use super::super::actor_test_harness::test_actor;
use super::{
    absolute_workspace_file_target, prompt_attachment_root, validated_mobile_workspace_root,
};
use serde_json::json;
use std::collections::HashMap;
use std::path::Path;

#[test]
fn prompt_attachment_reads_are_limited_to_runtime_upload_stores() {
    let runtime = tempfile::tempdir().unwrap();
    let files = runtime.path().join("prompt-files");
    let outside = runtime.path().join("outside");
    std::fs::create_dir_all(&files).unwrap();
    std::fs::create_dir_all(&outside).unwrap();
    let attachment = files.join("attachment.txt");
    let unrelated = outside.join("private.txt");
    std::fs::write(&attachment, b"attachment").unwrap();
    std::fs::write(&unrelated, b"private").unwrap();

    let attachment = std::fs::canonicalize(attachment).unwrap();
    let unrelated = std::fs::canonicalize(unrelated).unwrap();
    assert!(prompt_attachment_root(runtime.path(), &attachment).is_ok());
    assert!(prompt_attachment_root(runtime.path(), &unrelated).is_err());
}

#[test]
fn mobile_roots_reject_protected_workspace_metadata() {
    let workspace = tempfile::tempdir().unwrap();
    let metadata = workspace.path().join(".git");
    std::fs::create_dir(&metadata).unwrap();

    let error = validated_mobile_workspace_root(&metadata, vec![workspace.path().to_path_buf()])
        .unwrap_err();

    assert!(error
        .wire_message()
        .contains("protected workspace metadata"));
}

#[test]
fn absolute_files_use_the_most_specific_known_workspace() {
    let directory = tempfile::tempdir().unwrap();
    let parent = directory.path().join("workspace");
    let nested = parent.join("packages/app");
    let file = nested.join("lib/main.dart");
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    std::fs::write(&file, b"void main() {}").unwrap();
    let nested_canonical = std::fs::canonicalize(&nested).unwrap();

    let (root, relative) = absolute_workspace_file_target(
        &file.to_string_lossy(),
        vec![
            parent.to_string_lossy().into_owned(),
            nested.to_string_lossy().into_owned(),
        ],
    )
    .unwrap();

    assert_eq!(root.canonical_path(), nested_canonical);
    assert_eq!(relative, Path::new("lib/main.dart").to_string_lossy());
}

#[test]
fn absolute_files_outside_known_workspaces_are_rejected() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let outside = directory.path().join("outside.txt");
    std::fs::create_dir_all(&workspace).unwrap();
    std::fs::write(&outside, b"outside").unwrap();

    let result = absolute_workspace_file_target(
        &outside.to_string_lossy(),
        vec![workspace.to_string_lossy().into_owned()],
    );

    assert!(result.is_err());
}

#[tokio::test]
async fn filesystem_requests_are_parked_before_runtime_lookup() {
    let directory = tempfile::tempdir().unwrap();
    let actor = test_actor(&directory, HashMap::new(), HashMap::new()).await;

    let started = actor.start_mobile_workspace_file_request(
        1,
        1,
        "mobile.workspaceFile.read",
        &json!({
            "workspaceId": "missing",
            "relativePath": "README.md",
        }),
    );

    assert!(started.is_ok());
    tokio::task::yield_now().await;
}
