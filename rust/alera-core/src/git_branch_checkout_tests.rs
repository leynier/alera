use super::*;

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
