use std::fs;

use super::{git_status_snapshot, source_control_root};

#[test]
fn source_control_root_defaults_to_workspace() {
    let workspace = tempfile::tempdir().unwrap();
    let root = workspace.path().to_string_lossy();
    assert_eq!(source_control_root(&root, None).unwrap(), root);
    assert_eq!(source_control_root(&root, Some("")).unwrap(), root);
    assert_eq!(source_control_root(&root, Some("/")).unwrap(), root);
}

#[test]
fn source_control_root_rejects_escapes() {
    let workspace = tempfile::tempdir().unwrap();
    let root = workspace.path().to_string_lossy();
    assert!(source_control_root(&root, Some("../outside")).is_err());
    assert!(source_control_root(&root, Some("nested/../../outside")).is_err());
}

#[test]
fn nested_root_reads_its_own_repository() {
    let workspace = tempfile::tempdir().unwrap();
    let nested = workspace.path().join("service");
    fs::create_dir(&nested).unwrap();
    git2::Repository::init(&nested).unwrap();
    fs::write(nested.join("new.txt"), "fresh\n").unwrap();
    let workspace_root = workspace.path().to_string_lossy();

    let at_workspace =
        git_status_snapshot(&source_control_root(&workspace_root, None).unwrap()).unwrap();
    assert_eq!(at_workspace["isRepository"], false);

    let root = source_control_root(&workspace_root, Some("service")).unwrap();
    let snapshot = git_status_snapshot(&root).unwrap();
    assert_eq!(snapshot["isRepository"], true);
    let entries = snapshot["entries"].as_array().unwrap();
    assert!(entries
        .iter()
        .any(|entry| entry["path"].as_str() == Some("new.txt")));
}

#[test]
fn nested_root_without_repository_reports_none() {
    let workspace = tempfile::tempdir().unwrap();
    fs::create_dir(workspace.path().join("docs")).unwrap();
    let root = source_control_root(&workspace.path().to_string_lossy(), Some("docs")).unwrap();
    assert_eq!(git_status_snapshot(&root).unwrap()["isRepository"], false);
}

#[cfg(unix)]
#[test]
fn source_control_root_rejects_symlink_escape() {
    let workspace = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    git2::Repository::init(outside.path()).unwrap();
    std::os::unix::fs::symlink(outside.path(), workspace.path().join("link")).unwrap();
    assert!(source_control_root(&workspace.path().to_string_lossy(), Some("link")).is_err());
}
