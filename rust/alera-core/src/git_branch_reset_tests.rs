use super::*;

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
