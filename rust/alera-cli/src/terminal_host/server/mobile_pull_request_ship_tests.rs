use std::fs;
use std::path::Path;

use super::super::mobile_source_control_snapshot::tests::{init_repo, run_git};
use super::*;

fn repo() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    init_repo(dir.path());
    dir
}

fn root(dir: &tempfile::TempDir) -> String {
    dir.path().to_string_lossy().into_owned()
}

/// A bare `origin` holding the current `main`.
fn with_origin(dir: &Path) -> tempfile::TempDir {
    let remote = tempfile::tempdir().unwrap();
    run_git(remote.path(), &["init", "-q", "--bare", "-b", "main"]);
    run_git(
        dir,
        &["remote", "add", "origin", &remote.path().to_string_lossy()],
    );
    run_git(dir, &["push", "-q", "-u", "origin", "main"]);
    remote
}

fn commit(dir: &Path, file: &str, message: &str) {
    fs::write(dir.join(file), message).unwrap();
    run_git(dir, &["add", file]);
    run_git(dir, &["commit", "-q", "-m", message]);
}

fn message_of(error: HostError) -> String {
    error.wire_message()
}

#[test]
fn a_feature_branch_with_changes_needs_a_commit_in_place() {
    let dir = repo();
    run_git(dir.path(), &["checkout", "-q", "-b", "feat/x"]);
    fs::write(dir.path().join("tracked.txt"), "two\n").unwrap();

    let plan = plan_ship(&root(&dir), "main", ShipScope::All).unwrap();

    assert!(plan.needs_commit);
    assert!(!plan.move_off_base);
    assert_eq!(plan.source_branch, "feat/x");
}

#[test]
fn a_clean_feature_branch_ships_its_existing_commits() {
    let dir = repo();
    run_git(dir.path(), &["checkout", "-q", "-b", "feat/x"]);
    commit(dir.path(), "a.txt", "feat: add a");

    let plan = plan_ship(&root(&dir), "main", ShipScope::All).unwrap();

    assert!(!plan.needs_commit);
    assert_eq!(plan.existing_message.as_deref(), Some("feat: add a"));
}

#[test]
fn nothing_to_ship_is_refused() {
    let dir = repo();
    run_git(dir.path(), &["checkout", "-q", "-b", "feat/x"]);
    let error = plan_ship(&root(&dir), "main", ShipScope::All).unwrap_err();
    assert_eq!(message_of(error), "No changes to ship.");

    let dir = repo();
    let _origin = with_origin(dir.path());
    let error = plan_ship(&root(&dir), "main", ShipScope::All).unwrap_err();
    assert_eq!(message_of(error), "No changes to ship.");
}

#[test]
fn staged_scope_refuses_unstaged_leftovers() {
    let dir = repo();
    run_git(dir.path(), &["checkout", "-q", "-b", "feat/x"]);
    fs::write(dir.path().join("tracked.txt"), "two\n").unwrap();
    let error = plan_ship(&root(&dir), "main", ShipScope::Staged).unwrap_err();
    assert_eq!(
        message_of(error),
        "Stage at least one change before shipping."
    );
}

#[test]
fn unpushed_commits_on_main_move_to_a_ship_branch_and_main_returns_to_origin() {
    let dir = repo();
    let _origin = with_origin(dir.path());
    let origin_main = run_git(dir.path(), &["rev-parse", "origin/main"]);
    commit(
        dir.path(),
        "a.txt",
        "feat(mobile): add pull request actions",
    );
    let unpushed = run_git(dir.path(), &["rev-parse", "HEAD"]);

    let plan = plan_ship(&root(&dir), "main", ShipScope::All).unwrap();
    assert!(plan.move_off_base);
    assert!(plan.unpushed_on_base);
    assert!(!plan.needs_commit);
    assert_eq!(
        plan.existing_message.as_deref(),
        Some("feat(mobile): add pull request actions")
    );

    let branch = move_off_base(
        &root(&dir),
        &plan,
        plan.existing_message.as_deref().unwrap(),
    )
    .unwrap();

    assert_eq!(branch, "ship/add-pull-request-actions");
    assert_eq!(run_git(dir.path(), &["branch", "--show-current"]), branch);
    assert_eq!(run_git(dir.path(), &["rev-parse", "HEAD"]), unpushed);
    assert_eq!(run_git(dir.path(), &["rev-parse", "main"]), origin_main);
}

#[test]
fn a_taken_ship_branch_gets_a_numbered_name() {
    let dir = repo();
    run_git(dir.path(), &["branch", "ship/add-x"]);
    assert_eq!(
        available_ship_branch_name(&root(&dir), "feat: add x").unwrap(),
        "ship/add-x-2"
    );
}

#[test]
fn ship_branch_names_follow_the_desktop_slug() {
    assert_eq!(
        ship_branch_base("fix(ui)!: Crash on Save\n\nbody"),
        "ship/crash-on-save"
    );
    assert_eq!(ship_branch_base("  "), "ship/changes");
    assert_eq!(
        ship_branch_base(&format!("feat: {}", "word ".repeat(20))).len(),
        "ship/".len() + 48
    );
    assert!(requires_ship_branch("main", "develop"));
    assert!(requires_ship_branch("develop", "develop"));
    assert!(!requires_ship_branch("feat/x", "main"));
}

#[test]
fn failures_after_the_commit_say_so_and_keep_the_code() {
    let error = after_commit(HostError::conflict("noUpstream", "Push first.", json!({})));
    assert_eq!(
        error.wire_message(),
        "The changes were committed, but Ship could not finish: Push first."
    );
    assert_eq!(error.wire_response(1)["errorCode"], "noUpstream");
}
