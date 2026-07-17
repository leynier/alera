use super::*;
use crate::api::git_explorer_status::{git_explorer_status_snapshot, GitExplorerStatus};

#[test]
fn detects_repository() {
    let repo = init_repo();
    assert!(is_git_repository(path_str(repo.path())).unwrap());

    let plain = tempfile::tempdir().expect("tempdir");
    assert!(!is_git_repository(path_str(plain.path())).unwrap());
}

#[test]
fn explorer_status_snapshot_aggregates_changed_ancestors_once() {
    let repo = init_repo();
    std::fs::create_dir_all(repo.path().join("src/nested")).expect("create nested");
    std::fs::write(repo.path().join("src/nested/new.txt"), "new").expect("write new");
    std::fs::write(repo.path().join("README.md"), "changed").expect("modify readme");

    let snapshot = git_explorer_status_snapshot(path_str(repo.path())).expect("snapshot");
    let statuses = snapshot
        .entries
        .into_iter()
        .map(|entry| (entry.path, entry.status))
        .collect::<std::collections::HashMap<_, _>>();

    assert_eq!(statuses["README.md"], GitExplorerStatus::Modified);
    assert_eq!(statuses["src/nested/new.txt"], GitExplorerStatus::Untracked);
    assert_eq!(statuses["src/nested"], GitExplorerStatus::Untracked);
    assert_eq!(statuses["src"], GitExplorerStatus::Untracked);
}
