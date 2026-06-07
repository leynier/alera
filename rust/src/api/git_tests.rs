use super::*;
use std::path::Path;
use std::process::Command;

#[path = "git_diff_edge_tests.rs"]
mod git_diff_edge_tests;

fn run_git(dir: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_AUTHOR_NAME", "Test")
        .env("GIT_AUTHOR_EMAIL", "test@example.com")
        .env("GIT_COMMITTER_NAME", "Test")
        .env("GIT_COMMITTER_EMAIL", "test@example.com")
        .status()
        .expect("git command runs");
    assert!(status.success(), "git {:?} failed", args);
}

fn init_repo() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    run_git(dir.path(), &["init", "-b", "main"]);
    std::fs::write(dir.path().join("README.md"), "hello").expect("write");
    run_git(dir.path(), &["add", "."]);
    run_git(dir.path(), &["commit", "-m", "initial"]);
    dir
}

fn path_str(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

#[test]
fn detects_repository() {
    let repo = init_repo();
    assert!(is_git_repository(path_str(repo.path())).unwrap());

    let plain = tempfile::tempdir().expect("tempdir");
    assert!(!is_git_repository(path_str(plain.path())).unwrap());
}

#[test]
fn rejects_bare_repository() {
    let bare = tempfile::tempdir().expect("tempdir");
    run_git(bare.path(), &["init", "--bare"]);

    assert!(!is_git_repository(path_str(bare.path())).unwrap());
}

#[test]
fn reports_branches_and_current() {
    let repo = init_repo();
    run_git(repo.path(), &["branch", "feature"]);

    let branches = list_branches(path_str(repo.path())).unwrap();
    assert!(branches.contains(&"main".to_string()));
    assert!(branches.contains(&"feature".to_string()));

    assert_eq!(current_branch(path_str(repo.path())).unwrap(), "main");
    assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
    assert!(!branch_exists(path_str(repo.path()), "missing".to_string()).unwrap());
}

#[test]
fn validates_branch_names() {
    assert!(is_valid_branch_name("feature/login".to_string()).unwrap());
    assert!(!is_valid_branch_name("bad branch".to_string()).unwrap());
}

#[test]
fn creates_lists_and_removes_worktree() {
    let repo = init_repo();
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("feature"));

    create_worktree(
        path_str(repo.path()),
        "feature".to_string(),
        worktree_path.clone(),
        "main".to_string(),
    )
    .unwrap();

    assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
    let worktrees = list_worktrees(path_str(repo.path())).unwrap();
    assert!(worktrees.iter().any(|entry| entry.branch == "feature"));
    assert!(worktrees.iter().any(|entry| entry.branch == "main"));

    remove_worktree(path_str(repo.path()), worktree_path.clone(), true).unwrap();
    let worktrees = list_worktrees(path_str(repo.path())).unwrap();
    assert!(!worktrees.iter().any(|entry| entry.branch == "feature"));

    delete_branch(path_str(repo.path()), "feature".to_string(), true).unwrap();
    assert!(!branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
}

#[test]
fn rejects_duplicate_branch() {
    let repo = init_repo();
    run_git(repo.path(), &["branch", "feature"]);
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("dupe"));
    let error = create_worktree(
        path_str(repo.path()),
        "feature".to_string(),
        worktree_path,
        "main".to_string(),
    )
    .unwrap_err();
    assert!(matches!(error.kind, GitErrorKind::BranchAlreadyExists));
}

#[test]
fn operates_from_subdirectory() {
    let repo = init_repo();
    let subdir = repo.path().join("nested").join("dir");
    std::fs::create_dir_all(&subdir).expect("create subdir");

    let subdir_path = path_str(&subdir);
    assert!(is_git_repository(subdir_path.clone()).unwrap());
    assert_eq!(current_branch(subdir_path.clone()).unwrap(), "main");
    assert!(list_branches(subdir_path)
        .unwrap()
        .contains(&"main".to_string()));
}

#[test]
fn creates_worktree_from_remote_tracking_branch() {
    let repo = init_repo();
    run_git(
        repo.path(),
        &["remote", "add", "origin", "https://example.com/repo.git"],
    );
    run_git(
        repo.path(),
        &["update-ref", "refs/remotes/origin/feature", "HEAD"],
    );

    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("from-remote"));
    create_worktree(
        path_str(repo.path()),
        "local-feature".to_string(),
        worktree_path,
        "origin/feature".to_string(),
    )
    .unwrap();

    assert!(branch_exists(path_str(repo.path()), "local-feature".to_string()).unwrap());
    let repo_handle = Repository::open(repo.path()).unwrap();
    let config = repo_handle.config().unwrap();
    assert_eq!(
        config.get_string("branch.local-feature.remote").unwrap(),
        "origin"
    );
    assert_eq!(
        config.get_string("branch.local-feature.merge").unwrap(),
        "refs/heads/feature"
    );
}

#[test]
fn rolls_back_branch_when_worktree_fails() {
    let repo = init_repo();
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let blocked = worktree_base.path().join("blocked");
    std::fs::create_dir_all(&blocked).expect("create blocker dir");
    std::fs::write(blocked.join("busy.txt"), "x").expect("write blocker");
    let worktree_path = path_str(&blocked);

    let error = create_worktree(
        path_str(repo.path()),
        "feature".to_string(),
        worktree_path.clone(),
        "main".to_string(),
    )
    .unwrap_err();
    assert!(!matches!(error.kind, GitErrorKind::BranchAlreadyExists));
    assert!(!branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());

    std::fs::remove_dir_all(&worktree_path).expect("remove blocker dir");
    create_worktree(
        path_str(repo.path()),
        "feature".to_string(),
        worktree_path,
        "main".to_string(),
    )
    .unwrap();
    assert!(branch_exists(path_str(repo.path()), "feature".to_string()).unwrap());
}

#[test]
fn creates_same_basename_worktrees_under_different_parents() {
    let repo = init_repo();
    let parent_a = tempfile::tempdir().expect("tempdir");
    let parent_b = tempfile::tempdir().expect("tempdir");
    let path_a = path_str(&parent_a.path().join("shared"));
    let path_b = path_str(&parent_b.path().join("shared"));

    create_worktree(
        path_str(repo.path()),
        "feature-a".to_string(),
        path_a.clone(),
        "main".to_string(),
    )
    .unwrap();
    create_worktree(
        path_str(repo.path()),
        "feature-b".to_string(),
        path_b.clone(),
        "main".to_string(),
    )
    .unwrap();

    assert!(Path::new(&path_a).join(".git").exists());
    assert!(Path::new(&path_b).join(".git").exists());

    let worktrees = list_worktrees(path_str(repo.path())).unwrap();
    let target_a = canonical(&path_a);
    let target_b = canonical(&path_b);
    assert!(worktrees
        .iter()
        .any(|entry| canonical(&entry.path) == target_a && entry.branch == "feature-a"));
    assert!(worktrees
        .iter()
        .any(|entry| canonical(&entry.path) == target_b && entry.branch == "feature-b"));
}

#[test]
fn split_clone_destination_uses_basename_under_parent() {
    assert_eq!(
        split_clone_destination("repos/demo").unwrap(),
        ("repos".to_string(), "demo".to_string())
    );
    assert_eq!(
        split_clone_destination("/abs/repos/demo").unwrap(),
        ("/abs/repos".to_string(), "demo".to_string())
    );
    assert_eq!(
        split_clone_destination("demo").unwrap(),
        (".".to_string(), "demo".to_string())
    );
}

#[test]
fn clones_from_local_source_into_nested_destination() {
    let source = init_repo();
    let workspace = tempfile::tempdir().expect("tempdir");
    let destination = workspace.path().join("nested").join("cloned");
    std::fs::create_dir_all(destination.parent().unwrap()).expect("create parent");

    clone_repository(path_str(source.path()), path_str(&destination)).unwrap();

    assert!(destination.join(".git").exists());
    assert!(!destination.join("cloned").exists());
    assert!(is_git_repository(path_str(&destination)).unwrap());
}

#[test]
fn git_status_splits_untracked_unstaged_and_staged_changes() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\n").expect("write staged");
    run_git(repo.path(), &["add", "README.md"]);
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\nunstaged\n")
        .expect("write unstaged");
    std::fs::write(repo.path().join("new.txt"), "new\nfile\n").expect("write untracked");

    let status = git_status(path_str(repo.path())).unwrap();

    assert!(status.entries.iter().any(|entry| {
        entry.path == "README.md"
            && entry.area == GitChangeArea::Staged
            && entry.status == GitChangeStatus::Modified
            && entry.added.unwrap_or(0) >= 1
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "README.md"
            && entry.area == GitChangeArea::Unstaged
            && entry.status == GitChangeStatus::Modified
            && entry.added == Some(1)
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "new.txt"
            && entry.area == GitChangeArea::Untracked
            && entry.status == GitChangeStatus::Untracked
            && entry.added.is_none()
            && entry.removed == Some(0)
    }));
}

#[cfg(unix)]
#[test]
fn git_status_lists_unreadable_untracked_files_without_reading_content() {
    use std::os::unix::fs::PermissionsExt;

    let repo = init_repo();
    let unreadable = repo.path().join("unreadable.txt");
    std::fs::write(&unreadable, "unreadable\ncontent\n").expect("write unreadable file");
    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o000))
        .expect("make unreadable");

    let status = git_status(path_str(repo.path())).unwrap();

    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o644))
        .expect("restore permissions");
    let entry = status
        .entries
        .iter()
        .find(|entry| entry.path == "unreadable.txt")
        .expect("unreadable untracked entry");
    assert_eq!(entry.area, GitChangeArea::Untracked);
    assert!(entry.added.is_none());
    assert_eq!(entry.removed, Some(0));
}

#[test]
fn git_diff_loads_single_area_and_combined_results() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\n").expect("write staged");
    run_git(repo.path(), &["add", "README.md"]);
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\nunstaged\n")
        .expect("write unstaged");
    std::fs::write(repo.path().join("new.txt"), "new\n").expect("write untracked");

    let staged = git_diff(
        path_str(repo.path()),
        "README.md".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(staged.files.len(), 1);
    assert!(staged.files[0].patch.contains("+staged"));
    assert!(staged.files[0].added.unwrap_or(0) >= 1);

    let all = git_diff_all(path_str(repo.path()), None).unwrap();
    assert!(all
        .files
        .iter()
        .any(|file| file.path == "README.md" && file.area == GitChangeArea::Staged));
    assert!(all
        .files
        .iter()
        .any(|file| file.path == "README.md" && file.area == GitChangeArea::Unstaged));
    assert!(all
        .files
        .iter()
        .any(|file| file.path == "new.txt" && file.area == GitChangeArea::Untracked));
    let untracked = all
        .files
        .iter()
        .find(|file| file.path == "new.txt")
        .expect("untracked diff");
    assert_eq!(untracked.added, Some(1));
}

#[test]
fn git_status_uses_workspace_relative_paths_for_subdirectories() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&lib_dir).expect("create app lib dir");
    std::fs::write(lib_dir.join("foo.dart"), "void main() {}\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app"]);

    std::fs::write(
        lib_dir.join("foo.dart"),
        "void main() {\n  print('changed');\n}\n",
    )
    .expect("modify app file");
    std::fs::write(repo.path().join("README.md"), "root changed\n").expect("modify root file");

    let status = git_status(path_str(&app_dir)).unwrap();

    assert_eq!(status.entries.len(), 1);
    assert_eq!(status.entries[0].path, "lib/foo.dart");
    assert_eq!(status.entries[0].area, GitChangeArea::Unstaged);

    let diff = git_diff(
        path_str(&app_dir),
        "lib/foo.dart".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();
    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "lib/foo.dart");
    assert!(diff.files[0].patch.contains("changed"));
}

#[cfg(unix)]
#[test]
fn git_untracked_symlink_diff_does_not_read_target_contents() {
    use std::os::unix::fs::symlink;

    let repo = init_repo();
    let outside = tempfile::tempdir().expect("external tempdir");
    let target = outside.path().join("secret.txt");
    std::fs::write(&target, "SECRET MATERIAL\n").expect("write external target");
    symlink(&target, repo.path().join("secrets")).expect("create symlink");

    let diff = git_diff(
        path_str(repo.path()),
        "secrets".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();

    assert_eq!(diff.files.len(), 1);
    assert!(diff.files[0].patch.contains("new file mode 120000"));
    assert!(diff.files[0].patch.contains(&path_str(&target)));
    assert!(!diff.files[0].patch.contains("SECRET MATERIAL"));
}

#[test]
fn git_diff_preserves_staged_rename_pairs() {
    let repo = init_repo();
    std::fs::write(repo.path().join("old.txt"), "same\ncontent\n").expect("write old file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add old"]);
    run_git(repo.path(), &["mv", "old.txt", "new.txt"]);
    run_git(repo.path(), &["add", "-A"]);

    let status = git_status(path_str(repo.path())).unwrap();
    let rename = status
        .entries
        .iter()
        .find(|entry| entry.path == "new.txt")
        .expect("rename status entry");

    assert_eq!(rename.area, GitChangeArea::Staged);
    assert_eq!(rename.status, GitChangeStatus::Renamed);
    assert_eq!(rename.old_path.as_deref(), Some("old.txt"));

    let diff = git_diff(
        path_str(repo.path()),
        "new.txt".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();

    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].status, GitChangeStatus::Renamed);
    assert_eq!(diff.files[0].old_path.as_deref(), Some("old.txt"));
    assert!(diff.files[0].patch.contains("rename from old.txt"));
    assert!(diff.files[0].patch.contains("rename to new.txt"));
}

#[test]
fn git_diff_truncates_large_unicode_without_panicking() {
    let repo = init_repo();
    let total_added_lines = 120_000u32;
    let repeated = (0..total_added_lines)
        .map(|index| format!("á{index}\n"))
        .collect::<String>();
    std::fs::write(repo.path().join("README.md"), format!("hello\n{repeated}"))
        .expect("write large unicode diff");

    let single = git_diff(
        path_str(repo.path()),
        "README.md".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();

    assert_eq!(single.files.len(), 1);
    assert!(single.files[0].truncated);
    assert!(single.files[0].added.unwrap() < total_added_lines);
    assert!(single.files[0]
        .patch
        .is_char_boundary(single.files[0].patch.len()));

    let combined = git_diff_all(path_str(repo.path()), None).unwrap();
    assert!(combined.truncated);
    assert!(combined.files[0]
        .patch
        .is_char_boundary(combined.files[0].patch.len()));
}
