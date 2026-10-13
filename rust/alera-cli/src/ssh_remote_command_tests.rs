use std::time::{Duration, Instant};

use alera_core::runtime::{SshAuthKind, SshBootstrapStatus};
use anyhow::Context;

use super::*;

fn target() -> SshTarget {
    let now = chrono::Utc::now();
    SshTarget {
        id: "build-box".to_string(),
        alias: "Build Box".to_string(),
        host: "build.invalid".to_string(),
        port: 2222,
        username: "dev".to_string(),
        platform: None,
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        projects_dir: None,
        identity_file: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::Installed,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

fn sh(script: &str) -> Vec<String> {
    vec!["-c".to_string(), script.to_string()]
}

#[test]
fn ssh_and_sftp_share_the_connection_policy() {
    let ssh = ssh_args(&target());
    let sftp = sftp_args(&target());
    assert_eq!(&ssh[..2], ["-p", "2222"]);
    assert_eq!(&sftp[..2], ["-P", "2222"]);
    for args in [&ssh, &sftp] {
        for option in [
            "BatchMode=yes",
            "ConnectTimeout=15",
            "StrictHostKeyChecking=accept-new",
        ] {
            let at = args.iter().position(|arg| arg == option).unwrap();
            assert_eq!(args[at - 1], "-o");
        }
        assert_eq!(args.last().unwrap(), "dev@build.invalid");
    }
    let mut anonymous = target();
    anonymous.username = " ".to_string();
    assert_eq!(sftp_args(&anonymous).last().unwrap(), "build.invalid");
}

#[test]
fn an_identity_file_is_the_only_key_ssh_and_sftp_offer() {
    for args in [ssh_args(&target()), sftp_args(&target())] {
        assert!(!args.contains(&"-i".to_string()), "{args:?}");
        assert!(
            !args.contains(&"IdentitiesOnly=yes".to_string()),
            "{args:?}"
        );
    }
    let mut keyed = target();
    keyed.identity_file = Some(" ~/.ssh/build key ".to_string());
    for args in [ssh_args(&keyed), sftp_args(&keyed)] {
        let at = args.iter().position(|arg| arg == "-i").unwrap();
        assert_eq!(args[at + 1], "~/.ssh/build key");
        assert_eq!(args[at + 2], "-o");
        assert_eq!(args[at + 3], "IdentitiesOnly=yes");
        assert_eq!(args.last().unwrap(), "dev@build.invalid");
    }
    keyed.identity_file = Some("  ".to_string());
    assert!(!ssh_args(&keyed).contains(&"-i".to_string()));
}

#[test]
fn budgets_have_the_documented_durations() {
    assert_eq!(
        RemoteCommandBudget::Probe.duration(),
        Duration::from_secs(20)
    );
    assert_eq!(
        RemoteCommandBudget::Command.duration(),
        Duration::from_secs(60)
    );
    assert_eq!(
        RemoteCommandBudget::Install.duration(),
        Duration::from_secs(600)
    );
    assert_eq!(
        RemoteCommandBudget::Transfer.duration(),
        Duration::from_secs(900)
    );
    assert_eq!(
        RemoteCommandBudget::Provision.duration(),
        Duration::from_secs(1800)
    );
    assert_eq!(RemoteCommandBudget::Command.to_string(), "command (60s)");
}

#[test]
fn shell_probe_order_asks_powershell_first_for_recorded_windows_hosts() {
    let mut remote = target();
    assert_eq!(
        shell_probe_order(&remote),
        [RemoteShell::Posix, RemoteShell::Windows]
    );
    remote.runtime_platform = Some("windows".to_string());
    assert_eq!(
        shell_probe_order(&remote),
        [RemoteShell::Windows, RemoteShell::Posix]
    );
}

#[cfg(unix)]
#[tokio::test]
async fn a_failed_command_keeps_its_exit_code_and_both_streams() {
    let error = run_checked(
        "sh",
        &sh("echo partial; echo 'fatal: no such repo' >&2; exit 3"),
        RemoteCommandBudget::Probe,
    )
    .await
    .unwrap_err();
    match error.downcast_ref::<RemoteCommandError>() {
        Some(RemoteCommandError::Exit {
            code,
            stderr_tail,
            stdout_tail,
            ..
        }) => {
            assert_eq!(*code, Some(3));
            assert_eq!(stderr_tail, "fatal: no such repo\n");
            assert_eq!(stdout_tail, "partial\n");
        }
        other => panic!("expected an exit error, got {other:?}"),
    }
    let error = Err::<(), _>(error)
        .context("Could not inspect the checkout")
        .unwrap_err();
    assert_eq!(
        format!("{error:#}"),
        "Could not inspect the checkout: sh failed: fatal: no such repo partial"
    );
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn a_command_past_its_budget_is_killed() {
    let directory = tempfile::tempdir().unwrap();
    let pid_file = directory.path().join("pid");
    let script = format!(
        "echo $$ > {}; exec sleep 30",
        shell_quote(pid_file.to_str().unwrap())
    );
    let started = Instant::now();
    let error = run_checked(
        "sh",
        &sh(&script),
        RemoteCommandBudget::Custom(Duration::from_millis(500)),
    )
    .await
    .unwrap_err();
    assert!(started.elapsed() < Duration::from_secs(20));
    assert!(matches!(
        error.downcast_ref::<RemoteCommandError>(),
        Some(RemoteCommandError::Timeout { program, .. }) if program == "sh"
    ));
    assert!(error.to_string().contains("budget"), "{error}");
    let pid = std::fs::read_to_string(&pid_file).unwrap();
    let pid = pid.trim();
    // A killed child may linger as a zombie until it is reaped; that counts
    // as stopped.
    let mut alive = true;
    for _ in 0..50 {
        let state = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
        let running = state
            .rsplit_once(") ")
            .is_some_and(|(_, rest)| !rest.starts_with('Z'));
        if !running {
            alive = false;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(!alive, "the timed-out child {pid} is still running");
}

#[test]
fn output_tail_keeps_the_last_bytes_on_a_char_boundary() {
    let short = "abc";
    assert_eq!(output_tail(short), "abc");
    let long = format!("{}{}", "x".repeat(REMOTE_OUTPUT_TAIL_BYTES), "é".repeat(10));
    let tail = output_tail(&long);
    assert!(tail.len() <= REMOTE_OUTPUT_TAIL_BYTES);
    assert!(tail.ends_with(&"é".repeat(10)));
}

#[test]
fn powershell_encoded_is_utf16le_base64() {
    assert_eq!(powershell_encoded("ab"), "YQBiAA==");
}

#[test]
fn windows_sftp_path_forces_openssh_absolute_drive_form() {
    assert_eq!(
        windows_sftp_path(r"C:\Users\leyni\AppData\Local\Alera\runtime"),
        "/C:/Users/leyni/AppData/Local/Alera/runtime"
    );
    assert_eq!(
        windows_sftp_path("C:/Users/leyni/AppData/Local/Alera/runtime"),
        "/C:/Users/leyni/AppData/Local/Alera/runtime"
    );
    assert_eq!(
        windows_sftp_path("/C:/Users/leyni/AppData/Local/Alera/runtime"),
        "/C:/Users/leyni/AppData/Local/Alera/runtime"
    );
    assert_eq!(
        windows_sftp_path("//C:/Users/leyni/AppData/Local/Alera/runtime/"),
        "/C:/Users/leyni/AppData/Local/Alera/runtime"
    );
    assert_eq!(windows_sftp_path("c:/Users/me"), "/c:/Users/me");
    assert_eq!(windows_sftp_path("D:"), "/D:");
}

#[test]
fn remote_join_windows_builds_absolute_sftp_destinations() {
    assert_eq!(
        remote_join(
            RemoteShell::Windows,
            r"C:\Users\leyni\AppData\Local\Alera\runtime",
            &["staging", "job", "archive.tar.gz"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging/job/archive.tar.gz"
    );
    assert_eq!(
        remote_join(
            RemoteShell::Windows,
            "C:/Users/leyni/AppData/Local/Alera/runtime",
            &["staging", "job"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging/job"
    );
    assert_eq!(
        remote_join(
            RemoteShell::Windows,
            "/C:/Users/leyni/AppData/Local/Alera/runtime",
            &["staging"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging"
    );
    assert_eq!(
        remote_join(
            RemoteShell::Posix,
            "/home/me/.alera/sidecar",
            &["staging", "job"]
        ),
        "/home/me/.alera/sidecar/staging/job"
    );
}
