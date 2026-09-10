use super::*;

#[test]
fn range_context_uses_the_requested_head_ref() {
    let repo = init_repo();
    run_git(repo.path(), &["switch", "-c", "feature"]);
    commit_file(repo.path(), "feature.txt", "feature\n", "feature change");
    let feature_oid = branch_oid(repo.path(), "feature");
    run_git(repo.path(), &["switch", "main"]);
    commit_file(repo.path(), "main.txt", "main\n", "main change");

    let range = git_range_context(
        path_str(repo.path()),
        "main".to_string(),
        Some(40),
        Some(feature_oid.to_string()),
    )
    .expect("range context");

    assert_eq!(range.head_oid, feature_oid.to_string());
    assert_eq!(range.head_branch, None);
    assert_eq!(range.commits.len(), 1);
    assert_eq!(range.commits[0].subject, "feature change");
    assert!(range.files.iter().any(|file| file.path == "feature.txt"));
    assert!(!range.files.iter().any(|file| file.path == "main.txt"));
}

#[test]
fn range_context_is_empty_when_head_equals_base() {
    let repo = init_repo();
    commit_file(repo.path(), "second.txt", "second\n", "second");
    commit_file(repo.path(), "third.txt", "third\n", "third");

    let range = git_range_context(
        path_str(repo.path()),
        "main".to_string(),
        Some(40),
        Some("main".to_string()),
    )
    .expect("range context");

    assert!(range.commits.is_empty());
    assert!(range.files.is_empty());
}

#[test]
fn range_context_is_empty_when_head_is_behind_base() {
    let repo = init_repo();
    run_git(repo.path(), &["switch", "-c", "feature"]);
    run_git(repo.path(), &["switch", "main"]);
    commit_file(repo.path(), "main.txt", "main\n", "main change");
    commit_file(repo.path(), "later.txt", "later\n", "later change");

    let range = git_range_context(
        path_str(repo.path()),
        "main".to_string(),
        Some(40),
        Some("feature".to_string()),
    )
    .expect("range context");

    assert!(range.commits.is_empty());
    assert!(range.files.is_empty());
}

#[test]
fn range_context_resolves_a_remote_only_origin_base() {
    let origin = init_repo();
    run_git(origin.path(), &["switch", "-c", "develop"]);
    commit_file(origin.path(), "develop.txt", "develop\n", "develop base");
    let clone = tempfile::tempdir().expect("clone dir");
    run_git(
        origin.path(),
        &[
            "clone",
            "--branch",
            "develop",
            path_str(origin.path()).as_str(),
            path_str(clone.path()).as_str(),
        ],
    );
    run_git(clone.path(), &["switch", "-c", "feature"]);
    commit_file(clone.path(), "feature.txt", "feature\n", "feature change");
    run_git(clone.path(), &["branch", "-d", "develop"]);

    let range = git_range_context(
        path_str(clone.path()),
        "develop".to_string(),
        Some(40),
        Some("feature".to_string()),
    )
    .expect("range context");

    assert_eq!(range.commits.len(), 1);
    assert_eq!(range.commits[0].subject, "feature change");
    assert!(range.files.iter().any(|file| file.path == "feature.txt"));
}

#[test]
fn range_context_uses_the_remote_tracking_ref_when_a_local_origin_main_exists() {
    let repo = init_repo();
    run_git(
        repo.path(),
        &["update-ref", "refs/remotes/origin/main", "HEAD"],
    );
    run_git(repo.path(), &["switch", "-c", "feature"]);
    commit_file(repo.path(), "feature.txt", "feature\n", "feature change");
    run_git(repo.path(), &["branch", "origin/main"]);

    let range = git_range_context(
        path_str(repo.path()),
        "refs/remotes/origin/main".to_string(),
        Some(40),
        Some("refs/heads/feature".to_string()),
    )
    .expect("range context");

    assert_eq!(range.commits.len(), 1);
    assert_eq!(range.commits[0].subject, "feature change");
}

#[test]
fn range_context_truncates_an_oversized_ascii_patch() {
    let repo = init_repo();
    run_git(repo.path(), &["switch", "-c", "feature"]);
    let content = format!("{}\n", "a".repeat(210 * 1024));
    commit_file(repo.path(), "large.txt", &content, "large ascii");

    let range = git_range_context(
        path_str(repo.path()),
        "main".to_string(),
        Some(40),
        Some("feature".to_string()),
    )
    .expect("range context");

    assert_eq!(range.commits.len(), 1);
    assert!(range.files.iter().any(|file| file.path == "large.txt"));
    assert!(range.patch.contains("...(diff truncated)"));
    assert!(range.patch.is_char_boundary(range.patch.len()));
}

#[test]
fn range_context_truncates_an_oversized_multibyte_patch() {
    let repo = init_repo();
    run_git(repo.path(), &["switch", "-c", "feature"]);
    let content = format!("{}\n", "é".repeat(110 * 1024));
    commit_file(repo.path(), "unicode.txt", &content, "large unicode");

    let range = git_range_context(
        path_str(repo.path()),
        "main".to_string(),
        Some(40),
        Some("feature".to_string()),
    )
    .expect("range context");

    assert_eq!(range.commits.len(), 1);
    assert!(range.files.iter().any(|file| file.path == "unicode.txt"));
    assert!(range.patch.contains("...(diff truncated)"));
    assert!(range.patch.is_char_boundary(range.patch.len()));
}
