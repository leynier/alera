use super::*;
use crate::api::git_diff_blob::git_diff_blob_bytes;

#[test]
fn git_diff_blob_bytes_returns_both_sides_for_unstaged_binary_change() {
    let repo = init_repo();
    let old_bytes: Vec<u8> = vec![0x89, b'P', b'N', b'G', 1, 2, 3];
    let new_bytes: Vec<u8> = vec![0x89, b'P', b'N', b'G', 9, 8, 7, 6];
    std::fs::write(repo.path().join("logo.png"), &old_bytes).expect("write image");
    run_git(repo.path(), &["add", "logo.png"]);
    run_git(repo.path(), &["commit", "-m", "add image"]);
    std::fs::write(repo.path().join("logo.png"), &new_bytes).expect("modify image");

    let old_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        true,
    )
    .unwrap();
    let new_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        false,
    )
    .unwrap();

    assert_eq!(old_side, Some(old_bytes));
    assert_eq!(new_side, Some(new_bytes));
}

#[test]
fn git_diff_blob_bytes_reads_staged_side_from_head_and_index() {
    let repo = init_repo();
    let old_bytes: Vec<u8> = vec![1, 2, 3];
    let staged_bytes: Vec<u8> = vec![4, 5, 6, 7];
    std::fs::write(repo.path().join("logo.png"), &old_bytes).expect("write image");
    run_git(repo.path(), &["add", "logo.png"]);
    run_git(repo.path(), &["commit", "-m", "add image"]);
    std::fs::write(repo.path().join("logo.png"), &staged_bytes).expect("modify image");
    run_git(repo.path(), &["add", "logo.png"]);

    let old_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        true,
    )
    .unwrap();
    let new_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        false,
    )
    .unwrap();

    assert_eq!(old_side, Some(old_bytes));
    assert_eq!(new_side, Some(staged_bytes));
}

#[test]
fn git_diff_blob_bytes_has_no_old_side_for_untracked_files() {
    let repo = init_repo();
    let bytes: Vec<u8> = vec![9, 9, 9];
    std::fs::write(repo.path().join("new.png"), &bytes).expect("write image");

    let old_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "new.png".to_string(),
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        true,
    )
    .unwrap();
    let new_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "new.png".to_string(),
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        false,
    )
    .unwrap();

    assert_eq!(old_side, None);
    assert_eq!(new_side, Some(bytes));
}

#[test]
fn git_diff_blob_bytes_resolves_commit_diff_sides() {
    let repo = init_repo();
    let old_bytes: Vec<u8> = vec![1, 1, 1];
    let new_bytes: Vec<u8> = vec![2, 2, 2, 2];
    std::fs::write(repo.path().join("logo.png"), &old_bytes).expect("write image");
    run_git(repo.path(), &["add", "logo.png"]);
    run_git(repo.path(), &["commit", "-m", "add image"]);
    std::fs::write(repo.path().join("logo.png"), &new_bytes).expect("modify image");
    run_git(repo.path(), &["add", "logo.png"]);
    run_git(repo.path(), &["commit", "-m", "modify image"]);
    let history = git_history(path_str(repo.path()), Some(5), None).unwrap();
    let commit_oid = history.items[0].id.clone();

    let old_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        None,
        Some(commit_oid.clone()),
        None,
        true,
    )
    .unwrap();
    let new_side = git_diff_blob_bytes(
        path_str(repo.path()),
        "logo.png".to_string(),
        None,
        None,
        Some(commit_oid),
        None,
        false,
    )
    .unwrap();

    assert_eq!(old_side, Some(old_bytes));
    assert_eq!(new_side, Some(new_bytes));
}

#[test]
fn git_diff_blob_bytes_returns_none_for_missing_sides() {
    let repo = init_repo();
    // Deleted file: unstaged delete keeps the index side but not the workdir.
    run_git(repo.path(), &["rm", "--cached", "README.md"]);

    let staged_new = git_diff_blob_bytes(
        path_str(repo.path()),
        "README.md".to_string(),
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        false,
    )
    .unwrap();
    assert_eq!(staged_new, None);

    let missing = git_diff_blob_bytes(
        path_str(repo.path()),
        "does-not-exist.png".to_string(),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        true,
    )
    .unwrap();
    assert_eq!(missing, None);
}
