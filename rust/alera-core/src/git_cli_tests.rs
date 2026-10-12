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
fn applies_owner_environment_without_persisting_git_configuration() {
    let dir = init_repo();
    let environment = std::collections::BTreeMap::from([
        ("GIT_CONFIG_COUNT".into(), "1".into()),
        (
            "GIT_CONFIG_KEY_0".into(),
            "alera.owner-checkout-test".into(),
        ),
        ("GIT_CONFIG_VALUE_0".into(), "owner-value".into()),
    ]);
    let value = super::git_in_dir_with_environment(
        dir.path(),
        &["config", "--get", "alera.owner-checkout-test"],
        &environment,
    )
    .unwrap();
    assert_eq!(value.trim(), "owner-value");
    assert!(git_in_dir(
        dir.path(),
        &["config", "--local", "--get", "alera.owner-checkout-test"]
    )
    .is_err());
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

#[test]
fn streaming_git_emits_bounded_actual_output_and_failure() {
    let lines = std::sync::Mutex::new(Vec::new());
    let collect = |line| lines.lock().unwrap().push(line);
    let result =
        super::git_in_dir_with_progress(std::path::Path::new("."), &["--version"], &collect)
            .unwrap();
    assert!(result.starts_with("git version"));
    assert!(lines
        .lock()
        .unwrap()
        .iter()
        .any(|line| line.starts_with("git version")));
    assert!(super::git_in_dir_with_progress(
        std::path::Path::new("."),
        &["--alera-invalid"],
        &collect
    )
    .is_err());
    assert!(lines
        .lock()
        .unwrap()
        .iter()
        .all(|line| line.chars().count() <= 512));
}

#[test]
fn progress_redacts_credentials_and_bounds_output() {
    assert_eq!(
        super::redact_progress_line("To https://user:password@example.org/repo"),
        "To https://[redacted]@example.org/repo"
    );
    assert_eq!(
        super::redact_progress_line("Authorization: Bearer secret"),
        "[redacted authentication output]"
    );
    assert_eq!(super::redact_progress_line(&"x".repeat(5000)).len(), 512);
}

#[test]
fn failures_redact_stderr_stdout_and_command_credentials() {
    #[cfg(unix)]
    let status = {
        use std::os::unix::process::ExitStatusExt;
        std::process::ExitStatus::from_raw(256)
    };
    #[cfg(windows)]
    let status = {
        use std::os::windows::process::ExitStatusExt;
        std::process::ExitStatus::from_raw(1)
    };
    let diagnostics = b"fatal: https://user:secret@example.org/repo\nAuthorization: private\rpassword=private\ntoken=private\nBearer private\nordinary diagnostic";
    for stderr in [true, false] {
        let output = std::process::Output {
            status,
            stdout: if stderr {
                Vec::new()
            } else {
                diagnostics.to_vec()
            },
            stderr: if stderr {
                diagnostics.to_vec()
            } else {
                Vec::new()
            },
        };
        let error =
            super::failure_message(&["push", "https://user:secret@example.org/repo"], &output);
        assert!(!error.contains("secret"), "{error}");
        assert!(!error.contains("private"), "{error}");
        assert!(!error.contains("user:"), "{error}");
        assert!(error.contains("ordinary diagnostic"), "{error}");
        assert!(error.contains("https://[redacted]@example.org/repo"));
    }
}
