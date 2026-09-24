//! The sidecar binary cargo builds and xtask stages into a bundle.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;

const CLI_TARGET_NAME: &str = "alera";

pub fn cli_executable_name() -> &'static str {
    if cfg!(windows) {
        "alera.exe"
    } else {
        "alera"
    }
}

pub fn cargo_build_arguments(release: bool) -> Vec<String> {
    let mut args = vec![
        "build".to_string(),
        "--locked".to_string(),
        "-p".to_string(),
        "alera-cli".to_string(),
        "--message-format=json-render-diagnostics".to_string(),
    ];
    if release {
        args.push("--release".to_string());
    }
    args
}

pub fn built_cli_executable(cargo_stdout: &str) -> Option<PathBuf> {
    let mut executable = None;
    for line in cargo_stdout.lines() {
        let Ok(message) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        if message.get("reason").and_then(serde_json::Value::as_str) != Some("compiler-artifact") {
            continue;
        }
        let Some(target) = message.get("target") else {
            continue;
        };
        if target.get("name").and_then(serde_json::Value::as_str) != Some(CLI_TARGET_NAME) {
            continue;
        }
        let is_bin = target
            .get("kind")
            .and_then(serde_json::Value::as_array)
            .is_some_and(|kinds| kinds.iter().any(|kind| kind.as_str() == Some("bin")));
        if !is_bin {
            continue;
        }
        let Some(path) = message
            .get("executable")
            .and_then(serde_json::Value::as_str)
        else {
            continue;
        };
        executable = Some(PathBuf::from(path));
    }
    executable
}

pub fn stage_cli_binary(source: &Path, destination_dir: &Path) -> Result<()> {
    fs::create_dir_all(destination_dir)?;
    let destination = destination_dir.join(cli_executable_name());
    let staged = destination.with_extension(format!(
        "stage-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_micros())
            .unwrap_or(0)
    ));
    let stage_result = (|| -> Result<()> {
        fs::copy(source, &staged)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = fs::metadata(&staged)?.permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(&staged, permissions)?;
        }
        #[cfg(windows)]
        if destination.exists() {
            fs::remove_file(&destination)?;
        }
        fs::rename(&staged, &destination)?;
        Ok(())
    })();
    if staged.exists() {
        let _ = fs::remove_file(&staged);
    }
    stage_result?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn compiler_artifact(name: &str, kind: &[&str], executable: Option<&str>) -> String {
        serde_json::json!({
            "reason": "compiler-artifact",
            "target": { "name": name, "kind": kind },
            "executable": executable,
        })
        .to_string()
    }

    #[test]
    fn built_cli_executable_reads_the_bin_artifact() {
        let stdout = [
            serde_json::json!({
                "reason": "compiler-artifact",
                "target": { "name": "other", "kind": ["lib"] },
                "executable": null,
            })
            .to_string(),
            serde_json::json!({
                "reason": "build-script-executed",
                "package_id": "alera-cli",
            })
            .to_string(),
            compiler_artifact("alera", &["bin"], Some("/tmp/t/release/alera")),
            "not json".to_string(),
            serde_json::json!({
                "reason": "build-finished",
                "success": true,
            })
            .to_string(),
        ]
        .join("\n");
        assert_eq!(
            built_cli_executable(&stdout),
            Some(PathBuf::from("/tmp/t/release/alera"))
        );
    }

    #[test]
    fn built_cli_executable_reads_windows_paths() {
        let line = serde_json::json!({
            "reason": "compiler-artifact",
            "target": { "name": "alera", "kind": ["bin"] },
            "executable": r"C:\c\n\release\alera.exe",
        })
        .to_string();
        assert_eq!(
            built_cli_executable(&line),
            Some(PathBuf::from(r"C:\c\n\release\alera.exe"))
        );
    }

    #[test]
    fn built_cli_executable_accepts_fresh_artifacts() {
        let mut message = serde_json::json!({
            "reason": "compiler-artifact",
            "target": { "name": "alera", "kind": ["bin"] },
            "executable": "/tmp/t/debug/alera",
        });
        message["fresh"] = serde_json::json!(true);
        assert_eq!(
            built_cli_executable(&message.to_string()),
            Some(PathBuf::from("/tmp/t/debug/alera"))
        );
    }

    #[test]
    fn built_cli_executable_ignores_other_targets() {
        let stdout = [
            compiler_artifact("alera-xtask", &["bin"], Some("/tmp/t/debug/alera-xtask")),
            compiler_artifact("alera", &["lib"], None),
        ]
        .join("\n");
        assert_eq!(built_cli_executable(&stdout), None);
        assert_eq!(built_cli_executable(""), None);
    }

    #[test]
    fn cargo_build_arguments_request_json_messages() {
        let debug_args = cargo_build_arguments(false);
        assert!(debug_args.iter().any(|arg| arg == "--locked"));
        assert!(debug_args
            .windows(2)
            .any(|pair| { pair[0] == "-p" && pair[1] == "alera-cli" }));
        assert!(debug_args
            .iter()
            .any(|arg| arg == "--message-format=json-render-diagnostics"));
        assert!(!debug_args.iter().any(|arg| arg == "--release"));

        let release_args = cargo_build_arguments(true);
        assert!(release_args.iter().any(|arg| arg == "--locked"));
        assert!(release_args
            .windows(2)
            .any(|pair| { pair[0] == "-p" && pair[1] == "alera-cli" }));
        assert!(release_args
            .iter()
            .any(|arg| arg == "--message-format=json-render-diagnostics"));
        assert!(release_args.iter().any(|arg| arg == "--release"));
    }

    #[test]
    fn stage_cli_binary_replaces_destination() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source-bin");
        fs::write(&source, b"new").unwrap();
        let destination_dir = root.path().join("bundle");
        fs::create_dir(&destination_dir).unwrap();
        let destination = destination_dir.join(cli_executable_name());
        fs::write(&destination, b"old").unwrap();

        stage_cli_binary(&source, &destination_dir).unwrap();

        assert_eq!(fs::read(&destination).unwrap(), b"new");
        let entries = fs::read_dir(&destination_dir).unwrap().count();
        assert_eq!(entries, 1);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&destination).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o755);
        }

        let nested = root.path().join("missing").join("nested");
        stage_cli_binary(&source, &nested).unwrap();
        assert_eq!(
            fs::read(nested.join(cli_executable_name())).unwrap(),
            b"new"
        );
    }
}
