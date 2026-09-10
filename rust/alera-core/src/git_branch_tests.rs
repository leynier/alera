use std::fs;
use std::path::{Path, PathBuf};

use git2::{BranchType, Repository, RepositoryInitOptions, Signature, StatusOptions};
use tempfile::TempDir;

use super::{
    checkout_branch, create_and_checkout_branch, create_and_checkout_branch_from, create_worktree,
    current_branch, reset_branch_to_ref, reset_branch_to_ref_from, GitErrorKind,
};

#[test]
fn creates_and_checks_out_branch_without_touching_pending_changes() {
    let (_directory, repo) = init_repo();
    fs::write(workdir(&repo).join("README.md"), "staged\n").expect("write staged file");
    let mut index = repo.index().expect("open index");
    index
        .add_path(Path::new("README.md"))
        .expect("stage README");
    index.write().expect("write index");
    fs::write(workdir(&repo).join("tracked.txt"), "unstaged\n").expect("write unstaged file");
    fs::write(workdir(&repo).join("untracked.txt"), "untracked\n").expect("write untracked file");
    let before = status_snapshot(&repo);
    let staged_blob = index_blob(&repo, "README.md");
    let main_oid = branch_oid(&repo, "main");

    create_and_checkout_branch(path_str(repo.path()), "ship/staged-change")
        .expect("create ship branch");

    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "ship/staged-change"
    );
    assert_eq!(branch_oid(&repo, "ship/staged-change"), main_oid);
    assert_eq!(status_snapshot(&repo), before);
    assert_eq!(index_blob(&repo, "README.md"), staged_blob);
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("README.md")).expect("read staged file"),
        "staged\n"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).expect("read unstaged file"),
        "unstaged\n"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("untracked.txt")).expect("read untracked file"),
        "untracked\n"
    );
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

#[test]
fn resets_a_non_head_branch_without_touching_head_or_status() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_workdir_file(&repo, "tracked.txt", "ahead\n", "feat: local commit");
    let ahead_oid = branch_oid(&repo, "main");
    create_and_checkout_branch(path_str(repo.path()), "ship/local-commit")
        .expect("create ship branch");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");
    fs::write(workdir(&repo).join("README.md"), "staged\n").expect("write staged file");
    let mut index = repo.index().expect("open index");
    index
        .add_path(Path::new("README.md"))
        .expect("stage README");
    index.write().expect("write index");
    fs::write(workdir(&repo).join("tracked.txt"), "unstaged\n").expect("write unstaged file");
    fs::write(workdir(&repo).join("untracked.txt"), "untracked\n").expect("write untracked file");
    let before = status_snapshot(&repo);
    let staged_blob = index_blob(&repo, "README.md");

    reset_branch_to_ref(path_str(repo.path()), "main", "origin/main").expect("reset main");

    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "ship/local-commit"
    );
    assert_eq!(branch_oid(&repo, "main"), main_oid);
    assert_eq!(branch_oid(&repo, "ship/local-commit"), ahead_oid);
    assert_eq!(status_snapshot(&repo), before);
    assert_eq!(index_blob(&repo, "README.md"), staged_blob);
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("README.md")).expect("read staged file"),
        "staged\n"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).expect("read unstaged file"),
        "unstaged\n"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("untracked.txt")).expect("read untracked file"),
        "untracked\n"
    );
}

#[test]
fn rejects_resetting_the_checked_out_branch() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");

    let error = reset_branch_to_ref(path_str(repo.path()), "main", "origin/main")
        .expect_err("resetting HEAD must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert_eq!(branch_oid(&repo, "main"), main_oid);
}

#[test]
fn rejects_resetting_a_missing_branch() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    create_and_checkout_branch(path_str(repo.path()), "ship/local").expect("create ship branch");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");

    let error = reset_branch_to_ref(path_str(repo.path()), "missing", "origin/main")
        .expect_err("missing branch must fail");

    assert_eq!(error.kind, GitErrorKind::BranchNotFound);
}

#[test]
fn rejects_resetting_a_missing_target_ref() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    create_and_checkout_branch(path_str(repo.path()), "ship/local").expect("create ship branch");

    let error = reset_branch_to_ref(path_str(repo.path()), "main", "origin/main")
        .expect_err("missing target must fail");

    assert_eq!(error.kind, GitErrorKind::BranchNotFound);
    assert_eq!(branch_oid(&repo, "main"), main_oid);
}

#[test]
fn rejects_resetting_a_branch_checked_out_in_another_worktree() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    let worktree_dir = TempDir::new().expect("linked worktree");
    let worktree_path = worktree_dir.path().join("feature");
    create_worktree(
        path_str(workdir(&repo)),
        "feature",
        path_str(&worktree_path),
        "main",
        true,
    )
    .expect("create linked worktree");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");

    let error = reset_branch_to_ref(path_str(&worktree_path), "main", "origin/main")
        .expect_err("occupied main must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert!(error.context.contains("checked out"));
    assert_eq!(
        current_branch(path_str(workdir(&repo))).expect("read main checkout"),
        "main"
    );
    assert_eq!(branch_oid(&repo, "main"), main_oid);
}

#[test]
fn rejects_creating_a_ship_branch_when_head_moved() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    let head = repo.find_commit(main_oid).expect("read main commit");
    repo.branch("other", &head, false).expect("create other");
    checkout_branch(path_str(workdir(&repo)), "other").expect("switch to other");

    let error = create_and_checkout_branch_from(
        path_str(repo.path()),
        "ship/local-commit",
        Some("main"),
        Some(&main_oid.to_string()),
    )
    .expect_err("moved HEAD must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "other"
    );
    assert!(!repo
        .find_branch("ship/local-commit", BranchType::Local)
        .is_ok());
}

#[test]
fn rejects_resetting_when_the_source_oid_changed() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_workdir_file(&repo, "tracked.txt", "ahead\n", "feat: local commit");
    let ahead_oid = branch_oid(&repo, "main");
    create_and_checkout_branch(path_str(repo.path()), "ship/local-commit")
        .expect("create ship branch");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");

    let error = reset_branch_to_ref_from(
        path_str(repo.path()),
        "main",
        "refs/remotes/origin/main",
        Some(&main_oid.to_string()),
    )
    .expect_err("changed source oid must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert_eq!(branch_oid(&repo, "main"), ahead_oid);
}

#[test]
fn rejects_resetting_when_head_is_locked() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_workdir_file(&repo, "tracked.txt", "ahead\n", "feat: local commit");
    create_and_checkout_branch(path_str(repo.path()), "ship/local-commit")
        .expect("create ship branch");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");
    let mut transaction = repo.transaction().expect("open transaction");
    transaction.lock_ref("HEAD").expect("lock HEAD");

    let error = reset_branch_to_ref(path_str(repo.path()), "main", "refs/remotes/origin/main")
        .expect_err("locked HEAD must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert_eq!(
        branch_oid(&repo, "main"),
        branch_oid(&repo, "ship/local-commit")
    );
}

#[test]
fn resets_using_the_remote_tracking_ref_when_a_local_origin_main_branch_exists() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_workdir_file(&repo, "tracked.txt", "ahead\n", "feat: local commit");
    let ahead_oid = branch_oid(&repo, "main");
    create_and_checkout_branch(path_str(repo.path()), "ship/local-commit")
        .expect("create ship branch");
    repo.reference(
        "refs/remotes/origin/main",
        main_oid,
        true,
        "remote tracking main",
    )
    .expect("create origin/main");
    repo.branch(
        "origin/main",
        &repo.find_commit(ahead_oid).expect("ahead"),
        false,
    )
    .expect("create colliding local origin/main");

    reset_branch_to_ref(path_str(repo.path()), "main", "refs/remotes/origin/main")
        .expect("reset main");

    assert_eq!(branch_oid(&repo, "main"), main_oid);
    assert_eq!(branch_oid(&repo, "ship/local-commit"), ahead_oid);
}

#[test]
fn rejects_resetting_a_branch_reserved_by_a_stopped_rebase() {
    let (_directory, repo) = init_repo();
    let main_oid = branch_oid(&repo, "main");
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    let feature_oid = branch_oid(&repo, "feature");
    let worktree_dir = TempDir::new().expect("linked worktree");
    let worktree_path = worktree_dir.path().join("feature");
    create_worktree(
        path_str(workdir(&repo)),
        "feature",
        path_str(&worktree_path),
        "main",
        true,
    )
    .expect("create linked worktree");
    let worktree_repo = Repository::open(&worktree_path).expect("open linked worktree");
    let rebase_dir = worktree_repo.path().join("rebase-merge");
    fs::create_dir_all(&rebase_dir).expect("create rebase-merge");
    fs::write(rebase_dir.join("head-name"), "refs/heads/feature\n").expect("write head-name");
    worktree_repo
        .set_head_detached(feature_oid)
        .expect("detach during rebase");
    repo.reference(
        "refs/remotes/origin/feature",
        main_oid,
        true,
        "remote tracking feature",
    )
    .expect("create origin/feature");

    let error = reset_branch_to_ref(
        path_str(workdir(&repo)),
        "feature",
        "refs/remotes/origin/feature",
    )
    .expect_err("rebase occupancy must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert!(error.context.contains("checked out"));
    assert_eq!(branch_oid(&repo, "feature"), feature_oid);
}

#[test]
fn switches_to_an_existing_local_branch() {
    let (_directory, repo) = init_repo();
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");

    checkout_branch(path_str(workdir(&repo)), "feature").expect("checkout feature");

    assert_eq!(
        current_branch(path_str(workdir(&repo))).expect("read current branch"),
        "feature"
    );
    assert_eq!(
        fs::read_to_string(workdir(&repo).join("tracked.txt")).expect("read tracked file"),
        "feature\n"
    );
}

#[test]
fn checkout_is_a_no_op_when_already_on_the_branch() {
    let (_directory, repo) = init_repo();

    checkout_branch(path_str(workdir(&repo)), "main").expect("checkout current branch");

    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "main"
    );
}

#[test]
fn rejects_checkout_when_local_changes_would_be_overwritten() {
    let (_directory, repo) = init_repo();
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    fs::write(workdir(&repo).join("tracked.txt"), "conflict\n").expect("write conflicting file");

    let error =
        checkout_branch(path_str(workdir(&repo)), "feature").expect_err("dirty checkout must fail");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert_eq!(
        current_branch(path_str(repo.path())).expect("read current branch"),
        "main"
    );
}

#[test]
fn rejects_a_missing_branch() {
    let (_directory, repo) = init_repo();

    let error =
        checkout_branch(path_str(workdir(&repo)), "missing").expect_err("missing branch must fail");

    assert_eq!(error.kind, GitErrorKind::BranchNotFound);
}

#[test]
fn checks_out_a_remote_tracking_branch_by_creating_a_local_tracker() {
    let (_directory, repo) = init_repo();
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    repo.remote("origin", "https://example.invalid/repo.git")
        .expect("add origin");
    let feature = repo
        .find_branch("feature", BranchType::Local)
        .expect("find feature");
    let feature_oid = feature.get().target().expect("feature target");
    drop(feature);
    repo.reference(
        "refs/remotes/origin/feature",
        feature_oid,
        true,
        "remote tracking feature",
    )
    .expect("create remote tracking branch");
    checkout_branch(path_str(workdir(&repo)), "main").expect("return to main");
    repo.find_branch("feature", BranchType::Local)
        .expect("find local feature")
        .delete()
        .expect("delete local feature");

    checkout_branch(path_str(workdir(&repo)), "origin/feature")
        .expect("checkout remote tracking branch");

    assert_eq!(
        current_branch(path_str(workdir(&repo))).expect("read current branch"),
        "feature"
    );
    let local = repo
        .find_branch("feature", BranchType::Local)
        .expect("local feature");
    let upstream = local.upstream().expect("upstream");
    assert_eq!(
        upstream.name().expect("upstream name").expect("name"),
        "origin/feature"
    );
}

#[test]
fn remote_selection_is_a_no_op_when_the_matching_local_is_current() {
    let (_directory, repo) = init_repo();
    repo.remote("origin", "https://example.invalid/repo.git")
        .expect("add origin");
    let head = repo
        .head()
        .expect("read HEAD")
        .peel_to_commit()
        .expect("read HEAD commit");
    repo.branch("feature", &head, false)
        .expect("create local feature");
    repo.reference(
        "refs/remotes/origin/feature",
        head.id(),
        true,
        "remote tracking feature",
    )
    .expect("create remote tracking branch");
    repo.set_head("refs/heads/feature")
        .expect("switch symbolic HEAD");
    drop(head);

    checkout_branch(path_str(workdir(&repo)), "origin/feature").expect("matching remote selection");

    assert_eq!(
        current_branch(path_str(workdir(&repo))).expect("read current branch"),
        "feature"
    );
}

#[test]
fn rejects_a_remote_selection_when_the_local_branch_has_diverged() {
    let (_directory, repo) = init_repo();
    repo.remote("origin", "https://example.invalid/repo.git")
        .expect("add origin");
    let head = repo
        .head()
        .expect("read HEAD")
        .peel_to_commit()
        .expect("read HEAD commit");
    repo.branch("feature", &head, false)
        .expect("create local feature");
    let tree = head.tree().expect("read HEAD tree");
    let signature = Signature::now("Alera Tests", "tests@alera.build").expect("signature");
    let remote_oid = repo
        .commit(
            None,
            &signature,
            &signature,
            "remote feature",
            &tree,
            &[&head],
        )
        .expect("create remote commit");
    repo.reference(
        "refs/remotes/origin/feature",
        remote_oid,
        true,
        "remote tracking feature",
    )
    .expect("create remote tracking branch");
    drop(tree);
    drop(head);

    let error = checkout_branch(path_str(workdir(&repo)), "origin/feature")
        .expect_err("divergent local branch must block remote selection");

    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert!(error.context.contains("local branch \"feature\""));
    assert!(error.context.contains("\"origin/feature\""));
    assert_eq!(
        current_branch(path_str(workdir(&repo))).expect("read current branch"),
        "main"
    );
}

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
