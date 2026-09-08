use std::fs;
use std::path::Path;

use git2::{Repository, RepositoryInitOptions, Signature};
use tempfile::TempDir;

use super::{default_branch, detach_head, set_head_to_branch, stash_include_untracked, stash_pop};
use crate::git::{current_branch, is_worktree_clean};

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
