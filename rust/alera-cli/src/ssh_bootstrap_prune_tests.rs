use super::*;

#[test]
fn posix_prune_keeps_current_and_the_named_version() {
    let script = prune_versions_script(
        RemoteShell::Posix,
        "~/.alera/sidecar",
        Some("1.5.0-linux-x64"),
    );
    assert!(script.starts_with("set -eu\n"), "{script}");
    assert!(script.contains("install='~/.alera/sidecar'"), "{script}");
    assert!(script.contains("keep='1.5.0-linux-x64'"), "{script}");
    assert!(script.contains("readlink \"$install/current\""), "{script}");
    assert!(script.contains("rm -rf -- \"$entry\""), "{script}");
    assert!(
        script.contains("exit 3"),
        "refuses without a version to keep"
    );
}

#[test]
fn windows_prune_keeps_current_txt_and_the_named_version() {
    let script = prune_versions_script(
        RemoteShell::Windows,
        "%LOCALAPPDATA%\\Alera\\runtime",
        Some("1.5.0-windows-x64"),
    );
    assert!(
        script.contains("ExpandEnvironmentVariables('%LOCALAPPDATA%\\Alera\\runtime')"),
        "{script}"
    );
    assert!(script.contains("current.txt"), "{script}");
    assert!(script.contains("$extra = '1.5.0-windows-x64'"), "{script}");
    assert!(script.contains("$keep -notcontains $_.Name"), "{script}");
    assert!(
        script.contains("throw 'no current runtime version to keep'"),
        "{script}"
    );
    assert!(!script.contains('\u{2014}'));

    let without_keep = prune_versions_script(RemoteShell::Windows, "C:\\it's", None);
    assert!(without_keep.contains("'C:\\it''s'"), "{without_keep}");
    assert!(without_keep.contains("$extra = ''"), "{without_keep}");
}

#[test]
fn reads_the_installed_cli_version_past_profile_noise() {
    let stdout =
        "Welcome to the lab\n{\n  \"cliVersion\": \"1.5.0\",\n  \"cliCommit\": \"abc\"\n}\n";
    assert_eq!(parse_installed_version(stdout).as_deref(), Some("1.5.0"));
    assert_eq!(parse_installed_version("not json"), None);
    assert_eq!(parse_installed_version("{\"cliVersion\": \"\"}"), None);
}

#[test]
fn version_script_targets_the_sidecar_data_profile() {
    let posix = installed_version_script(RemoteShell::Posix, "/opt/alera");
    assert!(
        posix.contains(
            "exec \"$install/current/alera\" version --json --runtime-dir \"$install/data\""
        ),
        "{posix}"
    );
    let windows = installed_version_script(RemoteShell::Windows, "C:\\alera");
    assert!(
        windows.contains("version --json --runtime-dir (Join-Path $install 'data')"),
        "{windows}"
    );
}

#[cfg(unix)]
mod posix_run {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::path::Path;

    fn layout(install: &Path, names: &[&str]) {
        for name in names {
            std::fs::create_dir_all(install.join("versions").join(name)).unwrap();
            std::fs::write(install.join("versions").join(name).join("alera"), "bin").unwrap();
        }
    }

    fn remaining(install: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(install.join("versions"))
            .unwrap()
            .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    fn run(install: &Path, keep: Option<&str>) -> std::process::Output {
        let script = prune_versions_script(RemoteShell::Posix, install.to_str().unwrap(), keep);
        alera_core::child_process::windowless_command("sh")
            .arg("-c")
            .arg(script)
            .output()
            .unwrap()
    }

    #[test]
    fn deletes_every_version_but_current_and_keep() {
        let dir = tempfile::tempdir().unwrap();
        let install = dir.path().join("sidecar dir");
        layout(
            &install,
            &["1.3.0-linux-x64", "1.4.0-linux-x64", "1.5.0-linux-x64"],
        );
        std::fs::create_dir_all(install.join("versions/.hidden")).unwrap();
        symlink(
            install.join("versions/1.5.0-linux-x64"),
            install.join("current"),
        )
        .unwrap();
        let output = run(&install, None);
        assert!(output.status.success(), "{output:?}");
        assert_eq!(remaining(&install), vec!["1.5.0-linux-x64"]);
        assert!(install.join("current/alera").exists());
    }

    #[test]
    fn a_relative_current_link_and_a_named_keep_both_survive() {
        let dir = tempfile::tempdir().unwrap();
        let install = dir.path().join("sidecar");
        layout(&install, &["old", "new", "staged"]);
        symlink("versions/new", install.join("current")).unwrap();
        let output = run(&install, Some("staged"));
        assert!(output.status.success(), "{output:?}");
        assert_eq!(remaining(&install), vec!["new", "staged"]);
    }

    #[test]
    fn refuses_to_delete_anything_without_a_version_to_keep() {
        let dir = tempfile::tempdir().unwrap();
        let install = dir.path().join("sidecar");
        layout(&install, &["old", "new"]);
        let output = run(&install, None);
        assert_eq!(output.status.code(), Some(3), "{output:?}");
        assert_eq!(remaining(&install), vec!["new", "old"]);
    }

    #[test]
    fn a_host_without_versions_has_nothing_to_prune() {
        let dir = tempfile::tempdir().unwrap();
        let output = run(dir.path(), None);
        assert!(output.status.success(), "{output:?}");
    }
}
