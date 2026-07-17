use super::*;
use git2::{Oid, Repository};
use std::path::Path;
use std::process::Command;

#[path = "git_diff_edge_tests.rs"]
mod git_diff_edge_tests;
#[path = "git_explorer_status_tests.rs"]
mod git_explorer_status_tests;
#[path = "git_submodule_tests.rs"]
mod git_submodule_tests;

fn run_git(dir: &Path, args: &[&str]) {
    let status = git_command(dir, args).status().expect("git command runs");
    assert!(status.success(), "git {:?} failed", args);
}

fn run_git_expect_failure(dir: &Path, args: &[&str]) {
    let status = git_command(dir, args).status().expect("git command runs");
    assert!(!status.success(), "git {:?} succeeded unexpectedly", args);
}

fn git_command(dir: &Path, args: &[&str]) -> Command {
    let mut command = Command::new("git");
    command
        .args(args)
        .current_dir(dir)
        .env("GIT_AUTHOR_NAME", "Test")
        .env("GIT_AUTHOR_EMAIL", "test@example.com")
        .env("GIT_COMMITTER_NAME", "Test")
        .env("GIT_COMMITTER_EMAIL", "test@example.com");
    command
}

fn init_repo() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    run_git(dir.path(), &["init", "-b", "main"]);
    configure_git_identity(dir.path());
    std::fs::write(dir.path().join("README.md"), "hello").expect("write");
    run_git(dir.path(), &["add", "."]);
    run_git(dir.path(), &["commit", "-m", "initial"]);
    dir
}

fn configure_git_identity(dir: &Path) {
    run_git(dir, &["config", "user.name", "Test"]);
    run_git(dir, &["config", "user.email", "test@example.com"]);
}

fn path_str(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

fn canonical(path: &str) -> String {
    let target = Path::new(path);
    std::fs::canonicalize(target)
        .unwrap_or_else(|_| target.to_path_buf())
        .to_string_lossy()
        .trim_end_matches('/')
        .to_string()
}

fn branch_oid(path: &Path, branch: &str) -> Oid {
    let repo = Repository::open(path).expect("open repo");
    let branch = repo
        .find_branch(branch, git2::BranchType::Local)
        .expect("find branch");
    branch.get().target().expect("branch target")
}

fn commit_file(repo_path: &Path, file_name: &str, content: &str, message: &str) {
    std::fs::write(repo_path.join(file_name), content).expect("write file");
    run_git(repo_path, &["add", file_name]);
    run_git(repo_path, &["commit", "-m", message]);
}

fn head_commit_message(path: &Path) -> String {
    let repo = Repository::open(path).expect("open repo");
    let commit = repo
        .head()
        .expect("head")
        .peel_to_commit()
        .expect("head commit");
    commit.message().expect("message").to_string()
}

fn head_author_name(path: &Path) -> String {
    let repo = Repository::open(path).expect("open repo");
    let commit = repo
        .head()
        .expect("head")
        .peel_to_commit()
        .expect("head commit");
    let author = commit.author().name().expect("author name").to_string();
    author
}

fn head_committer_name(path: &Path) -> String {
    let repo = Repository::open(path).expect("open repo");
    let commit = repo
        .head()
        .expect("head")
        .peel_to_commit()
        .expect("head commit");
    let committer = commit
        .committer()
        .name()
        .expect("committer name")
        .to_string();
    committer
}

fn diff_text(file: &GitDiffFile) -> String {
    file.lines
        .iter()
        .map(|line| line.text.as_str())
        .collect::<Vec<_>>()
        .join("\n")
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
fn repository_state_includes_head_message() {
    let repo = init_repo();

    let state = git_repository_state(path_str(repo.path())).unwrap();

    assert_eq!(state.head_message.as_deref(), Some("initial"));
}

#[test]
fn git_history_includes_upstream_only_commits() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);

    commit_file(
        source.path(),
        "remote-only.txt",
        "remote\n",
        "remote only change",
    );
    run_git(source.path(), &["push"]);
    run_git(&clone_path, &["fetch", "origin"]);

    let history = git_history(path_str(&clone_path), Some(50), None).unwrap();

    assert!(history.has_incoming_changes);
    assert_eq!(history.remote_ref.unwrap().name, "origin/main");
    assert!(history
        .items
        .iter()
        .any(|item| item.subject == "remote only change"));
}

#[test]
fn git_history_refs_peel_annotated_tags_to_commits() {
    let repo = init_repo();
    run_git(repo.path(), &["tag", "-a", "v1.0.0", "-m", "release v1"]);

    let history = git_history(path_str(repo.path()), Some(50), None).unwrap();

    let initial = history
        .items
        .iter()
        .find(|item| item.subject == "initial")
        .expect("initial commit in history");
    assert!(initial.references.iter().any(|reference| {
        reference.name == "v1.0.0" && reference.category == Some(GitHistoryRefCategory::Tags)
    }));
}

#[test]
fn git_history_filters_commits_for_scoped_workspace_path() {
    let repo = init_repo();
    std::fs::create_dir_all(repo.path().join("packages/app/lib")).expect("create app dir");
    std::fs::create_dir_all(repo.path().join("packages/other/lib")).expect("create other dir");
    commit_file(
        repo.path(),
        "packages/app/lib/main.dart",
        "app\n",
        "app change",
    );
    commit_file(repo.path(), "README.md", "hello\nroot\n", "root change");
    commit_file(
        repo.path(),
        "packages/other/lib/main.dart",
        "other\n",
        "other change",
    );
    commit_file(
        repo.path(),
        "packages/app/lib/main.dart",
        "app\napp 2\n",
        "app change 2",
    );

    let history = git_history(path_str(&repo.path().join("packages/app")), Some(50), None).unwrap();
    let subjects = history
        .items
        .iter()
        .map(|item| item.subject.as_str())
        .collect::<Vec<_>>();

    assert!(subjects.contains(&"app change"));
    assert!(subjects.contains(&"app change 2"));
    assert!(!subjects.contains(&"other change"));
    assert!(!subjects.contains(&"root change"));
    assert!(!subjects.contains(&"initial"));
    let older = history
        .items
        .iter()
        .find(|item| item.subject == "app change")
        .expect("older scoped commit");
    let newer = history
        .items
        .iter()
        .find(|item| item.subject == "app change 2")
        .expect("newer scoped commit");
    assert_eq!(newer.parent_ids, vec![older.id.clone()]);
}

#[test]
fn git_history_suppresses_divergence_markers_outside_scoped_workspace_path() {
    let source = init_repo();
    std::fs::create_dir_all(source.path().join("packages/app/lib")).expect("create app dir");
    std::fs::create_dir_all(source.path().join("packages/other/lib")).expect("create other dir");
    commit_file(
        source.path(),
        "packages/app/lib/main.dart",
        "app\n",
        "app change",
    );
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);

    commit_file(
        source.path(),
        "packages/other/remote.dart",
        "remote\n",
        "remote other change",
    );
    run_git(source.path(), &["push"]);
    run_git(&clone_path, &["fetch", "origin"]);
    std::fs::create_dir_all(clone_path.join("packages/other")).expect("create clone other dir");
    commit_file(
        &clone_path,
        "packages/other/local.dart",
        "local\n",
        "local other change",
    );

    let history = git_history(path_str(&clone_path.join("packages/app")), Some(50), None).unwrap();
    let subjects = history
        .items
        .iter()
        .map(|item| item.subject.as_str())
        .collect::<Vec<_>>();

    assert!(!history.has_incoming_changes);
    assert!(!history.has_outgoing_changes);
    assert!(subjects.contains(&"app change"));
    assert!(!subjects.contains(&"remote other change"));
    assert!(!subjects.contains(&"local other change"));
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
        false,
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
fn creates_worktree_from_existing_branch() {
    let repo = init_repo();
    run_git(repo.path(), &["branch", "feature/existing"]);
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("existing"));

    create_worktree(
        path_str(repo.path()),
        "feature/existing".to_string(),
        worktree_path.clone(),
        "main".to_string(),
        true,
    )
    .unwrap();

    assert_eq!(current_branch(worktree_path).unwrap(), "feature/existing");
}

#[test]
fn rejects_missing_existing_branch_for_reused_worktree() {
    let repo = init_repo();
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("missing"));

    let error = create_worktree(
        path_str(repo.path()),
        "feature/missing".to_string(),
        worktree_path,
        "main".to_string(),
        true,
    )
    .unwrap_err();

    assert!(matches!(error.kind, GitErrorKind::BranchNotFound));
}

#[test]
fn removes_worktree_metadata_when_checkout_directory_is_missing() {
    let repo = init_repo();
    let worktree_base = tempfile::tempdir().expect("tempdir");
    let worktree_path = path_str(&worktree_base.path().join("feature-missing-dir"));

    create_worktree(
        path_str(repo.path()),
        "feature/missing-dir".to_string(),
        worktree_path.clone(),
        "main".to_string(),
        false,
    )
    .unwrap();
    std::fs::remove_dir_all(&worktree_path).expect("remove checkout dir");

    remove_worktree(path_str(repo.path()), worktree_path, true).unwrap();

    let worktrees = list_worktrees(path_str(repo.path())).unwrap();
    assert!(!worktrees
        .iter()
        .any(|entry| entry.branch == "feature/missing-dir"));
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
        false,
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
fn status_preserves_punctuation_and_control_character_paths() {
    let repo = init_repo();
    let comma_path = repo.path().join("comma,name.txt");
    let newline_path = repo.path().join("line\nbreak.txt");
    std::fs::write(&comma_path, "comma\n").expect("write comma path");
    std::fs::write(&newline_path, "newline\n").expect("write newline path");

    let status = git_status(path_str(repo.path())).unwrap();

    assert!(status.entries.iter().any(|entry| {
        entry.path == "comma,name.txt"
            && entry.area == GitChangeArea::Untracked
            && entry.status == GitChangeStatus::Untracked
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "line\nbreak.txt"
            && entry.area == GitChangeArea::Untracked
            && entry.status == GitChangeStatus::Untracked
    }));
}

#[test]
fn diff_accepts_backslash_separators_from_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&lib_dir).expect("create lib dir");
    std::fs::write(lib_dir.join("foo.dart"), "void main() {}\n").expect("write file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app file"]);
    std::fs::write(lib_dir.join("foo.dart"), "void main() {\n  print(1);\n}\n")
        .expect("modify file");

    let diff = git_diff(
        path_str(&app_dir),
        "lib\\foo.dart".to_string(),
        GitChangeArea::Unstaged,
    )
    .unwrap();

    assert_eq!(diff.files.len(), 1);
    assert_eq!(diff.files[0].path, "lib/foo.dart");
    assert!(diff_text(&diff.files[0]).contains("+  print(1);"));
}

#[test]
fn concurrent_status_refreshes_do_not_share_mutable_probe_state() {
    let repo = init_repo();
    std::fs::write(repo.path().join("changed.txt"), "changed\n").expect("write changed");
    let repo_path = path_str(repo.path());

    let handles = (0..8)
        .map(|_| {
            let path = repo_path.clone();
            std::thread::spawn(move || git_status(path).unwrap())
        })
        .collect::<Vec<_>>();

    for handle in handles {
        let status = handle.join().expect("status thread joins");
        assert!(status.entries.iter().any(|entry| {
            entry.path == "changed.txt" && entry.status == GitChangeStatus::Untracked
        }));
    }
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
        false,
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
fn refresh_source_branch_fetches_remote_tracking_source() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);

    commit_file(source.path(), "remote.txt", "remote\n", "remote change");
    run_git(source.path(), &["push"]);

    refresh_source_branch(path_str(&clone_path), "origin/main".to_string()).unwrap();

    let worktree_base = tempfile::tempdir().expect("worktree base");
    let worktree_path = worktree_base.path().join("from-remote");
    create_worktree(
        path_str(&clone_path),
        "feature/from-remote".to_string(),
        path_str(&worktree_path),
        "origin/main".to_string(),
        false,
    )
    .unwrap();
    assert!(worktree_path.join("remote.txt").exists());
}

#[test]
fn refresh_source_branch_pulls_current_local_source() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);

    commit_file(source.path(), "pulled.txt", "pulled\n", "remote change");
    run_git(source.path(), &["push"]);

    refresh_source_branch(path_str(&clone_path), "main".to_string()).unwrap();

    assert!(clone_path.join("pulled.txt").exists());
}

#[test]
fn refresh_source_branch_rejects_diverged_current_local_source() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);
    run_git(&clone_path, &["config", "pull.rebase", "false"]);
    run_git(&clone_path, &["config", "pull.ff", "false"]);

    commit_file(
        &clone_path,
        "local-main.txt",
        "local\n",
        "local main change",
    );
    let local_oid = branch_oid(&clone_path, "main");

    commit_file(
        source.path(),
        "remote-main.txt",
        "remote\n",
        "remote main change",
    );
    run_git(source.path(), &["push"]);

    let error = refresh_source_branch(path_str(&clone_path), "main".to_string()).unwrap_err();

    assert!(matches!(error.kind, GitErrorKind::GitCli));
    assert_eq!(branch_oid(&clone_path, "main"), local_oid);
    assert_eq!(current_branch(path_str(&clone_path)).unwrap(), "main");
}

#[test]
fn refresh_source_branch_fast_forwards_non_current_local_source() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);
    run_git(source.path(), &["checkout", "-b", "feature"]);
    commit_file(source.path(), "feature.txt", "v1\n", "feature v1");
    run_git(source.path(), &["push", "-u", "origin", "feature"]);
    run_git(source.path(), &["checkout", "main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);
    run_git(
        &clone_path,
        &["checkout", "-b", "feature", "origin/feature"],
    );
    run_git(&clone_path, &["checkout", "main"]);

    run_git(source.path(), &["checkout", "feature"]);
    commit_file(source.path(), "feature.txt", "v2\n", "feature v2");
    run_git(source.path(), &["push"]);

    refresh_source_branch(path_str(&clone_path), "feature".to_string()).unwrap();

    assert_eq!(current_branch(path_str(&clone_path)).unwrap(), "main");
    let worktree_base = tempfile::tempdir().expect("worktree base");
    let worktree_path = worktree_base.path().join("from-local");
    create_worktree(
        path_str(&clone_path),
        "from-local-feature".to_string(),
        path_str(&worktree_path),
        "feature".to_string(),
        false,
    )
    .unwrap();
    assert_eq!(
        std::fs::read_to_string(worktree_path.join("feature.txt")).unwrap(),
        "v2\n"
    );
}

#[test]
fn refresh_source_branch_rejects_diverged_non_current_local_source() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);
    run_git(source.path(), &["checkout", "-b", "feature"]);
    commit_file(source.path(), "feature.txt", "v1\n", "feature v1");
    run_git(source.path(), &["push", "-u", "origin", "feature"]);
    run_git(source.path(), &["checkout", "main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);
    run_git(
        &clone_path,
        &["checkout", "-b", "feature", "origin/feature"],
    );
    commit_file(
        &clone_path,
        "local-feature.txt",
        "local\n",
        "local feature change",
    );
    let local_oid = branch_oid(&clone_path, "feature");
    run_git(&clone_path, &["checkout", "main"]);

    run_git(source.path(), &["checkout", "feature"]);
    commit_file(
        source.path(),
        "remote-feature.txt",
        "remote\n",
        "remote feature change",
    );
    run_git(source.path(), &["push"]);

    let error = refresh_source_branch(path_str(&clone_path), "feature".to_string()).unwrap_err();

    assert!(matches!(error.kind, GitErrorKind::Conflict));
    assert_eq!(branch_oid(&clone_path, "feature"), local_oid);
    assert_eq!(current_branch(path_str(&clone_path)).unwrap(), "main");
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
        false,
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
        false,
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
        false,
    )
    .unwrap();
    create_worktree(
        path_str(repo.path()),
        "feature-b".to_string(),
        path_b.clone(),
        "main".to_string(),
        false,
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
    assert_eq!(
        status
            .groups
            .iter()
            .map(|group| group.area)
            .collect::<Vec<_>>(),
        vec![
            GitChangeArea::Staged,
            GitChangeArea::Unstaged,
            GitChangeArea::Untracked,
        ]
    );
}

#[test]
fn git_stage_unstage_commit_and_state_follow_index() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "hello\nupdated\n").expect("modify readme");

    git_stage(path_str(repo.path()), Some("README.md".to_string())).unwrap();
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "README.md" && entry.area == GitChangeArea::Staged));

    git_unstage(path_str(repo.path()), Some("README.md".to_string())).unwrap();
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "README.md" && entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "README.md" && entry.area == GitChangeArea::Staged));

    git_stage(path_str(repo.path()), Some("README.md".to_string())).unwrap();
    let oid = git_commit(path_str(repo.path()), "update readme".to_string()).unwrap();
    assert!(!oid.is_empty());
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.is_empty());

    let state = git_repository_state(path_str(repo.path())).unwrap();
    assert_eq!(state.branch, "main");
    assert!(!state.has_conflicts);
}

#[test]
fn git_stage_treats_selected_pathspec_characters_as_literals() {
    let repo = init_repo();
    std::fs::write(repo.path().join("*.txt"), "literal star\n").expect("write star file");
    std::fs::write(repo.path().join("other.txt"), "other\n").expect("write other file");
    run_git(repo.path(), &["add", "*.txt", "other.txt"]);
    run_git(repo.path(), &["commit", "-m", "add pathspec files"]);

    std::fs::write(repo.path().join("*.txt"), "literal star changed\n").expect("modify star file");
    std::fs::write(repo.path().join("other.txt"), "other changed\n").expect("modify other file");

    git_stage(path_str(repo.path()), Some("*.txt".to_string())).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "*.txt" && entry.area == GitChangeArea::Staged));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "other.txt" && entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "other.txt" && entry.area == GitChangeArea::Staged));
}

#[test]
fn git_unstage_treats_selected_pathspec_characters_as_literals() {
    let repo = init_repo();
    std::fs::write(repo.path().join("file[1].txt"), "literal bracket\n")
        .expect("write bracket file");
    std::fs::write(repo.path().join("file1.txt"), "glob match\n").expect("write match file");
    run_git(repo.path(), &["add", "file[1].txt", "file1.txt"]);
    run_git(repo.path(), &["commit", "-m", "add bracket files"]);

    std::fs::write(repo.path().join("file[1].txt"), "literal bracket changed\n")
        .expect("modify bracket file");
    std::fs::write(repo.path().join("file1.txt"), "glob match changed\n")
        .expect("modify match file");
    run_git(repo.path(), &["add", "file[1].txt", "file1.txt"]);

    git_unstage(path_str(repo.path()), Some("file[1].txt".to_string())).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "file[1].txt" && entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "file[1].txt" && entry.area == GitChangeArea::Staged));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "file1.txt" && entry.area == GitChangeArea::Staged));
}

#[test]
fn git_stage_all_treats_workspace_pathspec_characters_as_literals() {
    let repo = init_repo();
    let bracket_dir = repo.path().join("packages").join("app[1]");
    let glob_match_dir = repo.path().join("packages").join("app1");
    std::fs::create_dir_all(&bracket_dir).expect("create bracket dir");
    std::fs::create_dir_all(&glob_match_dir).expect("create glob match dir");
    std::fs::write(bracket_dir.join("foo.dart"), "bracket\n").expect("write bracket file");
    std::fs::write(glob_match_dir.join("foo.dart"), "glob\n").expect("write glob file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app dirs"]);

    std::fs::write(bracket_dir.join("foo.dart"), "bracket changed\n").expect("modify bracket file");
    std::fs::write(glob_match_dir.join("foo.dart"), "glob changed\n").expect("modify glob file");

    git_stage(path_str(&bracket_dir), None).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app[1]/foo.dart" && entry.area == GitChangeArea::Staged
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app1/foo.dart" && entry.area == GitChangeArea::Unstaged
    }));
    assert!(!status.entries.iter().any(|entry| {
        entry.path == "packages/app1/foo.dart" && entry.area == GitChangeArea::Staged
    }));
}

#[test]
fn git_stage_area_limits_to_selected_area_and_folder() {
    let repo = init_repo();
    std::fs::create_dir_all(repo.path().join("lib")).expect("create lib");
    std::fs::create_dir_all(repo.path().join("test")).expect("create test");
    std::fs::write(repo.path().join("lib/tracked.dart"), "lib\n").expect("write lib tracked");
    std::fs::write(repo.path().join("test/tracked.dart"), "test\n").expect("write test tracked");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add tracked files"]);

    std::fs::write(repo.path().join("lib/tracked.dart"), "lib changed\n")
        .expect("modify lib tracked");
    std::fs::write(repo.path().join("lib/new.dart"), "new\n").expect("write lib new");
    std::fs::write(repo.path().join("test/tracked.dart"), "test changed\n")
        .expect("modify test tracked");

    git_stage_area(
        path_str(repo.path()),
        GitChangeArea::Unstaged,
        Some("lib".to_string()),
    )
    .unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| { entry.path == "lib/tracked.dart" && entry.area == GitChangeArea::Staged }));
    assert!(status
        .entries
        .iter()
        .any(|entry| { entry.path == "lib/new.dart" && entry.area == GitChangeArea::Untracked }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "test/tracked.dart" && entry.area == GitChangeArea::Unstaged
    }));
}

#[test]
fn git_unstage_all_treats_workspace_pathspec_characters_as_literals() {
    let repo = init_repo();
    let bracket_dir = repo.path().join("packages").join("app[1]");
    let glob_match_dir = repo.path().join("packages").join("app1");
    std::fs::create_dir_all(&bracket_dir).expect("create bracket dir");
    std::fs::create_dir_all(&glob_match_dir).expect("create glob match dir");
    std::fs::write(bracket_dir.join("foo.dart"), "bracket\n").expect("write bracket file");
    std::fs::write(glob_match_dir.join("foo.dart"), "glob\n").expect("write glob file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app dirs"]);

    std::fs::write(bracket_dir.join("foo.dart"), "bracket changed\n").expect("modify bracket file");
    std::fs::write(glob_match_dir.join("foo.dart"), "glob changed\n").expect("modify glob file");
    run_git(
        repo.path(),
        &["add", "packages/app[1]/foo.dart", "packages/app1/foo.dart"],
    );

    git_unstage(path_str(&bracket_dir), None).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app[1]/foo.dart" && entry.area == GitChangeArea::Unstaged
    }));
    assert!(!status.entries.iter().any(|entry| {
        entry.path == "packages/app[1]/foo.dart" && entry.area == GitChangeArea::Staged
    }));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app1/foo.dart" && entry.area == GitChangeArea::Staged
    }));
}

#[test]
fn git_discard_treats_selected_pathspec_characters_as_literals() {
    let repo = init_repo();
    std::fs::write(repo.path().join("file[1].txt"), "literal bracket\n")
        .expect("write bracket file");
    std::fs::write(repo.path().join("file1.txt"), "glob match\n").expect("write match file");
    run_git(repo.path(), &["add", "file[1].txt", "file1.txt"]);
    run_git(repo.path(), &["commit", "-m", "add bracket files"]);

    std::fs::write(repo.path().join("file[1].txt"), "literal bracket changed\n")
        .expect("modify bracket file");
    std::fs::write(repo.path().join("file1.txt"), "glob match changed\n")
        .expect("modify match file");

    git_discard(path_str(repo.path()), Some("file[1].txt".to_string())).unwrap();

    assert_eq!(
        std::fs::read_to_string(repo.path().join("file[1].txt")).unwrap(),
        "literal bracket\n"
    );
    assert_eq!(
        std::fs::read_to_string(repo.path().join("file1.txt")).unwrap(),
        "glob match changed\n"
    );
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "file[1].txt"));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "file1.txt" && entry.area == GitChangeArea::Unstaged));
}

#[test]
fn git_discard_restores_tracked_and_deletes_untracked() {
    let repo = init_repo();
    let tracked = repo.path().join("README.md");
    let untracked = repo.path().join("scratch.txt");
    std::fs::write(&tracked, "changed\n").expect("modify readme");
    std::fs::write(&untracked, "scratch\n").expect("write scratch");

    git_discard(path_str(repo.path()), None).unwrap();

    assert_eq!(std::fs::read_to_string(&tracked).unwrap(), "hello");
    assert!(!untracked.exists());
    assert!(git_status(path_str(repo.path()))
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn git_discard_all_removes_unstaged_rename_destination() {
    let repo = init_repo();
    let old_path = repo.path().join("old.txt");
    let new_path = repo.path().join("new.txt");
    std::fs::write(&old_path, "old\n").expect("write old file");
    run_git(repo.path(), &["add", "old.txt"]);
    run_git(repo.path(), &["commit", "-m", "add old file"]);

    std::fs::rename(&old_path, &new_path).expect("rename tracked file");

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "new.txt"
            && entry.old_path.as_deref() == Some("old.txt")
            && entry.area == GitChangeArea::Unstaged
            && entry.status == GitChangeStatus::Renamed
    }));

    git_discard(path_str(repo.path()), None).unwrap();

    assert_eq!(std::fs::read_to_string(&old_path).unwrap(), "old\n");
    assert!(!new_path.exists());
    assert!(git_status(path_str(repo.path()))
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn git_discard_all_keeps_rename_out_destination_outside_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    let other_dir = repo.path().join("packages").join("other");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::create_dir_all(&other_dir).expect("create other dir");
    let old_path = app_lib_dir.join("foo.dart");
    let new_path = other_dir.join("foo.dart");
    std::fs::write(&old_path, "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app file"]);

    std::fs::rename(&old_path, &new_path).expect("rename file out of workspace");

    let status = git_status(path_str(&app_dir)).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "lib/foo.dart"
            && entry.old_path.as_deref() == Some("lib/foo.dart")
            && entry.area == GitChangeArea::Unstaged
            && entry.status == GitChangeStatus::Renamed
    }));

    git_discard(path_str(&app_dir), None).unwrap();

    assert_eq!(std::fs::read_to_string(&old_path).unwrap(), "app\n");
    assert_eq!(std::fs::read_to_string(&new_path).unwrap(), "app\n");
    assert!(git_status(path_str(&app_dir)).unwrap().entries.is_empty());
}

#[test]
fn git_discard_area_limits_to_untracked_folder_entries() {
    let repo = init_repo();
    std::fs::create_dir_all(repo.path().join("lib")).expect("create lib");
    std::fs::create_dir_all(repo.path().join("test")).expect("create test");
    std::fs::write(repo.path().join("lib/tracked.dart"), "lib\n").expect("write lib tracked");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add tracked file"]);

    std::fs::write(repo.path().join("lib/tracked.dart"), "lib changed\n")
        .expect("modify lib tracked");
    std::fs::write(repo.path().join("lib/new.dart"), "new\n").expect("write lib new");
    std::fs::write(repo.path().join("test/new.dart"), "test new\n").expect("write test new");

    git_discard_area(
        path_str(repo.path()),
        GitChangeArea::Untracked,
        Some("lib".to_string()),
    )
    .unwrap();

    assert!(!repo.path().join("lib/new.dart").exists());
    assert!(repo.path().join("test/new.dart").exists());
    assert_eq!(
        std::fs::read_to_string(repo.path().join("lib/tracked.dart")).unwrap(),
        "lib changed\n"
    );
}

#[test]
fn git_commit_rejects_empty_index() {
    let repo = init_repo();
    let error = git_commit(path_str(repo.path()), "empty".to_string()).unwrap_err();
    assert_eq!(error.kind, GitErrorKind::NothingToCommit);
}

#[test]
fn git_commit_rejects_missing_identity() {
    let repo = init_repo();
    run_git(repo.path(), &["config", "user.name", ""]);
    run_git(repo.path(), &["config", "user.email", ""]);
    std::fs::write(repo.path().join("README.md"), "identity missing\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);

    let error = git_commit(path_str(repo.path()), "update readme".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::MissingIdentity);
    assert!(error.context.contains("user.name"));
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "README.md" && entry.area == GitChangeArea::Staged));
}

#[test]
fn git_commit_rejects_staged_changes_outside_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add workspace files"]);

    std::fs::write(repo.path().join("root.txt"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(
        repo.path(),
        &["add", "root.txt", "packages/app/lib/foo.dart"],
    );

    let error = git_commit(path_str(&app_dir), "workspace commit".to_string()).unwrap_err();
    assert_eq!(error.kind, GitErrorKind::WorkspaceScope);

    let state = git_repository_state(path_str(repo.path())).unwrap();
    assert_eq!(state.ahead, 0);
    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "root.txt" && entry.area == GitChangeArea::Staged));
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app/lib/foo.dart" && entry.area == GitChangeArea::Staged
    }));
}

#[test]
fn git_commit_allows_subdirectory_workspace_when_staged_changes_are_scoped() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app"]);

    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(repo.path(), &["add", "packages/app/lib/foo.dart"]);

    let oid = git_commit(path_str(&app_dir), "workspace commit".to_string()).unwrap();
    assert!(!oid.is_empty());
    assert!(git_status(path_str(&app_dir)).unwrap().entries.is_empty());
}

#[test]
fn git_commit_amend_uses_staged_tree_and_edited_message() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "amended\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);

    let oid = git_commit_amend(path_str(repo.path()), "amended message".to_string()).unwrap();

    assert!(!oid.is_empty());
    assert_eq!(head_commit_message(repo.path()), "amended message");
    assert_eq!(
        std::fs::read_to_string(repo.path().join("README.md")).unwrap(),
        "amended\n"
    );
    assert!(git_status(path_str(repo.path()))
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn git_commit_amend_preserves_author_and_uses_configured_committer() {
    let repo = init_repo();
    run_git(repo.path(), &["config", "user.name", "Amender"]);
    run_git(
        repo.path(),
        &["config", "user.email", "amender@example.com"],
    );
    std::fs::write(repo.path().join("README.md"), "amended\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);

    git_commit_amend(path_str(repo.path()), "amended message".to_string()).unwrap();

    assert_eq!(head_author_name(repo.path()), "Test");
    assert_eq!(head_committer_name(repo.path()), "Amender");
}

#[test]
fn git_commit_amend_rejects_empty_message() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "amended\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);

    let error = git_commit_amend(path_str(repo.path()), "   ".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::NothingToCommit);
}

#[test]
fn git_commit_amend_rejects_missing_identity() {
    let repo = init_repo();
    run_git(repo.path(), &["config", "user.name", ""]);
    run_git(repo.path(), &["config", "user.email", ""]);
    std::fs::write(repo.path().join("README.md"), "amended\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);

    let error = git_commit_amend(path_str(repo.path()), "amended message".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::MissingIdentity);
    assert!(error.context.contains("user.name"));
}

#[test]
fn git_commit_amend_rejects_no_staged_changes() {
    let repo = init_repo();

    let error = git_commit_amend(path_str(repo.path()), "amended message".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::NothingToCommit);
}

#[test]
fn git_commit_amend_rejects_staged_changes_outside_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add workspace files"]);

    std::fs::write(repo.path().join("root.txt"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(
        repo.path(),
        &["add", "root.txt", "packages/app/lib/foo.dart"],
    );

    let error = git_commit_amend(path_str(&app_dir), "amend workspace".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::WorkspaceScope);
}

#[test]
fn git_commit_amend_rejects_unresolved_merge_conflicts() {
    let repo = init_repo();
    run_git(repo.path(), &["checkout", "-b", "feature"]);
    std::fs::write(repo.path().join("README.md"), "feature\n").expect("write feature change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "feature change"]);
    run_git(repo.path(), &["checkout", "main"]);
    std::fs::write(repo.path().join("README.md"), "main\n").expect("write main change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "main change"]);
    run_git_expect_failure(repo.path(), &["merge", "feature"]);

    let error = git_commit_amend(path_str(repo.path()), "amended message".to_string()).unwrap_err();

    assert_eq!(error.kind, GitErrorKind::Conflict);
}

#[test]
fn git_commit_rejects_unresolved_merge_conflicts() {
    let repo = init_repo();
    run_git(repo.path(), &["checkout", "-b", "feature"]);
    std::fs::write(repo.path().join("README.md"), "feature\n").expect("write feature change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "feature change"]);
    run_git(repo.path(), &["checkout", "main"]);
    std::fs::write(repo.path().join("README.md"), "main\n").expect("write main change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "main change"]);
    run_git_expect_failure(repo.path(), &["merge", "feature"]);

    let error = git_commit(path_str(repo.path()), "merge commit".to_string()).unwrap_err();
    assert_eq!(error.kind, GitErrorKind::Conflict);
}

#[test]
fn git_commit_allows_resolved_merge_state() {
    let repo = init_repo();
    run_git(repo.path(), &["checkout", "-b", "feature"]);
    std::fs::write(repo.path().join("README.md"), "feature\n").expect("write feature change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "feature change"]);
    run_git(repo.path(), &["checkout", "main"]);
    std::fs::write(repo.path().join("README.md"), "main\n").expect("write main change");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "main change"]);
    run_git_expect_failure(repo.path(), &["merge", "feature"]);

    std::fs::write(repo.path().join("README.md"), "resolved\n").expect("resolve readme");
    run_git(repo.path(), &["add", "README.md"]);

    let oid = git_commit(path_str(repo.path()), "merge commit".to_string()).unwrap();

    assert!(!oid.is_empty());
    let repository = Repository::discover(repo.path()).expect("open repo");
    assert_eq!(repository.state(), RepositoryState::Clean);
    assert!(git_status(path_str(repo.path()))
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn git_stash_lists_and_pops_tracked_changes() {
    let repo = init_repo();
    let tracked = repo.path().join("README.md");
    std::fs::write(&tracked, "stashed\n").expect("modify readme");
    std::fs::write(repo.path().join("untracked.txt"), "left alone\n").expect("write untracked");

    git_stash(path_str(repo.path())).unwrap();
    assert_eq!(std::fs::read_to_string(&tracked).unwrap(), "hello");
    assert!(repo.path().join("untracked.txt").exists());

    let stashes = git_list_stashes(path_str(repo.path())).unwrap();
    assert_eq!(stashes.len(), 1);
    assert_eq!(stashes[0].reference, "stash@{0}");

    git_stash_pop(path_str(repo.path()), stashes[0].index).unwrap();
    assert_eq!(std::fs::read_to_string(&tracked).unwrap(), "stashed\n");
    assert!(git_list_stashes(path_str(repo.path())).unwrap().is_empty());
}

#[test]
fn git_stash_rejects_tracked_changes_outside_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add stash files"]);

    std::fs::write(repo.path().join("root.txt"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");

    let error = git_stash(path_str(&app_dir)).unwrap_err();
    assert_eq!(error.kind, GitErrorKind::WorkspaceScope);

    assert_eq!(
        std::fs::read_to_string(repo.path().join("root.txt")).unwrap(),
        "root changed\n"
    );
    assert_eq!(
        std::fs::read_to_string(app_lib_dir.join("foo.dart")).unwrap(),
        "app changed\n"
    );
    assert!(git_list_stashes(path_str(repo.path())).unwrap().is_empty());
}

#[test]
fn git_stash_allows_subdirectory_workspace_when_tracked_changes_are_scoped() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add stash files"]);

    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");

    git_stash(path_str(&app_dir)).unwrap();

    assert_eq!(
        std::fs::read_to_string(repo.path().join("root.txt")).unwrap(),
        "root\n"
    );
    assert_eq!(
        std::fs::read_to_string(app_lib_dir.join("foo.dart")).unwrap(),
        "app\n"
    );
    assert_eq!(git_list_stashes(path_str(repo.path())).unwrap().len(), 1);
    assert!(git_status(path_str(repo.path()))
        .unwrap()
        .entries
        .is_empty());
}

#[test]
fn git_stash_pop_rejects_stashes_with_changes_outside_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add stash pop files"]);

    std::fs::write(repo.path().join("root.txt"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(repo.path(), &["stash", "push"]);

    let error = git_stash_pop(path_str(&app_dir), 0).unwrap_err();
    assert_eq!(error.kind, GitErrorKind::WorkspaceScope);

    assert_eq!(
        std::fs::read_to_string(repo.path().join("root.txt")).unwrap(),
        "root\n"
    );
    assert_eq!(
        std::fs::read_to_string(app_lib_dir.join("foo.dart")).unwrap(),
        "app\n"
    );
    assert_eq!(git_list_stashes(path_str(repo.path())).unwrap().len(), 1);
}

#[test]
fn git_stash_pop_allows_subdirectory_workspace_when_stash_is_scoped() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(repo.path().join("root.txt"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add scoped stash pop files"]);

    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(repo.path(), &["stash", "push"]);

    git_stash_pop(path_str(&app_dir), 0).unwrap();

    assert_eq!(
        std::fs::read_to_string(repo.path().join("root.txt")).unwrap(),
        "root\n"
    );
    assert_eq!(
        std::fs::read_to_string(app_lib_dir.join("foo.dart")).unwrap(),
        "app changed\n"
    );
    assert!(git_list_stashes(path_str(repo.path())).unwrap().is_empty());
}

#[test]
fn git_push_sets_origin_upstream_when_missing() {
    let repo = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        repo.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    std::fs::write(repo.path().join("README.md"), "pushed\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);
    run_git(repo.path(), &["commit", "-m", "pushed"]);

    git_push(path_str(repo.path())).unwrap();

    let state = git_repository_state(path_str(repo.path())).unwrap();
    assert_eq!(state.upstream.as_deref(), Some("origin/main"));
    assert_eq!(state.ahead, 0);
}

#[test]
fn git_pull_respects_configured_rebase_strategy() {
    let source = init_repo();
    let bare = tempfile::tempdir().expect("bare remote");
    run_git(bare.path(), &["init", "--bare"]);
    run_git(
        source.path(),
        &["remote", "add", "origin", &path_str(bare.path())],
    );
    run_git(source.path(), &["push", "-u", "origin", "main"]);
    run_git(bare.path(), &["symbolic-ref", "HEAD", "refs/heads/main"]);

    let clone_parent = tempfile::tempdir().expect("clone parent");
    run_git(
        clone_parent.path(),
        &["clone", &path_str(bare.path()), "checkout"],
    );
    let clone_path = clone_parent.path().join("checkout");
    configure_git_identity(&clone_path);

    std::fs::write(source.path().join("remote.txt"), "remote\n").expect("write remote file");
    run_git(source.path(), &["add", "remote.txt"]);
    run_git(source.path(), &["commit", "-m", "remote change"]);
    run_git(source.path(), &["push"]);

    std::fs::write(clone_path.join("local.txt"), "local\n").expect("write local file");
    run_git(&clone_path, &["add", "local.txt"]);
    run_git(&clone_path, &["commit", "-m", "local change"]);
    run_git(&clone_path, &["config", "pull.rebase", "true"]);

    git_pull(path_str(&clone_path)).unwrap();

    let output = git_command(&clone_path, &["rev-list", "--parents", "-n", "1", "HEAD"])
        .output()
        .expect("rev-list runs");
    assert!(output.status.success());
    let parents = String::from_utf8_lossy(&output.stdout);
    assert_eq!(parents.split_whitespace().count(), 2);
    let subject = git_command(&clone_path, &["log", "-1", "--format=%s"])
        .output()
        .expect("log runs");
    assert!(subject.status.success());
    assert_eq!(
        String::from_utf8_lossy(&subject.stdout).trim(),
        "local change"
    );
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
fn git_status_for_path_limits_results_to_selected_file() {
    let repo = init_repo();
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\n").expect("modify readme");
    run_git(repo.path(), &["add", "README.md"]);
    std::fs::write(repo.path().join("README.md"), "hello\nstaged\nunstaged\n")
        .expect("modify readme again");
    std::fs::write(repo.path().join("unrelated.txt"), "unrelated\n").expect("write unrelated");

    let status = git_status_for_path(path_str(repo.path()), "README.md".to_string()).unwrap();

    assert_eq!(status.entries.len(), 2);
    assert!(status.entries.iter().all(|entry| entry.path == "README.md"));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.area == GitChangeArea::Staged));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "unrelated.txt"));
}

#[test]
fn git_status_returns_tree_projection_for_source_control_panel() {
    let repo = init_repo();
    std::fs::create_dir_all(repo.path().join("lib/src")).expect("create lib src");
    std::fs::write(repo.path().join("lib/src/a.dart"), "a\n").expect("write a");
    std::fs::write(repo.path().join("lib/b.dart"), "b\n").expect("write b");

    let status = git_status(path_str(repo.path())).unwrap();
    let group = status
        .groups
        .iter()
        .find(|group| group.area == GitChangeArea::Untracked)
        .expect("untracked group");

    assert_eq!(group.entries.len(), 2);
    assert!(group.tree_rows.iter().any(|row| {
        row.kind == GitChangeTreeRowKind::Directory
            && row.path == "lib"
            && row.depth == 0
            && row.file_count == 2
    }));
    assert!(group.tree_rows.iter().any(|row| {
        row.kind == GitChangeTreeRowKind::File
            && row.path == "lib/b.dart"
            && row
                .entry
                .as_ref()
                .is_some_and(|entry| entry.path == "lib/b.dart")
    }));
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
    assert!(diff_text(&staged.files[0]).contains("+staged"));
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
    assert!(diff_text(&diff.files[0]).contains("changed"));
}

#[test]
fn git_stage_selected_path_uses_repo_relative_index_path_from_subdirectory() {
    let repo = init_repo();
    let root_lib_dir = repo.path().join("lib");
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&root_lib_dir).expect("create root lib dir");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(root_lib_dir.join("foo.dart"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add colliding paths"]);

    std::fs::write(root_lib_dir.join("foo.dart"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");

    git_stage(path_str(&app_dir), Some("lib/foo.dart".to_string())).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "packages/app/lib/foo.dart"
            && entry.area == GitChangeArea::Staged));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "lib/foo.dart" && entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "lib/foo.dart" && entry.area == GitChangeArea::Staged));
}

#[test]
fn git_stage_selected_path_handles_rename_out_from_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    let other_dir = repo.path().join("packages").join("other");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::create_dir_all(&other_dir).expect("create other dir");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app file"]);

    std::fs::rename(app_lib_dir.join("foo.dart"), other_dir.join("foo.dart"))
        .expect("rename file out of workspace");

    git_stage(path_str(&app_dir), Some("lib/foo.dart".to_string())).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app/lib/foo.dart"
            && entry.area == GitChangeArea::Staged
            && entry.status == GitChangeStatus::Deleted
    }));
    assert!(!status.entries.iter().any(|entry| {
        entry.path == "packages/other/foo.dart" && entry.area == GitChangeArea::Staged
    }));
}

#[test]
fn git_stage_all_handles_rename_out_from_subdirectory_workspace() {
    let repo = init_repo();
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    let other_dir = repo.path().join("packages").join("other");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::create_dir_all(&other_dir).expect("create other dir");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add app file"]);

    std::fs::rename(app_lib_dir.join("foo.dart"), other_dir.join("foo.dart"))
        .expect("rename file out of workspace");

    git_stage(path_str(&app_dir), None).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status.entries.iter().any(|entry| {
        entry.path == "packages/app/lib/foo.dart"
            && entry.area == GitChangeArea::Staged
            && entry.status == GitChangeStatus::Deleted
    }));
    assert!(!status.entries.iter().any(|entry| {
        entry.path == "packages/other/foo.dart" && entry.area == GitChangeArea::Staged
    }));
}

#[test]
fn git_unstage_selected_path_uses_repo_relative_index_path_from_subdirectory() {
    let repo = init_repo();
    let root_lib_dir = repo.path().join("lib");
    let app_dir = repo.path().join("packages").join("app");
    let app_lib_dir = app_dir.join("lib");
    std::fs::create_dir_all(&root_lib_dir).expect("create root lib dir");
    std::fs::create_dir_all(&app_lib_dir).expect("create app lib dir");
    std::fs::write(root_lib_dir.join("foo.dart"), "root\n").expect("write root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app\n").expect("write app file");
    run_git(repo.path(), &["add", "."]);
    run_git(repo.path(), &["commit", "-m", "add colliding paths"]);

    std::fs::write(root_lib_dir.join("foo.dart"), "root changed\n").expect("modify root file");
    std::fs::write(app_lib_dir.join("foo.dart"), "app changed\n").expect("modify app file");
    run_git(
        repo.path(),
        &["add", "lib/foo.dart", "packages/app/lib/foo.dart"],
    );

    git_unstage(path_str(&app_dir), Some("lib/foo.dart".to_string())).unwrap();

    let status = git_status(path_str(repo.path())).unwrap();
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "packages/app/lib/foo.dart"
            && entry.area == GitChangeArea::Unstaged));
    assert!(!status
        .entries
        .iter()
        .any(|entry| entry.path == "packages/app/lib/foo.dart"
            && entry.area == GitChangeArea::Staged));
    assert!(status
        .entries
        .iter()
        .any(|entry| entry.path == "lib/foo.dart" && entry.area == GitChangeArea::Staged));
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
    assert!(diff_text(&diff.files[0]).contains("new file mode 120000"));
    assert!(diff_text(&diff.files[0]).contains(&path_str(&target)));
    assert!(!diff_text(&diff.files[0]).contains("SECRET MATERIAL"));
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
    assert!(diff_text(&diff.files[0]).contains("rename from old.txt"));
    assert!(diff_text(&diff.files[0]).contains("rename to new.txt"));
}

#[test]
fn git_diff_truncates_large_unicode_without_panicking() {
    let repo = init_repo();
    let total_added_lines = 120_000u32;
    let expected_added_lines = total_added_lines + 1;
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
    assert!(single.files[0].line_preview_truncated);
    assert_eq!(single.files[0].added, Some(expected_added_lines));
    let single_text = diff_text(&single.files[0]);
    assert!(single_text.is_char_boundary(single_text.len()));

    let combined = git_diff_all(path_str(repo.path()), None).unwrap();
    assert!(combined.files[0].line_preview_truncated);
    assert_eq!(combined.files[0].added, Some(expected_added_lines));
    let combined_text = diff_text(&combined.files[0]);
    assert!(combined_text.is_char_boundary(combined_text.len()));
}
