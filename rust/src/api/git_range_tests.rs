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
