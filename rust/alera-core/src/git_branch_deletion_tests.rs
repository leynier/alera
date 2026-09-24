use super::*;
use git2::Signature;

use super::super::{delete_branch, validate_branch_deletion};

fn signature() -> Signature<'static> {
    Signature::now("Alera Tests", "tests@alera.build").expect("signature")
}

fn squash_feature_into_ref(repo: &Repository, feature: &str, target_ref: &str) {
    let feature_commit = repo
        .find_branch(feature, BranchType::Local)
        .expect("feature")
        .get()
        .peel_to_commit()
        .expect("feature commit");
    let parent = repo
        .find_reference(target_ref)
        .ok()
        .and_then(|reference| reference.peel_to_commit().ok())
        .unwrap_or_else(|| {
            repo.find_branch("main", BranchType::Local)
                .expect("main")
                .get()
                .peel_to_commit()
                .expect("main commit")
        });
    let tree = feature_commit.tree().expect("feature tree");
    let sig = signature();
    repo.commit(Some(target_ref), &sig, &sig, "squash", &tree, &[&parent])
        .expect("squash commit");
}

#[test]
fn squash_merged_branch_is_safe_to_delete() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    squash_feature_into_ref(&repo, "feature", "refs/heads/main");

    validate_branch_deletion(path, "feature", false, None).expect("squash is integrated");
    delete_branch(path, "feature", false).expect("delete squash-merged branch");
    assert!(!super::super::branch_exists(path, "feature").expect("probe"));
}

#[test]
fn unique_unmerged_commits_are_not_safe_to_delete() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");

    let error = validate_branch_deletion(path, "feature", false, None).expect_err("unmerged");
    assert_eq!(error.kind, GitErrorKind::Conflict);
    assert!(error.context.contains("not merged"));
}

#[test]
fn squash_on_origin_default_is_safe_when_local_default_is_stale() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    let main = repo
        .find_branch("main", BranchType::Local)
        .expect("main")
        .get()
        .peel_to_commit()
        .expect("main commit");
    repo.reference(
        "refs/remotes/origin/main",
        main.id(),
        true,
        "seed origin/main",
    )
    .expect("origin/main");
    squash_feature_into_ref(&repo, "feature", "refs/remotes/origin/main");

    validate_branch_deletion(path, "feature", false, None)
        .expect("origin squash counts as integrated");
}

#[test]
fn merge_commit_into_default_is_safe_to_delete() {
    let (_directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    let feature = repo
        .find_branch("feature", BranchType::Local)
        .expect("feature")
        .get()
        .peel_to_commit()
        .expect("feature commit");
    let main = repo
        .find_branch("main", BranchType::Local)
        .expect("main")
        .get()
        .peel_to_commit()
        .expect("main commit");
    let tree = feature.tree().expect("feature tree");
    let sig = signature();
    repo.commit(
        Some("refs/heads/main"),
        &sig,
        &sig,
        "merge",
        &tree,
        &[&main, &feature],
    )
    .expect("merge commit");

    validate_branch_deletion(path, "feature", false, None).expect("merged");
}

#[test]
fn removing_worktree_may_delete_its_checked_out_branch() {
    let (directory, repo) = init_repo();
    let path = path_str(workdir(&repo));
    commit_on_branch(&repo, "feature", "tracked.txt", "feature\n", "feature");
    squash_feature_into_ref(&repo, "feature", "refs/heads/main");
    let child = directory.path().join("child");
    create_worktree(
        path,
        "feature",
        child.to_str().expect("utf-8"),
        "main",
        true,
    )
    .expect("worktree");

    validate_branch_deletion(path, "feature", false, Some(child.to_str().expect("utf-8")))
        .expect("removing worktree owns the checkout");
}
