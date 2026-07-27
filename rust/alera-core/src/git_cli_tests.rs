use super::{git_in_dir, GitCliError};

fn init_repo() -> tempfile::TempDir {
    let dir = tempfile::tempdir().expect("tempdir");
    git_in_dir(dir.path(), &["init", "-b", "main"]).expect("git init");
    dir
}

#[test]
fn returns_stdout_from_the_requested_directory() {
    let dir = init_repo();
    git_in_dir(dir.path(), &["config", "user.name", "Alera Test"]).expect("git config write");

    let value =
        git_in_dir(dir.path(), &["config", "--local", "user.name"]).expect("git config read");

    assert_eq!(value.trim(), "Alera Test");
}

#[test]
fn failure_carries_the_cli_diagnostics() {
    let dir = init_repo();

    let error = git_in_dir(dir.path(), &["rev-parse", "--verify", "refs/heads/missing"])
        .expect_err("unknown ref fails");

    assert!(
        error
            .message
            .starts_with("git rev-parse --verify refs/heads/missing failed"),
        "message names the command: {}",
        error.message
    );
    assert!(
        error.message.to_lowercase().contains("fatal"),
        "message keeps the git diagnostics: {}",
        error.message
    );
}

#[test]
fn failure_outside_a_repository_is_reported() {
    let dir = tempfile::tempdir().expect("tempdir");

    let error = git_in_dir(dir.path(), &["status", "--porcelain"]).expect_err("not a repository");

    assert!(
        error
            .message
            .to_lowercase()
            .contains("not a git repository"),
        "message keeps the git diagnostics: {}",
        error.message
    );
}

#[test]
fn error_renders_as_its_message() {
    let error = GitCliError {
        message: "git fetch failed: boom".to_string(),
    };

    assert_eq!(error.to_string(), "git fetch failed: boom");
}
