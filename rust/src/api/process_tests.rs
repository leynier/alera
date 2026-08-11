use super::process_shell::{posix_shell_invocation, windows_shell_invocation, ShellInvocation};
use super::{process_close_stdin, process_kill, process_run, process_write_stdin};

fn args(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
}

#[test]
fn posix_shell_quotes_every_token() {
    let invocation = posix_shell_invocation("gh", &args(&["pr", "list", "--json", "number"]));

    assert_eq!(
        invocation,
        ShellInvocation::Posix {
            program: "/bin/sh".to_string(),
            arguments: args(&["-c", "'gh' 'pr' 'list' '--json' 'number'"]),
        }
    );
}

#[test]
fn posix_shell_splices_single_quotes_out_of_the_quoted_run() {
    let invocation = posix_shell_invocation("echo", &args(&["it's fine"]));

    let ShellInvocation::Posix { arguments, .. } = invocation else {
        panic!("posix invocation");
    };
    assert_eq!(arguments[1], r#"'echo' 'it'"'"'s fine'"#);
}

#[test]
fn windows_shell_wraps_the_line_for_cmd() {
    let invocation = windows_shell_invocation("gh", &args(&["pr", "list"]));

    assert_eq!(
        invocation,
        ShellInvocation::Windows {
            program: "cmd.exe".to_string(),
            raw_arguments: r#"/d /s /c ""gh" "pr" "list"""#.to_string(),
        }
    );
}

#[test]
fn windows_shell_escapes_embedded_quotes() {
    let invocation = windows_shell_invocation("echo", &args(&[r#"he said "hi""#]));

    let ShellInvocation::Windows { raw_arguments, .. } = invocation else {
        panic!("windows invocation");
    };
    assert_eq!(
        raw_arguments,
        "/d /s /c \"\"echo\" \"he said \\\"hi\\\"\"\""
    );
}

#[test]
fn windows_shell_keeps_a_path_with_spaces_in_one_token() {
    let invocation =
        windows_shell_invocation(r"C:\Program Files\Git\bin\git.exe", &args(&["--version"]));

    let ShellInvocation::Windows { raw_arguments, .. } = invocation else {
        panic!("windows invocation");
    };
    assert_eq!(
        raw_arguments,
        "/d /s /c \"\"C:\\Program Files\\Git\\bin\\git.exe\" \"--version\"\""
    );
}

#[cfg(windows)]
#[test]
fn windows_run_preserves_script_paths_and_shell_metacharacters() {
    let directory = tempfile::tempdir().expect("tempdir");
    let script_directory = directory.path().join("scripts with spaces");
    std::fs::create_dir(&script_directory).expect("create script directory");
    let script = script_directory.join("argument probe.cmd");
    std::fs::write(
        &script,
        "@echo off\r\nif not \"%~1\"==\"A&B\" exit /b 17\r\nexit /b 0\r\n",
    )
    .expect("write command script");

    let result = process_run(
        script.to_string_lossy().into_owned(),
        args(&["A&B"]),
        None,
        None,
    )
    .expect("command script runs");

    assert_eq!(result.exit_code, 0, "stderr: {}", result.stderr);
}

#[cfg(windows)]
#[test]
fn windows_run_prefers_a_working_directory_command_over_path() {
    let directory = tempfile::tempdir().expect("tempdir");
    let working_directory = directory.path().join("working directory");
    let path_directory = directory.path().join("path directory");
    std::fs::create_dir(&working_directory).expect("create working directory");
    std::fs::create_dir(&path_directory).expect("create path directory");
    std::fs::write(
        working_directory.join("alera-precedence-probe.cmd"),
        "@echo off\r\necho working-directory\r\n",
    )
    .expect("write working-directory command");
    std::fs::write(
        path_directory.join("alera-precedence-probe.cmd"),
        "@echo off\r\necho path\r\n",
    )
    .expect("write PATH command");
    let mut environment = std::collections::HashMap::new();
    environment.insert(
        "PATH".to_string(),
        path_directory.to_string_lossy().into_owned(),
    );

    let result = process_run(
        "alera-precedence-probe".to_string(),
        Vec::new(),
        Some(working_directory.to_string_lossy().into_owned()),
        Some(environment),
    )
    .expect("working-directory command runs");

    assert_eq!(result.exit_code, 0, "stderr: {}", result.stderr);
    assert_eq!(result.stdout.trim(), "working-directory");
}

#[test]
fn run_captures_stdout_and_the_exit_code() {
    let result = process_run("git".to_string(), args(&["--version"]), None, None)
        .expect("git --version runs");

    assert_eq!(result.exit_code, 0);
    assert!(
        result.stdout.starts_with("git version"),
        "stdout: {}",
        result.stdout
    );
}

#[test]
fn run_reports_a_failing_command_with_its_stderr() {
    let directory = tempfile::tempdir().expect("tempdir");

    let result = process_run(
        "git".to_string(),
        args(&["rev-parse", "--verify", "refs/heads/missing"]),
        Some(directory.path().to_string_lossy().to_string()),
        None,
    )
    .expect("git runs");

    assert_ne!(result.exit_code, 0);
    assert!(
        result.stderr.to_lowercase().contains("fatal"),
        "stderr: {}",
        result.stderr
    );
}

#[test]
fn run_uses_the_requested_working_directory() {
    let directory = tempfile::tempdir().expect("tempdir");
    process_run(
        "git".to_string(),
        args(&["init"]),
        Some(directory.path().to_string_lossy().to_string()),
        None,
    )
    .expect("git init runs");

    assert!(directory.path().join(".git").exists());
}

#[test]
fn run_adds_the_requested_environment() {
    let mut environment = std::collections::HashMap::new();
    environment.insert("GIT_AUTHOR_NAME".to_string(), "Alera Test".to_string());
    environment.insert(
        "GIT_AUTHOR_EMAIL".to_string(),
        "alera-test@example.com".to_string(),
    );

    let result = process_run(
        "git".to_string(),
        args(&["var", "GIT_AUTHOR_IDENT"]),
        None,
        Some(environment),
    )
    .expect("git var runs");

    assert!(
        result
            .stdout
            .starts_with("Alera Test <alera-test@example.com>"),
        "stdout: {}",
        result.stdout
    );
}

#[test]
fn writing_to_an_unknown_session_is_refused_instead_of_panicking() {
    assert!(!process_write_stdin(i64::MAX, vec![b'x']));
    assert!(!process_kill(i64::MAX));
    process_close_stdin(i64::MAX);
}

#[test]
fn a_notified_kill_ends_a_child_that_would_keep_waiting() {
    use std::sync::Arc;
    use std::time::Duration;

    use tokio::sync::Notify;

    let kill = Arc::new(Notify::new());
    let status = super::process_session::wait_for_exit_in_tests(
        "git",
        &args(&["hash-object", "--stdin"]),
        kill.clone(),
        Duration::from_millis(100),
    );

    assert!(status.is_ok(), "kill reports a status: {status:?}");
    assert_ne!(status.unwrap(), 0);
}
