use std::fs;
use std::path::Path;

use alera_core::child_process::windowless_command;

use super::*;

#[test]
fn snapshot_keeps_legacy_fields_and_adds_actions() {
    let workspace = tempfile::tempdir().unwrap();
    init_repo(workspace.path());
    fs::write(workspace.path().join("tracked.txt"), "two\n").unwrap();
    fs::write(workspace.path().join("new.txt"), "fresh\n").unwrap();

    let snapshot = git_status_snapshot(&workspace.path().to_string_lossy()).unwrap();

    assert_eq!(snapshot["isRepository"], true);
    assert_eq!(snapshot["branch"], "main");
    assert_eq!(snapshot["writable"], true);
    let entries = snapshot["entries"].as_array().unwrap();
    let tracked = entries
        .iter()
        .find(|entry| entry["path"] == "tracked.txt")
        .unwrap();
    assert_eq!(tracked["area"], "unstaged");
    assert_eq!(tracked["status"], "modified");
    assert_eq!(tracked["added"], 1);
    assert_eq!(tracked["removed"], 1);
    assert_eq!(tracked["isBinary"], false);
    assert_eq!(tracked["canStage"], true);
    assert_eq!(tracked["canUnstage"], false);
    assert_eq!(tracked["canDiscard"], true);
    let untracked = entries
        .iter()
        .find(|entry| entry["path"] == "new.txt")
        .unwrap();
    assert_eq!(untracked["area"], "untracked");

    assert_eq!(snapshot["repository"]["upstream"], Value::Null);
    assert_eq!(snapshot["repository"]["headMessage"], "init");
    assert_eq!(snapshot["repository"]["detached"], false);
    assert_eq!(snapshot["stashes"], json!([]));
    assert_eq!(snapshot["actions"]["stageAll"], true);
    assert_eq!(snapshot["actions"]["commit"], false);
    assert_eq!(snapshot["actions"]["publishBranch"], true);
    assert_eq!(snapshot["primaryAction"], "publishBranch");
}

#[test]
fn snapshot_reports_a_plain_directory_as_not_a_repository() {
    let workspace = tempfile::tempdir().unwrap();

    let snapshot = git_status_snapshot(&workspace.path().to_string_lossy()).unwrap();

    assert_eq!(snapshot["isRepository"], false);
    assert_eq!(snapshot["writable"], false);
    assert_eq!(snapshot["entries"], json!([]));
}

#[test]
fn git_errors_carry_a_code_and_the_desktop_wording() {
    let response = git_host_error(GitError::new(
        GitErrorKind::NothingToCommit,
        "no staged changes",
    ))
    .wire_response(7);
    assert_eq!(response["error"], "Nothing to commit.");
    assert_eq!(response["errorCode"], "gitNothingToCommit");

    let response = git_host_error(GitError::new(GitErrorKind::GitCli, "  ")).wire_response(7);
    assert_eq!(response["error"], "Git operation failed.");

    let response = git_host_error(GitError::new(
        GitErrorKind::WorkspaceScope,
        "staged change outside workspace: other.txt",
    ))
    .wire_response(7);
    assert_eq!(
        response["error"],
        "staged change outside workspace: other.txt"
    );
}

pub(in crate::terminal_host::server) fn init_repo(path: &Path) {
    run_git(path, &["init", "-q", "-b", "main"]);
    run_git(path, &["config", "user.name", "Alera"]);
    run_git(path, &["config", "user.email", "alera@example.com"]);
    fs::write(path.join("tracked.txt"), "one\n").unwrap();
    run_git(path, &["add", "tracked.txt"]);
    run_git(path, &["commit", "-q", "-m", "init"]);
}

pub(in crate::terminal_host::server) fn run_git(path: &Path, args: &[&str]) -> String {
    let output = windowless_command("git")
        .args(args)
        .current_dir(path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}
