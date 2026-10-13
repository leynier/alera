use serde_json::{json, Value};

use super::*;

#[test]
fn posix_commands_expand_the_install_dir_and_pick_the_profile() {
    let bare = sidecar_command(
        RemoteShell::Posix,
        "~/sidecar's",
        "project inspect-checkout --path '/srv/app'",
        SidecarProfile::Bare,
    );
    assert!(bare.starts_with("set -eu\ninstall='~/sidecar'\"'\"'s'\n"));
    assert!(bare.contains(r#"install="$HOME/${install#"~/"}""#));
    assert!(bare
        .ends_with("exec \"$install/current/alera\" project inspect-checkout --path '/srv/app'\n"));
    assert!(!bare.contains("--state-dir"));

    let owner = sidecar_command(
        RemoteShell::Posix,
        "/opt/sidecar",
        "project owner-terminal",
        SidecarProfile::DataStateDir,
    );
    assert!(owner.ends_with(
        "exec \"$install/current/alera\" project owner-terminal --state-dir \"$install/data\"\n"
    ));
}

#[test]
fn windows_commands_read_current_txt_and_keep_the_exit_status() {
    for profile in [SidecarProfile::Bare, SidecarProfile::DataStateDir] {
        let script = sidecar_command(
            RemoteShell::Windows,
            r"%LOCALAPPDATA%\Alera's\runtime",
            "project inspect-checkout",
            profile,
        );
        assert!(script.contains(
            r"$install = [Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Alera''s\runtime')"
        ));
        assert!(script.contains("Join-Path $install 'current.txt'"));
        assert!(script.ends_with("\nexit $LASTEXITCODE\n"));
        match profile {
            SidecarProfile::Bare => assert!(!script.contains("--state-dir")),
            SidecarProfile::DataStateDir => {
                assert!(script.contains("$state = Join-Path $install 'data'\n"));
                assert!(script.contains("project inspect-checkout --state-dir $state\n"));
            }
        }
    }
}

#[test]
fn a_single_line_receipt_parses() {
    let value: Value = parse_last_json_line("{\"version\":1}\n").unwrap();
    assert_eq!(value, json!({"version": 1}));
}

#[test]
fn profile_noise_before_the_receipt_is_skipped() {
    let pretty = serde_json::to_string_pretty(&json!({
        "version": 1,
        "path": "/srv/app",
        "nested": {"items": [1, 2]},
    }))
    .unwrap();
    let stdout = format!("Welcome to build-box\n[motd] {{not json}}\n{pretty}\n");
    let value: Value = parse_last_json_line(&stdout).unwrap();
    assert_eq!(value["path"], "/srv/app");
    assert_eq!(value["nested"]["items"], json!([1, 2]));

    let single = "nvm: using node 22\n{\"version\":1,\"path\":\"/srv/app\"}\n";
    let value: Value = parse_last_json_line(single).unwrap();
    assert_eq!(value["version"], 1);
}

#[test]
fn the_last_receipt_wins_and_trailing_noise_falls_back_to_lines() {
    let value: Value = parse_last_json_line("{\"n\":1}\n{\"n\":2}\n").unwrap();
    assert_eq!(value["n"], 2);
    let value: Value = parse_last_json_line("{\"n\":3}\nlogout\n").unwrap();
    assert_eq!(value["n"], 3);
}

#[test]
fn output_without_json_reports_a_parse_error() {
    assert!(parse_last_json_line::<Value>("bash: alera: command not found\n").is_err());
    assert!(parse_last_json_line::<Value>("").is_err());
}
