use std::fs;
use std::path::{Path, PathBuf};

use git2::{BranchType, Repository, RepositoryInitOptions, Signature, StatusOptions};
use tempfile::TempDir;

use super::{
    checkout_branch, create_and_checkout_branch, create_and_checkout_branch_from, create_worktree,
    current_branch, reset_branch_to_ref, reset_branch_to_ref_from, GitErrorKind,
};

#[path = "git_branch_checkout_tests.rs"]
mod git_branch_checkout_tests;
#[path = "git_branch_create_tests.rs"]
mod git_branch_create_tests;
#[path = "git_branch_reset_tests.rs"]
mod git_branch_reset_tests;

fn workdir(repo: &Repository) -> &Path {
    repo.workdir().expect("workdir")
}

fn commit_workdir_file(repo: &Repository, file_name: &str, content: &str, message: &str) {
    let workdir = repo.workdir().expect("workdir");
    fs::write(workdir.join(file_name), content).expect("write file");
    let mut index = repo.index().expect("open index");
    index.add_path(Path::new(file_name)).expect("stage file");
    index.write().expect("write index");
    let tree_oid = index.write_tree().expect("write tree");
    let tree = repo.find_tree(tree_oid).expect("find tree");
    let parent = repo
        .head()
        .expect("read HEAD")
        .peel_to_commit()
        .expect("read HEAD commit");
    let signature = Signature::now("Alera Tests", "tests@alera.build").expect("signature");
    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        message,
        &tree,
        &[&parent],
    )
    .expect("commit on HEAD");
}

fn commit_on_branch(
    repo: &Repository,
    branch: &str,
    file_name: &str,
    content: &str,
    message: &str,
) {
    let head = repo
        .head()
        .expect("read HEAD")
        .peel_to_commit()
        .expect("read HEAD commit");
    repo.branch(branch, &head, false).expect("create branch");
    let workdir = repo.workdir().expect("workdir");
    fs::write(workdir.join(file_name), content).expect("write file");
    let mut index = repo.index().expect("open index");
    index.add_path(Path::new(file_name)).expect("stage file");
    index.write().expect("write index");
    let tree_oid = index.write_tree().expect("write tree");
    let tree = repo.find_tree(tree_oid).expect("find tree");
    let signature = Signature::now("Alera Tests", "tests@alera.build").expect("signature");
    repo.commit(
        Some(&format!("refs/heads/{branch}")),
        &signature,
        &signature,
        message,
        &tree,
        &[&head],
    )
    .expect("commit on branch");
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

fn index_blob(repo: &Repository, file_name: &str) -> Vec<u8> {
    let entry = repo
        .index()
        .expect("open index")
        .get_path(Path::new(file_name), 0)
        .expect("index entry");
    repo.find_blob(entry.id)
        .expect("find blob")
        .content()
        .to_vec()
}

fn branch_oid(repo: &Repository, branch: &str) -> git2::Oid {
    repo.find_branch(branch, BranchType::Local)
        .expect("find branch")
        .get()
        .target()
        .expect("branch target")
}

fn status_snapshot(repo: &Repository) -> Vec<(PathBuf, u32)> {
    let mut options = StatusOptions::new();
    options.include_untracked(true).recurse_untracked_dirs(true);
    let statuses = repo.statuses(Some(&mut options)).expect("read status");
    let mut snapshot = statuses
        .iter()
        .map(|entry| {
            (
                PathBuf::from(entry.path().expect("status path")),
                entry.status().bits(),
            )
        })
        .collect::<Vec<_>>();
    snapshot.sort_by(|left, right| left.0.cmp(&right.0));
    snapshot
}

fn path_str(path: &Path) -> &str {
    path.to_str().expect("utf-8 path")
}
