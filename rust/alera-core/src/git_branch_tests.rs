use std::fs;
use std::path::{Path, PathBuf};

use git2::{BranchType, Repository, RepositoryInitOptions, Signature, StatusOptions};
use tempfile::TempDir;

use super::{create_and_checkout_branch, current_branch, GitErrorKind};

#[test]
fn creates_and_checks_out_branch_without_touching_pending_changes() {
    let (_directory, repo) = init_repo();
    fs::write(repo.path().join("README.md"), "staged\n").expect("write staged file");
    let mut index = repo.index().expect("open index");
    index
        .add_path(Path::new("README.md"))
        .expect("stage README");
    index.write().expect("write index");
    fs::write(repo.path().join("tracked.txt"), "unstaged\n").expect("write unstaged file");
    fs::write(repo.path().join("untracked.txt"), "untracked\n").expect("write untracked file");
    let before = status_snapshot(&repo);
    let main_oid = branch_oid(&repo, "main");

    create_and_checkout_branch(path_str(repo.path()), "ship/staged-change")
        .expect("create ship branch");

    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "ship/staged-change"
    );
    assert_eq!(branch_oid(&repo, "ship/staged-change"), main_oid);
    assert_eq!(status_snapshot(&repo), before);
}

#[test]
fn rejects_an_existing_branch_without_switching_head() {
    let (_directory, repo) = init_repo();
    let head = repo
        .head()
        .expect("read HEAD")
        .peel_to_commit()
        .expect("read HEAD commit");
    repo.branch("ship/existing", &head, false)
        .expect("create existing branch");

    let error = create_and_checkout_branch(path_str(repo.path()), "ship/existing")
        .expect_err("existing branch must fail");

    assert_eq!(error.kind, GitErrorKind::BranchAlreadyExists);
    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "main"
    );
}

#[test]
fn rejects_detached_head() {
    let (_directory, repo) = init_repo();
    let head_oid = repo
        .head()
        .expect("read HEAD")
        .target()
        .expect("HEAD target");
    repo.set_head_detached(head_oid).expect("detach HEAD");

    let error = create_and_checkout_branch(path_str(repo.path()), "ship/detached")
        .expect_err("detached HEAD must fail");

    assert_eq!(error.kind, GitErrorKind::DetachedHead);
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
