use super::*;

#[test]
fn git_diff_returns_no_untracked_file_after_staging() {
    let repo = init_repo();
    std::fs::write(repo.path().join("stale.txt"), "stale\n").expect("write untracked");

    let before = git_diff(
        path_str(repo.path()),
        "stale.txt".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert_eq!(before.files.len(), 1);

    run_git(repo.path(), &["add", "stale.txt"]);

    let after = git_diff(
        path_str(repo.path()),
        "stale.txt".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert!(after.files.is_empty());
}

#[test]
fn git_diff_returns_no_untracked_file_after_commit() {
    let repo = init_repo();
    std::fs::write(repo.path().join("committed.txt"), "committed\n").expect("write untracked");

    let before = git_diff(
        path_str(repo.path()),
        "committed.txt".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert_eq!(before.files.len(), 1);

    run_git(repo.path(), &["add", "committed.txt"]);
    run_git(repo.path(), &["commit", "-m", "commit stale file"]);

    let after = git_diff(
        path_str(repo.path()),
        "committed.txt".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert!(after.files.is_empty());
}

#[test]
fn git_diff_keeps_untracked_replacement_after_staged_delete() {
    let repo = init_repo();
    run_git(repo.path(), &["rm", "README.md"]);
    std::fs::write(repo.path().join("README.md"), "replacement\n").expect("write replacement");

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "README.md"
            && entry.area == GitChangeArea::Staged
            && entry.status == GitChangeStatus::Deleted
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "README.md"
            && entry.area == GitChangeArea::Untracked
            && entry.status == GitChangeStatus::Untracked
    }));

    let untracked = git_diff(
        path_str(repo.path()),
        "README.md".to_string(),
        GitChangeArea::Untracked,
    )
    .unwrap();
    assert_eq!(untracked.files.len(), 1);
    assert!(diff_text(&untracked.files[0]).contains("+replacement"));

    let all = git_diff_all(path_str(repo.path()), None).unwrap();
    assert!(all.files.iter().any(|file| {
        file.path == "README.md"
            && file.area == GitChangeArea::Staged
            && file.status == GitChangeStatus::Deleted
    }));
    assert!(all.files.iter().any(|file| {
        file.path == "README.md"
            && file.area == GitChangeArea::Untracked
            && diff_text(file).contains("+replacement")
    }));
}

#[cfg(unix)]
#[test]
fn git_diff_all_keeps_readable_files_when_untracked_file_is_unreadable() {
    use std::os::unix::fs::PermissionsExt;

    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "hello\nreadable\n").expect("modify tracked");
    let unreadable = repo.path().join("unreadable.txt");
    std::fs::write(&unreadable, "unreadable\ncontent\n").expect("write unreadable file");
    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o000))
        .expect("make unreadable");

    let all = git_diff_all(path_str(repo.path()), None);

    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o644))
        .expect("restore permissions");
    let all = all.unwrap();
    assert!(all
        .files
        .iter()
        .any(|file| file.path == "README.md" && file.area == GitChangeArea::Unstaged));
    let unreadable = all
        .files
        .iter()
        .find(|file| file.path == "unreadable.txt")
        .expect("unreadable untracked placeholder");
    assert_eq!(unreadable.area, GitChangeArea::Untracked);
    assert_eq!(unreadable.status, GitChangeStatus::Untracked);
    assert!(unreadable.lines.is_empty());
    assert_eq!(unreadable.added, None);
    assert_eq!(unreadable.removed, Some(0));
}

#[cfg(unix)]
#[test]
fn git_diff_untracked_unreadable_file_returns_placeholder() {
    use std::os::unix::fs::PermissionsExt;

    let repo = init_repo();
    let unreadable = repo.path().join("unreadable.txt");
    std::fs::write(&unreadable, "unreadable\ncontent\n").expect("write unreadable file");
    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o000))
        .expect("make unreadable");

    let status = git_status(path_str(repo.path())).unwrap();
    let diff = git_diff(
        path_str(repo.path()),
        "unreadable.txt".to_string(),
        GitChangeArea::Untracked,
    );

    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o644))
        .expect("restore permissions");
    assert!(status.entries.iter().any(|entry| {
        entry.path == "unreadable.txt"
            && entry.area == GitChangeArea::Untracked
            && entry.status == GitChangeStatus::Untracked
    }));
    let diff = diff.unwrap();
    assert_eq!(diff.files.len(), 1);
    let file = &diff.files[0];
    assert_eq!(file.path, "unreadable.txt");
    assert_eq!(file.area, GitChangeArea::Untracked);
    assert_eq!(file.status, GitChangeStatus::Untracked);
    assert!(file.lines.is_empty());
    assert_eq!(file.added, None);
    assert_eq!(file.removed, Some(0));
}

#[cfg(unix)]
#[test]
fn git_diff_all_for_file_ignores_unrelated_changes() {
    use std::os::unix::fs::PermissionsExt;

    let repo = init_repo();
    std::fs::write(repo.path().join("target.txt"), "base\n").expect("write target");
    std::fs::write(repo.path().join("unrelated.txt"), "unrelated\n").expect("write unrelated");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add target and unrelated"]);
    std::fs::write(repo.path().join("target.txt"), "base\nstaged\n").expect("stage target");
    run_git(repo.path(), &["add", "target.txt"]);
    std::fs::write(repo.path().join("target.txt"), "base\nstaged\nunstaged\n")
        .expect("modify target");
    std::fs::write(repo.path().join("unrelated.txt"), "unrelated changed\n")
        .expect("modify unrelated");
    let unreadable = repo.path().join("unreadable.txt");
    std::fs::write(&unreadable, "unreadable\n").expect("write unreadable");
    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o000))
        .expect("make unreadable");

    let result = git_diff_all(path_str(repo.path()), Some("target.txt".to_string()));

    std::fs::set_permissions(&unreadable, std::fs::Permissions::from_mode(0o644))
        .expect("restore permissions");
    let result = result.unwrap();
    assert!(result.files.iter().all(|file| file.path == "target.txt"));
    assert!(result
        .files
        .iter()
        .any(|file| file.area == GitChangeArea::Staged));
    assert!(result
        .files
        .iter()
        .any(|file| file.area == GitChangeArea::Unstaged));
    assert!(!result.files.iter().any(|file| file.path == "unrelated.txt"));
    assert!(!result
        .files
        .iter()
        .any(|file| file.path == "unreadable.txt"));
}

#[test]
fn git_status_lists_conflicted_files_as_unstaged_changes() {
    let repo = init_repo();
    run_git(repo.path(), &["checkout", "-b", "feature"]);
    std::fs::write(repo.path().join("README.md"), "feature\n").expect("write feature");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "feature change"]);
    run_git(repo.path(), &["checkout", "main"]);
    std::fs::write(repo.path().join("README.md"), "main\n").expect("write main");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "main change"]);

    let merge = std::process::Command::new("git")
        .args(["merge", "feature"])
        .current_dir(repo.path())
        .status()
        .expect("git merge runs");
    assert!(!merge.success());

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "README.md"
            && entry.area == GitChangeArea::Unstaged
            && entry.status == GitChangeStatus::Modified
    }));
}

#[test]
fn git_diff_keeps_staged_rename_out_visible_from_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib = app_dir.join("lib");
    let other_dir = repo.path().join("packages").join("other");
    std::fs::create_dir_all(&app_lib).expect("create app lib");
    std::fs::create_dir_all(&other_dir).expect("create other dir");
    std::fs::write(app_lib.join("foo.dart"), "void main() {}\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app file"]);
    run_git(
        repo.path(),
        &["mv", "packages/app/lib/foo.dart", "packages/other/foo.dart"],
    );

    let status = git_status(path_str(&app_dir)).unwrap();
    let rename = status
        .entries
        .iter()
        .find(|entry| entry.path == "lib/foo.dart" && entry.area == GitChangeArea::Staged)
        .expect("rename out status entry");
    assert_eq!(rename.status, GitChangeStatus::Renamed);
    assert_eq!(rename.old_path.as_deref(), Some("lib/foo.dart"));

    let all = git_diff_all(path_str(&app_dir), None).unwrap();
    assert!(all.files.iter().any(|file| {
        file.path == "lib/foo.dart"
            && file.area == GitChangeArea::Staged
            && file.status == GitChangeStatus::Renamed
    }));

    let diff = git_diff(
        path_str(&app_dir),
        "lib/foo.dart".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "lib/foo.dart");
    assert_eq!(diff.files[0].status, GitChangeStatus::Renamed);
    assert!(diff_text(&diff.files[0]).contains("rename from packages/app/lib/foo.dart"));
    assert!(diff_text(&diff.files[0]).contains("rename to packages/other/foo.dart"));
}

#[test]
fn git_diff_does_not_select_copy_delta_by_source_path() {
    let repo = init_repo();
    let source = repo
        .path()
        .join("packages")
        .join("app")
        .join("lib")
        .join("foo.dart");
    let copy = repo.path().join("packages").join("aaa").join("foo.dart");
    std::fs::create_dir_all(source.parent().unwrap()).expect("create source dir");
    std::fs::create_dir_all(copy.parent().unwrap()).expect("create copy dir");
    std::fs::write(&source, "base\n").expect("write source");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add source"]);

    std::fs::copy(&source, &copy).expect("copy source");
    std::fs::write(&source, "base\nsource change\n").expect("modify source");
    run_git(
        repo.path(),
        &["add", "packages/app/lib/foo.dart", "packages/aaa/foo.dart"],
    );

    let copy_diff = git_diff(
        path_str(repo.path()),
        "packages/aaa/foo.dart".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(copy_diff.files.len(), 1);
    assert_eq!(copy_diff.files[0].path, "packages/aaa/foo.dart");
    assert_eq!(copy_diff.files[0].status, GitChangeStatus::Copied);
    assert_eq!(copy_diff.files[0].added, Some(0));
    assert_eq!(copy_diff.files[0].removed, Some(0));
    assert!(!diff_text(&copy_diff.files[0]).contains("+source change"));

    let diff = git_diff(
        path_str(repo.path()),
        "packages/app/lib/foo.dart".to_string(),
        GitChangeArea::Staged,
    )
    .unwrap();
    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "packages/app/lib/foo.dart");
    assert_eq!(diff.files[0].status, GitChangeStatus::Modified);
    assert!(diff_text(&diff.files[0]).contains("+source change"));
    assert!(!diff_text(&diff.files[0]).contains("packages/aaa/foo.dart"));

    let all = git_diff_all(
        path_str(repo.path()),
        Some("packages/app/lib/foo.dart".to_string()),
    )
    .unwrap();
    assert_eq!(all.files.len(), 1);
    assert_eq!(all.files[0].path, "packages/app/lib/foo.dart");
    assert_eq!(all.files[0].status, GitChangeStatus::Modified);
    assert!(diff_text(&all.files[0]).contains("+source change"));
    assert!(!diff_text(&all.files[0]).contains("packages/aaa/foo.dart"));
}

#[test]
fn git_diff_treats_star_pathspec_characters_as_literals() {
    let repo = init_repo();
    std::fs::write(repo.path().join("*.txt"), "literal star\n").expect("write star file");
    std::fs::write(repo.path().join("other.txt"), "other file\n").expect("write other file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add pathspec files"]);

    std::fs::write(repo.path().join("*.txt"), "literal star changed\n").expect("modify star");
    std::fs::write(repo.path().join("other.txt"), "other changed\n").expect("modify other");

    let diff = git_diff(
        path_str(repo.path()),
        "*.txt".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();

    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "*.txt");
    assert!(diff_text(&diff.files[0]).contains("literal star changed"));
    assert!(!diff_text(&diff.files[0]).contains("other changed"));
}

#[test]
fn git_diff_treats_bracket_pathspec_characters_as_literals() {
    let repo = init_repo();
    std::fs::write(repo.path().join("file[1].txt"), "literal bracket\n")
        .expect("write bracket file");
    std::fs::write(repo.path().join("file1.txt"), "matched by glob\n").expect("write glob file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add bracket files"]);

    std::fs::write(repo.path().join("file[1].txt"), "literal bracket changed\n")
        .expect("modify bracket");
    std::fs::write(repo.path().join("file1.txt"), "glob changed\n").expect("modify glob");

    let diff = git_diff(
        path_str(repo.path()),
        "file[1].txt".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();

    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "file[1].txt");
    assert!(diff_text(&diff.files[0]).contains("literal bracket changed"));
    assert!(!diff_text(&diff.files[0]).contains("glob changed"));
}
