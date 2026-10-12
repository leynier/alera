use super::*;
use std::fs;

fn fixture() -> (tempfile::TempDir, String) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_string_lossy().to_string();
    let repo = Repository::init(&path).unwrap();
    repo.config().unwrap().set_str("user.name", "Test").unwrap();
    repo.config()
        .unwrap()
        .set_str("user.email", "test@example.com")
        .unwrap();
    fs::write(dir.path().join("a.txt"), "a\n").unwrap();
    fs::write(dir.path().join("b.txt"), "b\n").unwrap();
    git_stage(path.clone(), None).unwrap();
    git_commit(path.clone(), "initial".into()).unwrap();
    (dir, path)
}

#[test]
fn workspace_comparison_combines_branch_and_disk_without_changing_index() {
    let (dir, path) = fixture();
    let repo = Repository::open(&path).unwrap();
    repo.branch(
        "base",
        &repo.head().unwrap().peel_to_commit().unwrap(),
        false,
    )
    .unwrap();
    fs::write(dir.path().join("a.txt"), "committed\n").unwrap();
    git_stage(path.clone(), None).unwrap();
    git_commit(path.clone(), "branch work".into()).unwrap();
    fs::write(dir.path().join("a.txt"), "disk\n").unwrap();
    fs::write(dir.path().join("new.txt"), "new\n").unwrap();
    let before = fs::read(repo.path().join("index")).unwrap();
    let review = git_workspace_comparison(path.clone(), Some("base".into())).unwrap();
    assert_eq!(review.entries.len(), 2);
    assert_eq!((review.added, review.removed), (2, 1));
    let diff = git_workspace_comparison_diff(path, review, "a.txt".into()).unwrap();
    assert!(diff.files[0].lines.iter().any(|line| line.text == "+disk"));
    assert_eq!(before, fs::read(repo.path().join("index")).unwrap());
}

#[test]
fn selected_commit_preserves_excluded_staged_files_and_commits_full_selected_file() {
    let (dir, path) = fixture();
    fs::write(dir.path().join("a.txt"), "staged a\n").unwrap();
    fs::write(dir.path().join("b.txt"), "staged b\n").unwrap();
    git_stage(path.clone(), None).unwrap();
    fs::write(dir.path().join("a.txt"), "disk a\n").unwrap();
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    git_commit_selected(
        path.clone(),
        snapshot,
        vec!["a.txt".into()],
        "selected".into(),
    )
    .unwrap();
    let repo = Repository::open(path).unwrap();
    let tree = repo.head().unwrap().peel_to_tree().unwrap();
    assert_eq!(
        repo.find_blob(tree.get_path(Path::new("a.txt")).unwrap().id())
            .unwrap()
            .content(),
        b"disk a\n"
    );
    assert_eq!(
        repo.find_blob(tree.get_path(Path::new("b.txt")).unwrap().id())
            .unwrap()
            .content(),
        b"b\n"
    );
    let index = repo.index().unwrap();
    assert_eq!(
        repo.find_blob(index.get_path(Path::new("b.txt"), 0).unwrap().id)
            .unwrap()
            .content(),
        b"staged b\n"
    );
    assert!(!repo.path().join("index.lock").exists());
}

#[test]
fn selected_commit_rejects_stale_snapshot_and_invalid_paths() {
    let (dir, path) = fixture();
    fs::write(dir.path().join("a.txt"), "reviewed\n").unwrap();
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    let before = fs::read(dir.path().join(".git/index")).unwrap();
    assert!(git_commit_selected(
        path.clone(),
        snapshot.clone(),
        vec!["../a.txt".into()],
        "bad".into()
    )
    .is_err());
    fs::write(dir.path().join("a.txt"), "changed\n").unwrap();
    assert!(git_commit_selected(path, snapshot, vec!["a.txt".into()], "stale".into()).is_err());
    assert_eq!(before, fs::read(dir.path().join(".git/index")).unwrap());
}

#[test]
fn unborn_workspace_comparison_and_commit() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_string_lossy().to_string();
    let repo = Repository::init(&path).unwrap();
    repo.config().unwrap().set_str("user.name", "Test").unwrap();
    repo.config()
        .unwrap()
        .set_str("user.email", "test@example.com")
        .unwrap();
    fs::write(dir.path().join("first"), "first\n").unwrap();
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    assert_eq!(snapshot.added, 1);
    assert!(snapshot.head_oid.is_none());
    git_commit_selected(path, snapshot, vec!["first".into()], "initial".into()).unwrap();
}

#[test]
fn comparison_preserves_renames_binaries_and_immutable_patches() {
    let (dir, path) = fixture();
    fs::rename(dir.path().join("a.txt"), dir.path().join("renamed.txt")).unwrap();
    fs::write(dir.path().join("binary.dat"), [0, 1, 2, 0, 3]).unwrap();
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    let renamed = snapshot
        .entries
        .iter()
        .find(|e| e.path == "renamed.txt")
        .unwrap();
    assert_eq!(renamed.status, GitChangeStatus::Renamed);
    assert_eq!(renamed.old_path.as_deref(), Some("a.txt"));
    let binary = snapshot
        .entries
        .iter()
        .find(|e| e.path == "binary.dat")
        .unwrap();
    assert!(binary.is_binary);
    assert_eq!((binary.added, binary.removed), (None, None));
    fs::write(dir.path().join("renamed.txt"), "unreviewed\n").unwrap();
    let patch = git_workspace_comparison_diff(path.clone(), snapshot.clone(), "renamed.txt".into())
        .unwrap();
    assert!(!patch.files[0]
        .lines
        .iter()
        .any(|line| line.text.contains("unreviewed")));
    fs::write(dir.path().join("renamed.txt"), "a\n").unwrap();
    git_commit_selected(
        path.clone(),
        snapshot,
        vec!["renamed.txt".into()],
        "rename".into(),
    )
    .unwrap();
    let repo = Repository::open(&path).unwrap();
    let tree = repo.head().unwrap().peel_to_tree().unwrap();
    assert!(tree.get_path(Path::new("a.txt")).is_err());
    assert!(tree.get_path(Path::new("renamed.txt")).is_ok());
    assert!(tree.get_path(Path::new("binary.dat")).is_err());
}

#[test]
fn selected_commit_refuses_index_changes_and_existing_locks() {
    let (dir, path) = fixture();
    fs::write(dir.path().join("a.txt"), "reviewed\n").unwrap();
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    fs::write(dir.path().join("b.txt"), "concurrent staging\n").unwrap();
    git_stage(path.clone(), Some("b.txt".into())).unwrap();
    let index = fs::read(dir.path().join(".git/index")).unwrap();
    assert!(
        git_commit_selected(path.clone(), snapshot, vec!["a.txt".into()], "stale".into()).is_err()
    );
    assert_eq!(index, fs::read(dir.path().join(".git/index")).unwrap());
    let snapshot = git_workspace_comparison(path.clone(), None).unwrap();
    for lock in ["HEAD.lock", "index.lock"] {
        let lock_path = dir.path().join(".git").join(lock);
        fs::write(&lock_path, "another client").unwrap();
        assert!(git_commit_selected(
            path.clone(),
            snapshot.clone(),
            vec!["a.txt".into()],
            "locked".into()
        )
        .is_err());
        assert_eq!(fs::read_to_string(&lock_path).unwrap(), "another client");
        fs::remove_file(lock_path).unwrap();
    }
}

#[test]
fn nested_workspace_comparison_and_commit_stay_in_scope() {
    let (dir, path) = fixture();
    fs::create_dir(dir.path().join("nested")).unwrap();
    fs::write(dir.path().join("nested/in.txt"), "initial\n").unwrap();
    git_stage(path.clone(), None).unwrap();
    git_commit(path.clone(), "nested initial".into()).unwrap();
    fs::write(dir.path().join("a.txt"), "outside\n").unwrap();
    fs::write(dir.path().join("nested/in.txt"), "inside\n").unwrap();
    let nested = dir.path().join("nested").to_string_lossy().to_string();
    let snapshot = git_workspace_comparison(nested.clone(), None).unwrap();
    assert_eq!(snapshot.entries.len(), 1);
    assert_eq!(snapshot.entries[0].path, "in.txt");
    assert_eq!((snapshot.added, snapshot.removed), (1, 1));
    let diff =
        git_workspace_comparison_diff(nested.clone(), snapshot.clone(), "in.txt".into()).unwrap();
    assert!(diff.files[0]
        .lines
        .iter()
        .any(|line| line.text == "+inside"));
    git_commit_selected(nested, snapshot, vec!["in.txt".into()], "nested".into()).unwrap();
    let repo = Repository::open(path).unwrap();
    let tree = repo.head().unwrap().peel_to_tree().unwrap();
    assert_eq!(
        repo.find_blob(tree.get_path(Path::new("a.txt")).unwrap().id())
            .unwrap()
            .content(),
        b"a\n"
    );
}

#[test]
fn workspace_default_branch_accepts_a_remote_only_default() {
    let (_dir, path) = fixture();
    let repo = Repository::open(&path).unwrap();
    repo.remote("origin", "https://example.com/repo.git")
        .unwrap();
    let oid = repo.head().unwrap().peel_to_commit().unwrap().id();
    repo.reference("refs/remotes/origin/trunk", oid, false, "test")
        .unwrap();
    repo.reference_symbolic(
        "refs/remotes/origin/HEAD",
        "refs/remotes/origin/trunk",
        false,
        "test",
    )
    .unwrap();
    assert_eq!(git_workspace_default_branch(path.clone()).unwrap(), "trunk");
    assert!(crate::git::default_branch(&path).is_err());
    let snapshot = git_workspace_comparison(path, Some("origin/trunk".into())).unwrap();
    assert!(snapshot.entries.is_empty());
}
