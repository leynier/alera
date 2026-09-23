use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use alera_core::child_process::windowless_command;
use tempfile::TempDir;

use super::{parse_nested_submodule_paths, run, run_with_submodules};

static GIT_CONFIG_ENV_LOCK: Mutex<()> = Mutex::new(());

struct FileProtocolAllowGuard {
    _lock: std::sync::MutexGuard<'static, ()>,
}

impl FileProtocolAllowGuard {
    fn acquire() -> Self {
        let lock = GIT_CONFIG_ENV_LOCK.lock().expect("git config env lock");
        unsafe {
            std::env::set_var("GIT_CONFIG_COUNT", "1");
            std::env::set_var("GIT_CONFIG_KEY_0", "protocol.file.allow");
            std::env::set_var("GIT_CONFIG_VALUE_0", "always");
        }
        Self { _lock: lock }
    }
}

impl Drop for FileProtocolAllowGuard {
    fn drop(&mut self) {
        unsafe {
            std::env::remove_var("GIT_CONFIG_COUNT");
            std::env::remove_var("GIT_CONFIG_KEY_0");
            std::env::remove_var("GIT_CONFIG_VALUE_0");
        }
    }
}

fn git(dir: &Path, args: &[&str]) {
    let output = windowless_command("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_AUTHOR_NAME", "Alera Test")
        .env("GIT_AUTHOR_EMAIL", "alera-test@example.com")
        .env("GIT_COMMITTER_NAME", "Alera Test")
        .env("GIT_COMMITTER_EMAIL", "alera-test@example.com")
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .expect("spawn git");
    assert!(
        output.status.success(),
        "git {} failed in {}: {}",
        args.join(" "),
        dir.display(),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn init_repo(dir: &Path) {
    git(dir, &["init", "-b", "main"]);
    git(dir, &["config", "user.name", "Alera Test"]);
    git(dir, &["config", "user.email", "alera-test@example.com"]);
}

fn commit_file(dir: &Path, relative: &str, contents: &str, message: &str) {
    let path = dir.join(relative);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent");
    }
    fs::write(&path, contents).expect("write file");
    git(dir, &["add", relative]);
    git(dir, &["commit", "-m", message]);
}

fn git_stdout(dir: &Path, args: &[&str]) -> String {
    let output = windowless_command("git")
        .args(args)
        .current_dir(dir)
        .output()
        .expect("spawn git");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn embed_gitlink(parent: &Path, child: &Path, relative_path: &str) {
    let sha = git_stdout(child, &["rev-parse", "HEAD"]);
    let name = relative_path.replace('/', "_");
    fs::write(
        parent.join(".gitmodules"),
        format!(
            "[submodule \"{name}\"]\n\tpath = {relative_path}\n\turl = {}\n",
            child.display()
        ),
    )
    .expect("write gitmodules");
    git(parent, &["add", ".gitmodules"]);
    let output = windowless_command("git")
        .args([
            "update-index",
            "--add",
            "--cacheinfo",
            "160000",
            sha.trim(),
            relative_path,
        ])
        .current_dir(parent)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .output()
        .expect("update-index");
    assert!(
        output.status.success(),
        "update-index failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    git(parent, &["commit", "-m", "add submodule gitlink"]);
}

fn clone_into(child: &Path, destination: &Path) {
    fs::create_dir_all(destination.parent().expect("parent")).expect("create dest parent");
    let output = windowless_command("git")
        .args([
            "clone",
            child.to_str().expect("utf8 child"),
            destination.to_str().expect("utf8 dest"),
        ])
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .expect("clone");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn parse_nested_paths_skips_empty_config() {
    let dir = PathBuf::from("/tmp/example");
    let paths = parse_nested_submodule_paths(1, "", "", &dir).expect("empty");
    assert!(paths.is_empty());
}

#[test]
fn parse_nested_paths_reads_last_token() {
    let dir = PathBuf::from("/tmp/example");
    let paths = parse_nested_submodule_paths(
        0,
        "submodule.ghostty.path ghostty\nsubmodule.other.path nested/lib\n",
        "",
        &dir,
    )
    .expect("paths");
    assert_eq!(paths, vec!["ghostty".to_string(), "nested/lib".to_string()]);
}

#[test]
fn missing_git_metadata_fails() {
    let dir = TempDir::new().expect("tempdir");
    let error = run(dir.path().to_path_buf()).expect_err("not a repo");
    assert!(
        error.0.contains("Repository metadata was not found"),
        "{}",
        error.0
    );
}

#[test]
fn refuses_a_dirty_submodule_checkout() {
    let parent_dir = TempDir::new().expect("parent");
    let child_dir = TempDir::new().expect("child");
    let parent = parent_dir.path();
    let child = child_dir.path();
    const PATH: &str = "third_party/xterm";

    init_repo(child);
    commit_file(child, "readme.txt", "one\n", "first");
    let first = git_stdout(child, &["rev-parse", "HEAD"]);
    commit_file(child, "readme.txt", "two\n", "second");

    init_repo(parent);
    commit_file(parent, "root.txt", "root\n", "parent root");
    embed_gitlink(parent, child, PATH);

    let vendor = parent.join(PATH);
    clone_into(child, &vendor);
    git(&vendor, &["checkout", first.trim()]);
    fs::write(vendor.join("dirty.txt"), "local change\n").expect("dirty file");

    let error = run_with_submodules(parent.to_path_buf(), &[PATH]).expect_err("dirty");
    assert!(
        error.0.contains("Refusing to move"),
        "expected dirty refusal, got {}",
        error.0
    );
}

#[test]
fn initializes_a_clean_local_submodule() {
    let parent_dir = TempDir::new().expect("parent");
    let child_dir = TempDir::new().expect("child");
    let parent = parent_dir.path();
    let child = child_dir.path();
    const PATH: &str = "third_party/xterm";

    init_repo(child);
    commit_file(child, "readme.txt", "child\n", "child commit");
    init_repo(parent);
    commit_file(parent, "root.txt", "root\n", "parent root");
    embed_gitlink(parent, child, PATH);
    git(parent, &["config", "protocol.file.allow", "always"]);
    let _file_protocol = FileProtocolAllowGuard::acquire();
    run_with_submodules(parent.to_path_buf(), &[PATH]).expect("initialize");
    let expected = git_stdout(child, &["rev-parse", "HEAD"]);
    let actual = git_stdout(&parent.join(PATH), &["rev-parse", "HEAD"]);
    assert_eq!(actual.trim(), expected.trim());
}
