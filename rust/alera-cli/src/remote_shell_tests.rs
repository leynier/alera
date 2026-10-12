use alera_core::runtime::{SshAuthKind, SshBootstrapStatus};

use super::*;

fn target(platform: Option<&str>, runtime_platform: Option<&str>) -> SshTarget {
    let now = chrono::Utc::now();
    SshTarget {
        id: "build-box".to_string(),
        alias: "Build Box".to_string(),
        host: "build.invalid".to_string(),
        port: 22,
        username: "dev".to_string(),
        platform: platform.map(str::to_string),
        arch: None,
        auth_kind: SshAuthKind::Agent,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        projects_dir: None,
        identity_file: None,
        runtime_version: None,
        runtime_platform: runtime_platform.map(str::to_string),
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::Installed,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

#[test]
fn platform_names_map_to_their_shell() {
    for (platform, shell) in [
        ("linux", Some(RemoteShell::Posix)),
        ("Darwin", Some(RemoteShell::Posix)),
        ("macos", Some(RemoteShell::Posix)),
        ("win32", Some(RemoteShell::Windows)),
        ("Windows_NT", Some(RemoteShell::Windows)),
        ("MINGW64_NT-10.0", Some(RemoteShell::Windows)),
        ("freebsd", None),
        ("", None),
    ] {
        assert_eq!(RemoteShell::from_platform(platform), shell, "{platform}");
    }
}

#[test]
fn the_validated_runtime_platform_wins_over_the_typed_one() {
    assert_eq!(
        RemoteShell::from_target(&target(Some("linux"), Some("windows"))).unwrap(),
        RemoteShell::Windows
    );
    assert_eq!(
        RemoteShell::from_target(&target(Some("windows"), Some("darwin"))).unwrap(),
        RemoteShell::Posix
    );
    assert_eq!(
        RemoteShell::from_target(&target(Some("windows"), None)).unwrap(),
        RemoteShell::Windows
    );
}

#[test]
fn an_unknown_platform_names_the_bootstrap_command() {
    for remote in [
        target(None, None),
        target(Some("windows"), Some("plan9")),
        target(Some("plan9"), None),
    ] {
        assert_eq!(RemoteShell::recorded(&remote), None);
        let message = RemoteShell::from_target(&remote).unwrap_err().to_string();
        assert!(
            message.contains("alera ssh-target bootstrap --id build-box"),
            "{message}"
        );
    }
}

#[test]
fn quoting_escapes_single_quotes_for_each_shell() {
    assert_eq!(RemoteShell::Posix.quote("it's"), r#"'it'"'"'s'"#);
    assert_eq!(RemoteShell::Windows.quote("it's"), "'it''s'");
    assert_eq!(RemoteShell::Posix.quote("$HOME `x`"), "'$HOME `x`'");
    assert_eq!(RemoteShell::Windows.quote("$env:HOME"), "'$env:HOME'");
}

#[test]
fn join_uses_forward_slashes_and_the_sftp_drive_form_on_windows() {
    assert_eq!(
        RemoteShell::Posix.join("/home/dev/sidecar/", &["data", "/x/"]),
        "/home/dev/sidecar/data/x"
    );
    assert_eq!(
        RemoteShell::Windows.join(r"C:\Users\dev\Alera", &["staging", "job"]),
        "/C:/Users/dev/Alera/staging/job"
    );
    assert!(RemoteShell::Windows.is_windows());
    assert!(!RemoteShell::Posix.is_windows());
}
