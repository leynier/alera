use super::*;

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
