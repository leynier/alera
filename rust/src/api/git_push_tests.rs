use super::*;

fn rev_parse(dir: &Path, rev: &str) -> String {
    let output = git_command(dir, &["rev-parse", rev])
        .output()
        .expect("rev-parse runs");
    assert!(
        output.status.success(),
        "rev-parse {rev} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

#[test]
fn git_push_publishes_worktree_branch_that_tracks_the_source_upstream() {
    let repo = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        repo.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(repo.path(), &["checkout", "-b", "develop"]);
    run_git(repo.path(), &["push", "-u", "origin", "develop"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/develop"]);
    let remote_develop = rev_parse(bare.path(), "refs/heads/develop");

    let worktree_base = tempfile::tempdir().expect("worktree base");
    let worktree_path = worktree_base.path().join("fix-git-push-issue");
    create_worktree(
        path_str(repo.path()),
        "fix/git-push-issue".to_string(),
        path_str(&worktree_path),
        "origin/develop".to_string(),
        false,
    )
    .unwrap();
    configure_git_identity(&worktree_path);
    run_git(&worktree_path, &["config", "push.default", "simple"]);
    commit_file(&worktree_path, "feature.txt", "feature\n", "feature change");

    let state = git_repository_state(path_str(&worktree_path)).unwrap();
    assert_eq!(state.branch, "fix/git-push-issue");
    assert_eq!(state.upstream.as_deref(), Some("origin/develop"));
    run_git_expect_failure(&worktree_path, &["push"]);

    git_push(path_str(&worktree_path)).unwrap();

    let state = git_repository_state(path_str(&worktree_path)).unwrap();
    assert_eq!(state.upstream.as_deref(), Some("origin/fix/git-push-issue"));
    assert_eq!(state.ahead, 0);
    assert_eq!(rev_parse(bare.path(), "refs/heads/develop"), remote_develop);
    assert_eq!(
        rev_parse(bare.path(), "refs/heads/fix/git-push-issue"),
        rev_parse(&worktree_path, "HEAD")
    );
}

#[test]
fn git_push_keeps_a_matching_upstream() {
    let repo = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        repo.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(repo.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);
    commit_file(repo.path(), "next.txt", "next\n", "next change");
    run_git(repo.path(), &["config", "push.default", "simple"]);

    git_push(path_str(repo.path())).unwrap();

    let state = git_repository_state(path_str(repo.path())).unwrap();
    assert_eq!(state.upstream.as_deref(), Some("origin/main"));
    assert_eq!(state.ahead, 0);
    assert_eq!(
        rev_parse(bare.path(), "refs/heads/main"),
        rev_parse(repo.path(), "HEAD")
    );
}
