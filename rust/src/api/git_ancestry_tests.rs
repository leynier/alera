use super::*;

#[test]
fn reports_commit_ancestry_between_branches() {
    let repo = init_repo();
    run_git(repo.path(), &["checkout", "-b", "feature/one"]);
    commit_file(repo.path(), "one.txt", "one\n", "first layer");
    run_git(repo.path(), &["checkout", "-b", "feature/two"]);
    commit_file(repo.path(), "two.txt", "two\n", "second layer");

    let path = path_str(repo.path());
    assert!(is_ancestor(path.clone(), "main".to_string(), "feature/one".to_string()).unwrap());
    assert!(is_ancestor(
        path.clone(),
        "feature/one".to_string(),
        "feature/two".to_string(),
    )
    .unwrap());
    assert!(is_ancestor(
        path.clone(),
        "feature/two".to_string(),
        "feature/two".to_string(),
    )
    .unwrap());
    assert!(!is_ancestor(path, "feature/two".to_string(), "feature/one".to_string()).unwrap());
}

#[test]
fn ancestry_prefers_a_branch_over_a_same_named_tag() {
    let repo = init_repo();
    run_git(repo.path(), &["tag", "feature"]);
    run_git(repo.path(), &["checkout", "-b", "feature"]);
    commit_file(repo.path(), "feature.txt", "feature\n", "feature change");

    assert!(is_ancestor(
        path_str(repo.path()),
        "main".to_string(),
        "feature".to_string(),
    )
    .unwrap());
}

#[test]
fn ancestry_resolves_origin_tracking_branches() {
    let source = init_repo();
    run_git(source.path(), &["checkout", "-b", "feature/one"]);
    commit_file(source.path(), "one.txt", "one\n", "first layer");
    run_git(source.path(), &["checkout", "main"]);

    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(source.path(), &["push", "origin", "feature/one"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");

    assert!(is_ancestor(
        path_str(&clone_path),
        "main".to_string(),
        "feature/one".to_string(),
    )
    .unwrap());
}

#[test]
fn ancestry_reports_missing_refs() {
    let repo = init_repo();

    let error = is_ancestor(
        path_str(repo.path()),
        "missing".to_string(),
        "main".to_string(),
    )
    .expect_err("missing ancestor should fail");

    assert_eq!(error.kind, GitErrorKind::BranchNotFound);
    assert!(error.context.contains("missing"));
}
