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
