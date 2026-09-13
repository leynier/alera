#[path = "workspace_relocation_admin_tests.rs"]
mod relocation_admin_tests;

use std::fs;
use std::path::Path;

use git2::{Repository, RepositoryInitOptions, Signature};
use tempfile::TempDir;

use super::{default_branch, detach_head, set_head_to_branch, stash_include_untracked, stash_pop};
use crate::git::{current_branch, is_worktree_clean};

#[test]
fn immutable_stash_preserves_partial_index_and_other_stack_entries() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    fs::write(workdir(&repo).join("old.txt"), "older").unwrap();
    let older = super::stash_for_handoff(path).unwrap().unwrap();
    fs::write(workdir(&repo).join("tracked.txt"), "staged\n").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    fs::write(workdir(&repo).join("tracked.txt"), "unstaged\n").unwrap();
    fs::write(workdir(&repo).join("scratch.txt"), "mine").unwrap();
    let owned = super::stash_for_handoff(path).unwrap().unwrap();
    fs::write(workdir(&repo).join("newer.txt"), "newer").unwrap();
    let newer = super::stash_for_handoff(path).unwrap().unwrap();
    super::apply_handoff_stash(path, &owned).unwrap();
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).unwrap(),
        "unstaged\n"
    );
    let entry = repo
        .index()
        .unwrap()
        .get_path(Path::new("tracked.txt"), 0)
        .unwrap();
    assert_eq!(repo.find_blob(entry.id).unwrap().content(), b"staged\n");
    assert!(workdir(&repo).join("scratch.txt").exists());
    assert!(!workdir(&repo).join("old.txt").exists());
    assert!(!workdir(&repo).join("newer.txt").exists());
    let mut repo = Repository::open(workdir(&repo)).unwrap();
    let mut ids = Vec::new();
    repo.stash_foreach(|_, _, id| {
        ids.push(id.to_string());
        true
    })
    .unwrap();
    assert_eq!(ids, vec![newer, owned, older]);
}

#[test]
fn relocation_snapshot_recovers_after_journal_write_gap_and_other_stashes() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    let id = uuid::Uuid::new_v4().to_string();
    fs::write(workdir(&repo).join("task.txt"), "owned changes").unwrap();
    let snapshot = crate::git::stash_for_workspace_relocation(path, &id)
        .unwrap()
        .unwrap();
    // Simulate a crash between stash-save and pinning its recovery reference.
    repo.find_reference(&format!("refs/alera/workspace-relocations/{id}"))
        .unwrap()
        .delete()
        .unwrap();
    fs::write(workdir(&repo).join("other.txt"), "another task").unwrap();
    let unrelated = super::stash_for_handoff(path).unwrap().unwrap();
    assert_ne!(snapshot, unrelated);
    assert_eq!(
        crate::git::find_workspace_relocation_snapshot(path, &id).unwrap(),
        Some(snapshot.clone())
    );
    assert_eq!(
        crate::git::stash_for_workspace_relocation(path, &id).unwrap(),
        Some(snapshot.clone())
    );
    let reference = repo
        .find_reference(&format!("refs/alera/workspace-relocations/{id}"))
        .unwrap();
    assert_eq!(reference.target().unwrap().to_string(), snapshot);
    super::apply_handoff_stash(path, &snapshot).unwrap();
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("task.txt")).unwrap(),
        "owned changes"
    );
    assert!(!workdir(&repo).join("other.txt").exists());
}

#[test]
fn relocation_retry_refuses_to_recapture_new_source_changes() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    let id = uuid::Uuid::new_v4().to_string();
    fs::write(workdir(&repo).join("original.txt"), "move me").unwrap();
    let snapshot = crate::git::stash_for_workspace_relocation(path, &id)
        .unwrap()
        .unwrap();
    fs::write(workdir(&repo).join("later.txt"), "keep me here").unwrap();
    assert!(crate::git::stash_for_workspace_relocation(path, &id).is_err());
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("later.txt")).unwrap(),
        "keep me here"
    );
    assert_eq!(
        crate::git::find_workspace_relocation_snapshot(path, &id).unwrap(),
        Some(snapshot)
    );
}

#[test]
fn relocation_snapshot_apply_is_retryable_and_verifies_the_staging_boundary() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    let id = uuid::Uuid::new_v4().to_string();
    fs::write(workdir(&repo).join("tracked.txt"), "staged\n").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    fs::write(workdir(&repo).join("tracked.txt"), "unstaged\n").unwrap();
    fs::create_dir(workdir(&repo).join("scratch")).unwrap();
    fs::write(workdir(&repo).join("scratch/task.txt"), "new file").unwrap();
    let snapshot = crate::git::stash_for_workspace_relocation(path, &id)
        .unwrap()
        .unwrap();
    assert!(!crate::git::workspace_matches_relocation_snapshot(path, &snapshot).unwrap());
    crate::git::apply_workspace_relocation_snapshot(path, &snapshot).unwrap();
    crate::git::apply_workspace_relocation_snapshot(path, &snapshot).unwrap();
    assert!(crate::git::workspace_matches_relocation_snapshot(path, &snapshot).unwrap());

    // A staging-only change must not be mistaken for the completed transfer.
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("tracked.txt")).unwrap();
    index.write().unwrap();
    assert!(!crate::git::workspace_matches_relocation_snapshot(path, &snapshot).unwrap());
    assert!(crate::git::apply_workspace_relocation_snapshot(path, &snapshot).is_err());
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).unwrap(),
        "unstaged\n"
    );
}

#[test]
fn relocation_snapshot_retry_preserves_additional_and_modified_files() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    let id = uuid::Uuid::new_v4().to_string();
    fs::write(workdir(&repo).join("task.txt"), "transfer").unwrap();
    let snapshot = crate::git::stash_for_workspace_relocation(path, &id)
        .unwrap()
        .unwrap();
    crate::git::apply_workspace_relocation_snapshot(path, &snapshot).unwrap();
    fs::write(workdir(&repo).join("other.txt"), "another task").unwrap();
    assert!(!crate::git::workspace_matches_relocation_snapshot(path, &snapshot).unwrap());
    assert!(crate::git::apply_workspace_relocation_snapshot(path, &snapshot).is_err());
    fs::remove_file(workdir(&repo).join("other.txt")).unwrap();
    fs::write(workdir(&repo).join("task.txt"), "edited after transfer").unwrap();
    assert!(crate::git::apply_workspace_relocation_snapshot(path, &snapshot).is_err());
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("task.txt")).unwrap(),
        "edited after transfer"
    );
}

#[test]
fn relocation_worktree_creation_preserves_source_and_recovers_its_registration() {
    let (directory, repo) = init_repo();
    let source = path_str(workdir(&repo));
    let original_branch = current_branch(source).unwrap();
    let commit = crate::git::checkout_commit(source).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let destination = directory.path().join("linked-task");
    let destination = path_str(&destination);
    fs::write(workdir(&repo).join("left-here.txt"), "shared task changes").unwrap();
    crate::git::create_workspace_relocation_worktree(
        source,
        &id,
        destination,
        "task",
        &commit,
        false,
    )
    .unwrap();
    assert_eq!(current_branch(source).unwrap(), original_branch);
    assert!(workdir(&repo).join("left-here.txt").exists());
    assert!(!Path::new(destination).join("left-here.txt").exists());
    assert!(crate::git::checkouts_share_repository(source, destination).unwrap());
    crate::git::create_workspace_relocation_worktree(
        source,
        &id,
        destination,
        "task",
        &commit,
        false,
    )
    .unwrap();
    fs::write(Path::new(destination).join("later.txt"), "later work").unwrap();
    assert!(crate::git::create_workspace_relocation_worktree(
        source,
        &id,
        destination,
        "task",
        &commit,
        false
    )
    .is_err());
    assert!(Path::new(destination).join("later.txt").exists());
}

#[test]
fn relocation_worktree_retry_does_not_adopt_another_branch_or_directory() {
    let (directory, repo) = init_repo();
    let source = path_str(workdir(&repo));
    let commit = crate::git::checkout_commit(source).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let destination = directory.path().join("destination");
    let destination = path_str(&destination);
    repo.branch(
        "someone-elses",
        &repo.head().unwrap().peel_to_commit().unwrap(),
        false,
    )
    .unwrap();
    assert!(crate::git::create_workspace_relocation_worktree(
        source,
        &id,
        destination,
        "someone-elses",
        &commit,
        false
    )
    .is_err());
    assert!(!Path::new(destination).exists());
    fs::create_dir(destination).unwrap();
    fs::write(Path::new(destination).join("precious.txt"), "preserve").unwrap();
    assert!(crate::git::create_workspace_relocation_worktree(
        source,
        &id,
        destination,
        "new-task",
        &commit,
        false
    )
    .is_err());
    assert_eq!(
        fs::read_to_string(Path::new(destination).join("precious.txt")).unwrap(),
        "preserve"
    );
    assert!(!crate::git::branch_exists(source, "new-task").unwrap());
}

#[test]
fn failed_stash_apply_retains_immutable_recovery_commit() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    fs::write(workdir(&repo).join("tracked.txt"), "incoming\n").unwrap();
    let owned = super::stash_for_handoff(path).unwrap().unwrap();
    fs::write(workdir(&repo).join("tracked.txt"), "local\n").unwrap();
    let error = super::apply_handoff_stash(path, &owned).unwrap_err();
    assert!(error.to_string().contains(&owned));
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).unwrap(),
        "local\n"
    );
    assert!(repo
        .find_commit(git2::Oid::from_str(&owned).unwrap())
        .is_ok());
}

#[test]
fn ignored_data_blocks_handoff_cleanup() {
    let (_directory, repo) = init_repo();
    fs::write(repo.path().join("info/exclude"), "local-secret\n").unwrap();
    fs::write(workdir(&repo).join("local-secret"), "keep").unwrap();
    let path = path_str(workdir(&repo));
    assert!(is_worktree_clean(path).unwrap());
    assert!(super::validate_no_ignored_handoff_files(path).is_err());
    assert!(super::validate_handoff_removal(path).is_err());
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("local-secret")).unwrap(),
        "keep"
    );
}

#[test]
fn custom_remote_default_wins_over_main_name() {
    let (_directory, repo) = init_repo();
    let commit = repo.head().unwrap().peel_to_commit().unwrap();
    repo.branch("trunk", &commit, false).unwrap();
    repo.reference_symbolic(
        "refs/remotes/origin/HEAD",
        "refs/remotes/origin/trunk",
        true,
        "test",
    )
    .unwrap();
    assert_eq!(default_branch(path_str(workdir(&repo))).unwrap(), "trunk");
}

#[test]
fn checkout_preserves_ignored_collision() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    crate::git::create_and_checkout_branch(path, "feature").unwrap();
    fs::write(workdir(&repo).join("secret"), "tracked incoming").unwrap();
    let mut index = repo.index().unwrap();
    index.add_path(Path::new("secret")).unwrap();
    index.write().unwrap();
    let tree_id = index.write_tree().unwrap();
    let tree = repo.find_tree(tree_id).unwrap();
    let parent = repo.head().unwrap().peel_to_commit().unwrap();
    let signature = Signature::now("Test", "test@example.com").unwrap();
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        "track secret",
        &tree,
        &[&parent],
    )
    .unwrap();
    crate::git::checkout_branch(path, "main").unwrap();
    fs::write(repo.path().join("info/exclude"), "secret\n").unwrap();
    fs::write(workdir(&repo).join("secret"), "local ignored data").unwrap();
    assert!(crate::git::checkout_branch(path, "feature").is_err());
    assert_eq!(current_branch(path).unwrap(), "main");
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("secret")).unwrap(),
        "local ignored data"
    );
}

#[test]
fn stash_round_trips_tracked_and_untracked_files() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    fs::write(workdir(&repo).join("tracked.txt"), "dirty\n").expect("edit tracked");
    fs::write(workdir(&repo).join("scratch.txt"), "untracked\n").expect("write untracked");

    assert!(stash_include_untracked(path).expect("stash"));
    assert!(is_worktree_clean(path).expect("clean after stash"));
    assert!(!workdir(&repo).join("scratch.txt").exists());

    stash_pop(path).expect("pop stash");
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).expect("read tracked"),
        "dirty\n"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("scratch.txt")).expect("read untracked"),
        "untracked\n"
    );
}

#[test]
fn stash_is_a_no_op_when_the_worktree_is_clean() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    assert!(!stash_include_untracked(path).expect("clean stash"));
}

#[test]
fn default_branch_prefers_local_main() {
    let (_directory, repo) = init_repo();
    assert_eq!(
        default_branch(path_str(workdir(&repo))).expect("default branch"),
        "main"
    );
}

#[test]
fn detach_and_reattach_preserve_the_commit() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    detach_head(path).expect("detach");
    assert_eq!(current_branch(path).expect("detached name"), "HEAD");
    set_head_to_branch(path, "main").expect("reattach");
    assert_eq!(current_branch(path).expect("reattached"), "main");
}

fn init_repo() -> (TempDir, Repository) {
    let directory = TempDir::new().expect("temporary repository");
    let path = directory.path();
    let mut options = RepositoryInitOptions::new();
    options.initial_head("main");
    let repo = Repository::init_opts(path, &options).expect("initialize repository");
    repo.config()
        .unwrap()
        .set_bool("core.autocrlf", false)
        .unwrap();
    fs::write(path.join("README.md"), "initial\n").expect("write README");
    fs::write(path.join("tracked.txt"), "initial\n").expect("write tracked file");
    let mut index = repo.index().expect("open index");
    index
        .add_all(
            ["README.md", "tracked.txt"],
            git2::IndexAddOption::DEFAULT,
            None,
        )
        .expect("stage initial files");
    index.write().expect("write index");
    let tree_oid = index.write_tree().expect("write tree");
    let tree = repo.find_tree(tree_oid).expect("find tree");
    let signature = Signature::now("Alera Tests", "tests@alera.build").expect("signature");
    repo.commit(Some("HEAD"), &signature, &signature, "initial", &tree, &[])
        .expect("initial commit");
    drop(tree);
    (directory, repo)
}

fn workdir(repo: &Repository) -> &Path {
    repo.workdir().expect("workdir")
}

fn path_str(path: &Path) -> &str {
    path.to_str().expect("utf-8 path")
}
