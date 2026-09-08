use super::*;

#[test]
fn default_install_dir_uses_sidecar_layout_on_posix() {
    assert_eq!(default_install_dir("linux"), "~/.alera/sidecar");
    assert_eq!(default_install_dir("macos"), "~/.alera/sidecar");
    assert_eq!(default_install_dir("auto"), "~/.alera/sidecar");
    assert_eq!(
        default_install_dir("windows"),
        r"%LOCALAPPDATA%\Alera\runtime"
    );
}

#[test]
fn normalizes_common_platform_and_arch_values() {
    assert_eq!(normalize_platform("Darwin"), "macos");
    assert_eq!(normalize_platform("Windows_NT"), "windows");
    assert_eq!(normalize_platform("MINGW64_NT-10.0-22631"), "windows");
    assert_eq!(normalize_platform("MSYS_NT-10.0-22631"), "windows");
    assert_eq!(normalize_platform("CYGWIN_NT-10.0-22631"), "windows");
    assert_eq!(normalize_arch("x86_64"), "x64");
    assert_eq!(normalize_arch("AARCH64"), "arm64");
}

#[test]
fn posix_install_script_repoints_current_symlink_and_runtime_data_dir() {
    let script = posix_install_script(
        "/home/me/.alera/sidecar",
        "1.2.3",
        "linux",
        "x64",
        "/home/me/.alera/sidecar/staging/job/alera-runtime.tar.gz",
        "alera",
    );
    assert!(script.contains("ln -sfn \"$version_dir\" \"$install_dir/current\""));
    assert!(!script.contains("current.tmp"));
    assert!(script.contains("trap rollback EXIT"));
    assert!(!script.contains("trap rollback ERR"));
    assert!(script.contains("mkdir -p \"$version_dir\" \"$install_dir/bin\" \"$install_dir/data\""));
    assert!(script.contains("export ALERA_RUNTIME_DIR=\"$DIR/data\""));
    assert!(script.contains("exec \"$DIR/current/alera\" \"$@\""));
    assert!(script.contains("<<-'SH'"));
    assert!(script.contains("\n\tSH\n"));
}

#[test]
fn configured_platform_and_arch_prevent_detection_requirement() {
    let target = SshTarget {
        id: "target-1".to_string(),
        alias: "remote".to_string(),
        host: "remote.example.test".to_string(),
        port: 22,
        username: "alera".to_string(),
        platform: Some("Darwin".to_string()),
        arch: Some("AARCH64".to_string()),
        auth_kind: SshAuthKind::Agent,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
        last_status: None,
        install_dir: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::NotInstalled,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    };
    let request = SshTargetBootstrapRequest {
        target_id: target.id.clone(),
        install_dir: None,
        platform: Some("linux".to_string()),
        arch: Some("x86_64".to_string()),
        channel: None,
        version: None,
        archive_url: None,
        archive_path: None,
        artifact_path: None,
        manifest_public_key: None,
    };

    assert_eq!(
        configured_bootstrap_platform(&request, &target).as_deref(),
        Some("linux")
    );
    assert_eq!(
        configured_bootstrap_arch(&request, &target).as_deref(),
        Some("x64")
    );
}

#[test]
fn runtime_archive_public_key_selection_ignores_empty_values() {
    assert_eq!(
        select_runtime_archive_public_key(
            Some(" ".to_string()),
            Some("\t".to_string()),
            Some(" update-key ".to_string()),
        )
        .as_deref(),
        Some("update-key")
    );
    assert_eq!(
        select_runtime_archive_public_key(
            Some(" request-key ".to_string()),
            Some("runtime-key".to_string()),
            Some("update-key".to_string()),
        )
        .as_deref(),
        Some("request-key")
    );
}

#[test]
fn windows_install_script_avoids_symlink_privileges() {
    let script = windows_install_script(
        "C:/Users/me/AppData/Local/Alera/runtime",
        "1.2.3",
        "windows",
        "x64",
        "C:/Users/me/AppData/Local/Alera/runtime/staging/job/alera-runtime.tar.gz",
        "alera.exe",
    );
    assert!(script.contains("current.txt"));
    assert!(script.contains("alera.cmd"));
    assert!(script.contains("set \"ALERA_RUNTIME_DIR=%~dp0..\\data\""));
    assert!(script.contains("tar.exe -xzf $stagingArchive"));
}

#[test]
fn windows_validate_script_uses_current_file_layout() {
    let script = windows_validate_script("windows", "C:/Users/me/AppData/Local/Alera/runtime");
    assert!(script.contains("current.txt"));
    assert!(script.contains("Join-Path $current 'alera.exe'"));
    assert!(!script.contains("current/alera.exe"));
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
            "windows",
            r"C:\Users\leyni\AppData\Local\Alera\runtime",
            &["staging", "job", "archive.tar.gz"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging/job/archive.tar.gz"
    );
    assert_eq!(
        remote_join(
            "windows",
            "C:/Users/leyni/AppData/Local/Alera/runtime",
            &["staging", "job"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging/job"
    );
    assert_eq!(
        remote_join(
            "windows",
            "/C:/Users/leyni/AppData/Local/Alera/runtime",
            &["staging"],
        ),
        "/C:/Users/leyni/AppData/Local/Alera/runtime/staging"
    );
    assert_eq!(
        remote_join("linux", "/home/me/.alera/sidecar", &["staging", "job"]),
        "/home/me/.alera/sidecar/staging/job"
    );
}

#[test]
fn posix_resolve_install_dir_script_escapes_tilde_prefix_strip() {
    let script = posix_resolve_install_dir_script("~/.alera/sidecar");
    assert!(
        script.contains(r#"${install_dir#"~/"}"#),
        "script must quote the ~/ strip pattern: {script}"
    );
    assert!(
        !script.contains("${install_dir#~/}"),
        "unquoted #~/ tilde-expands on dash/macOS sh: {script}"
    );
    assert!(script.contains(r#"mkdir -p "$install_dir""#));
}

#[test]
fn posix_resolve_install_dir_script_resolves_tilde_under_dash() {
    let script = posix_resolve_install_dir_script("~/.alera/sidecar-runtime");
    // Drive only the case/strip logic under dash with a fake HOME.
    let probe = r#"
HOME=/tmp/alera-tilde-home-666
install_dir='~/.alera/sidecar-runtime'
case "$install_dir" in
  "~") install_dir="$HOME" ;;
  "~/"*) install_dir="$HOME/${install_dir#"~/"}" ;;
esac
printf '%s\n' "$install_dir"
"#;
    let output = alera_core::child_process::windowless_command("dash")
        .arg("-c")
        .arg(probe)
        .output()
        .expect("dash should be available to run the regression probe");
    assert!(
        output.status.success(),
        "dash probe failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let resolved = String::from_utf8_lossy(&output.stdout).trim().to_string();
    assert_eq!(resolved, "/tmp/alera-tilde-home-666/.alera/sidecar-runtime");
    assert!(
        !resolved.contains("/~/"),
        "resolved path must not contain a literal /~ segment: {resolved}"
    );
    // Keep the generated remote script aligned with the probe pattern.
    assert!(script.contains(r#"${install_dir#"~/"}"#));
}

#[test]
fn posix_resolve_install_dir_script_resolves_tilde_under_sh() {
    let probe = r#"
HOME=/tmp/alera-tilde-home-666
install_dir='~/.alera/sidecar'
case "$install_dir" in
  "~") install_dir="$HOME" ;;
  "~/"*) install_dir="$HOME/${install_dir#"~/"}" ;;
esac
printf '%s\n' "$install_dir"
"#;
    let output = alera_core::child_process::windowless_command("sh")
        .arg("-c")
        .arg(probe)
        .output()
        .expect("sh should be available to run the regression probe");
    assert!(
        output.status.success(),
        "sh probe failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let resolved = String::from_utf8_lossy(&output.stdout).trim().to_string();
    assert_eq!(resolved, "/tmp/alera-tilde-home-666/.alera/sidecar");
    assert!(!resolved.contains("/~/"));
}

#[test]
fn prepare_rewrites_linux_home_expansion_to_tilde_for_macos() {
    let resolved = prepare_remote_install_dir(
        "macos",
        "/home/leynier/.alera/audit-637-home-probe",
        Some("/home/leynier"),
    )
    .unwrap();
    assert_eq!(resolved, "~/.alera/audit-637-home-probe");
}

#[test]
fn prepare_rewrites_explicit_linux_home_to_users_on_macos() {
    let resolved = prepare_remote_install_dir(
        "macos",
        "/home/leynier/.alera/audit-637-home-probe",
        Some("/var/empty"),
    )
    .unwrap();
    assert_eq!(resolved, "/Users/leynier/.alera/audit-637-home-probe");
}

#[test]
fn prepare_rejects_linux_home_root_on_macos() {
    let error = prepare_remote_install_dir("macos", "/home", Some("/var/empty"))
        .unwrap_err()
        .to_string();
    assert!(error.contains("autofs"), "{error}");
    assert!(error.contains("/Users"), "{error}");
    assert!(!error.contains("<user>"), "{error}");
}

#[test]
fn prepare_does_not_treat_homebrew_as_linux_home_on_macos() {
    let resolved =
        prepare_remote_install_dir("macos", "/homebrew/opt/alera", Some("/home/leynier")).unwrap();
    assert_eq!(resolved, "/homebrew/opt/alera");
}

#[test]
fn prepare_keeps_quoted_tilde_install_dir_on_macos() {
    let resolved =
        prepare_remote_install_dir("macos", "~/.alera/sidecar", Some("/home/leynier")).unwrap();
    assert_eq!(resolved, "~/.alera/sidecar");
}

#[test]
fn prepare_folds_macos_home_expansion_to_tilde_for_linux() {
    let resolved = prepare_remote_install_dir(
        "linux",
        "/Users/leynier/.alera/sidecar",
        Some("/Users/leynier"),
    )
    .unwrap();
    assert_eq!(resolved, "~/.alera/sidecar");
}

#[test]
fn prepare_rejects_linux_home_on_windows() {
    let error = prepare_remote_install_dir(
        "windows",
        "/home/leynier/.alera/sidecar",
        Some("/home/leynier"),
    )
    .unwrap_err()
    .to_string();
    assert!(error.contains("not valid on Windows"), "{error}");
    assert!(error.contains("/home/leynier/.alera/sidecar"), "{error}");
}

#[test]
fn redact_error_keeps_real_linux_home_path() {
    let redacted = redact_error("ssh failed: mkdir: /home/leynier: Operation not supported");
    assert!(redacted.contains("/home/leynier"), "{redacted}");
    assert!(!redacted.contains("/home/<user>"), "{redacted}");
    assert!(!redacted.contains("<user>"), "{redacted}");
    assert!(!redacted.contains("<host>"), "{redacted}");
}

#[test]
fn redact_error_redacts_credentials_only() {
    let redacted = redact_error(
        "ssh failed: mkdir: /home/leynier/.alera token=super-secret-value sk-secretvalue",
    );
    assert!(redacted.contains("/home/leynier/.alera"), "{redacted}");
    assert!(!redacted.contains("super-secret-value"), "{redacted}");
    assert!(!redacted.contains("sk-secretvalue"), "{redacted}");
    assert!(redacted.contains("[redacted]"), "{redacted}");
}

#[test]
fn truncate_error_handles_multibyte_text() {
    let message = "falló ".repeat(200);
    let truncated = truncate_error(&message);

    assert!(truncated.ends_with("..."));
    assert_eq!(truncated.trim_end_matches("...").chars().count(), 600);
}

#[test]
fn password_auth_is_rejected_for_new_targets_and_allowed_for_legacy_resave() {
    assert!(reject_password_ssh_bootstrap_auth(SshAuthKind::Agent).is_ok());
    assert!(reject_password_ssh_bootstrap_auth(SshAuthKind::Key).is_ok());
    assert_eq!(
        reject_password_ssh_bootstrap_auth(SshAuthKind::Password)
            .unwrap_err()
            .to_string(),
        SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED
    );
    assert!(
        reject_new_password_ssh_target(SshAuthKind::Password, Some(SshAuthKind::Password)).is_ok()
    );
    assert_eq!(
        reject_new_password_ssh_target(SshAuthKind::Password, None)
            .unwrap_err()
            .to_string(),
        SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED
    );
    assert_eq!(
        reject_new_password_ssh_target(SshAuthKind::Password, Some(SshAuthKind::Agent))
            .unwrap_err()
            .to_string(),
        SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED
    );
    assert!(reject_new_password_ssh_target(SshAuthKind::Agent, None).is_ok());
}

fn password_ssh_target(id: &str) -> SshTarget {
    let now = chrono::Utc::now();
    SshTarget {
        id: id.to_string(),
        alias: id.to_string(),
        host: "192.168.1.66".to_string(),
        port: 22,
        username: "alera".to_string(),
        platform: None,
        arch: None,
        auth_kind: SshAuthKind::Password,
        created_at: now,
        updated_at: now,
        last_status: None,
        install_dir: None,
        runtime_version: None,
        runtime_platform: None,
        runtime_arch: None,
        bootstrap_status: SshBootstrapStatus::NotInstalled,
        last_bootstrap_at: None,
        last_checked_at: None,
        last_error: None,
    }
}

fn empty_plan_request(target_id: &str) -> SshTargetBootstrapRequest {
    SshTargetBootstrapRequest {
        target_id: target_id.to_string(),
        channel: None,
        version: None,
        install_dir: None,
        platform: None,
        arch: None,
        archive_url: None,
        archive_path: None,
        artifact_path: None,
        manifest_public_key: None,
    }
}

#[tokio::test]
async fn build_ssh_bootstrap_plan_rejects_password_target() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let target = password_ssh_target("audit-674-pass");
    store.upsert_ssh_target(target.clone()).await.unwrap();

    let error = build_ssh_bootstrap_plan(&store, &empty_plan_request(&target.id))
        .await
        .unwrap_err();
    assert_eq!(error.to_string(), SSH_PASSWORD_BOOTSTRAP_UNSUPPORTED);
}

#[tokio::test]
async fn build_ssh_bootstrap_plan_rewrites_linux_home_on_macos_target() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let mut target = password_ssh_target("audit-675-macos");
    target.auth_kind = SshAuthKind::Agent;
    target.platform = Some("macos".to_string());
    target.username = "leynier".to_string();
    store.upsert_ssh_target(target.clone()).await.unwrap();

    let mut request = empty_plan_request(&target.id);
    request.install_dir = Some("/home/leynier/.alera/audit-637-home-probe".to_string());
    let plan = build_ssh_bootstrap_plan(&store, &request).await.unwrap();
    assert!(
        plan.install_dir == "~/.alera/audit-637-home-probe"
            || plan.install_dir == "/Users/leynier/.alera/audit-637-home-probe",
        "plan install_dir should be remote-home relative or /Users, got {}",
        plan.install_dir
    );
    assert!(
        !plan.install_dir.starts_with("/home/"),
        "Linux /home must not reach a macOS target: {}",
        plan.install_dir
    );
}
