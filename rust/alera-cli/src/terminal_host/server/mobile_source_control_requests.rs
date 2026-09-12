use std::fs;
use std::io::Read;
use std::path::Path;

use alera_core::git_cli::git_in_dir;
use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_source_control_snapshot::git_status_snapshot;
use super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::requests::{optional_string_key, require_string_key};

const MAX_DIFF_BYTES: usize = 400 * 1024;
const MAX_DIFF_LINES: usize = 2000;
const MAX_UNTRACKED_BYTES: u64 = 5 * 1024 * 1024;

pub(super) async fn mobile_git_status(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let root = workspace.path.clone();
    spawn_blocking_workspace("Git status", move || git_status_snapshot(&root)).await
}

pub(super) async fn mobile_git_diff(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let path = require_string_key(payload, "path")?;
    let area = optional_string_key(payload, "area").unwrap_or_else(|| "unstaged".to_string());
    let root = workspace.path.clone();
    spawn_blocking_workspace("Git diff", move || git_diff_snapshot(&root, &path, &area)).await
}

fn git_diff_snapshot(root: &str, path: &str, area: &str) -> HostResult<Value> {
    let area = match area {
        "staged" | "unstaged" | "untracked" => area,
        _ => "unstaged",
    };
    if area == "untracked" {
        return untracked_diff(root, path);
    }
    let contained = alera_core::workspace_files::contained_workspace_relative_path(root, path)
        .map_err(|error| HostError::state(error.to_string()))?;
    let relative_path = contained.relative_path;
    let args: Vec<&str> = if area == "staged" {
        vec!["diff", "--cached", "--", &relative_path]
    } else {
        vec!["diff", "--", &relative_path]
    };
    let output =
        git_in_dir(Path::new(root), &args).map_err(|error| HostError::state(error.message))?;
    Ok(json!({
        "path": relative_path,
        "area": area,
        "isBinary": diff_is_binary(&output),
        "truncated": output.len() > MAX_DIFF_BYTES,
        "lines": parse_unified_diff(&output),
    }))
}

fn diff_is_binary(output: &str) -> bool {
    output.contains("Binary files ") || output.contains("Binary file ")
}

fn untracked_diff(root: &str, path: &str) -> HostResult<Value> {
    // Never Path::join the client path onto the workspace root: an absolute
    // path replaces the root (`root.join("/etc/passwd")` is `/etc/passwd`).
    let contained = alera_core::workspace_files::contained_workspace_relative_path(root, path)
        .map_err(|error| HostError::state(error.to_string()))?;
    let relative_path = contained.relative_path;
    let canonical_root = fs::canonicalize(root)
        .map_err(|error| HostError::state(format!("Workspace root is unavailable: {error}")))?;
    if let Ok(canonical) = fs::canonicalize(&contained.absolute_path) {
        if !canonical.starts_with(&canonical_root) {
            return Err(HostError::state("Diff path is outside the workspace."));
        }
    }
    let (mut file, _) =
        alera_core::workspace_files::open_workspace_file_nofollow(root, &relative_path)
            .map_err(|error| HostError::state(format!("Untracked file is unavailable: {error}")))?;
    let metadata = file
        .metadata()
        .map_err(|error| HostError::state(format!("Untracked file is unavailable: {error}")))?;
    if metadata.len() > MAX_UNTRACKED_BYTES {
        return Ok(json!({
            "path": relative_path,
            "area": "untracked",
            "isBinary": false,
            "truncated": true,
            "lines": [{
                "kind": "header",
                "text": "Untracked file is too large to preview.",
            }],
        }));
    }
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)
        .map_err(|error| HostError::state(format!("Untracked file is unavailable: {error}")))?;
    if bytes.contains(&0) || std::str::from_utf8(&bytes).is_err() {
        return Ok(json!({
            "path": relative_path,
            "area": "untracked",
            "isBinary": true,
            "truncated": false,
            "lines": [{
                "kind": "header",
                "text": "Binary file",
            }],
        }));
    }
    let text = String::from_utf8_lossy(&bytes);
    let mut lines = vec![json!({"kind": "header", "text": format!("+++ {relative_path}")})];
    for line in text.lines().take(MAX_DIFF_LINES) {
        lines.push(json!({"kind": "addition", "text": format!("+{line}")}));
    }
    Ok(json!({
        "path": relative_path,
        "area": "untracked",
        "isBinary": false,
        "truncated": text.lines().count() > MAX_DIFF_LINES,
        "lines": lines,
    }))
}

fn parse_unified_diff(output: &str) -> Vec<Value> {
    let mut lines = Vec::new();
    let truncated = output.len() > MAX_DIFF_BYTES;
    let body = if truncated {
        &output[..MAX_DIFF_BYTES]
    } else {
        output
    };
    for line in body.lines().take(MAX_DIFF_LINES) {
        let kind = if line.starts_with("+++") || line.starts_with("---") {
            "header"
        } else if line.starts_with("@@") {
            "hunk"
        } else if line.starts_with('+') {
            "addition"
        } else if line.starts_with('-') {
            "deletion"
        } else {
            "context"
        };
        lines.push(json!({"kind": kind, "text": line}));
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::child_process::windowless_command;

    #[test]
    fn reports_untracked_and_modified_files() {
        let workspace = tempfile::tempdir().unwrap();
        git2::Repository::init(workspace.path()).unwrap();
        fs::write(workspace.path().join("tracked.txt"), "one\n").unwrap();
        run_git(workspace.path(), &["add", "tracked.txt"]);
        run_git(
            workspace.path(),
            &[
                "-c",
                "user.name=Alera",
                "-c",
                "user.email=alera@example.com",
                "commit",
                "-m",
                "init",
            ],
        );
        fs::write(workspace.path().join("tracked.txt"), "two\n").unwrap();
        fs::write(workspace.path().join("new.txt"), "fresh\n").unwrap();

        let snapshot = git_status_snapshot(&workspace.path().to_string_lossy()).unwrap();
        assert_eq!(snapshot["isRepository"], true);
        let entries = snapshot["entries"].as_array().unwrap();
        let paths = entries
            .iter()
            .map(|entry| {
                (
                    entry["path"].as_str().unwrap().to_string(),
                    entry["area"].as_str().unwrap().to_string(),
                )
            })
            .collect::<Vec<_>>();
        assert!(paths.contains(&("tracked.txt".into(), "unstaged".into())));
        assert!(paths.contains(&("new.txt".into(), "untracked".into())));
    }

    #[test]
    fn diff_allows_in_tree_relative_path() {
        let workspace = tempfile::tempdir().unwrap();
        git2::Repository::init(workspace.path()).unwrap();
        fs::write(workspace.path().join("tracked.txt"), "one\n").unwrap();
        run_git(workspace.path(), &["add", "tracked.txt"]);
        run_git(
            workspace.path(),
            &[
                "-c",
                "user.name=Alera",
                "-c",
                "user.email=alera@example.com",
                "commit",
                "-m",
                "init",
            ],
        );
        fs::write(workspace.path().join("tracked.txt"), "two\n").unwrap();
        let snapshot = git_diff_snapshot(
            &workspace.path().to_string_lossy(),
            "tracked.txt",
            "unstaged",
        )
        .unwrap();
        assert_eq!(snapshot["path"], "tracked.txt");
        assert_eq!(snapshot["isBinary"], false);
        let lines = snapshot["lines"].as_array().unwrap();
        assert!(lines
            .iter()
            .any(|line| line["text"].as_str() == Some("+two")));
    }

    #[test]
    fn diff_rejects_absolute_paths() {
        let workspace = tempfile::tempdir().unwrap();
        let root = workspace.path().to_string_lossy();
        for area in ["unstaged", "untracked"] {
            assert!(
                git_diff_snapshot(&root, "/etc/passwd", area).is_err(),
                "absolute path must be rejected for {area}",
            );
            assert!(
                git_diff_snapshot(&root, "../secret", area).is_err(),
                "parent path must be rejected for {area}",
            );
        }
    }

    #[test]
    fn untracked_diff_allows_in_tree_relative_path() {
        let workspace = tempfile::tempdir().unwrap();
        git2::Repository::init(workspace.path()).unwrap();
        fs::write(workspace.path().join("new.txt"), "fresh\n").unwrap();
        let snapshot =
            git_diff_snapshot(&workspace.path().to_string_lossy(), "new.txt", "untracked").unwrap();
        assert_eq!(snapshot["path"], "new.txt");
        assert_eq!(snapshot["isBinary"], false);
        let lines = snapshot["lines"].as_array().unwrap();
        assert!(lines
            .iter()
            .any(|line| line["text"].as_str() == Some("+fresh")));
    }

    #[cfg(unix)]
    #[test]
    fn diff_rejects_symlink_escape() {
        let workspace = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let secret = outside.path().join("secret.txt");
        fs::write(&secret, "secret\n").unwrap();
        std::os::unix::fs::symlink(&secret, workspace.path().join("link.txt")).unwrap();
        assert!(
            git_diff_snapshot(&workspace.path().to_string_lossy(), "link.txt", "untracked")
                .is_err()
        );
        assert!(
            git_diff_snapshot(&workspace.path().to_string_lossy(), "link.txt", "unstaged").is_err()
        );
    }

    #[test]
    fn binary_marker_does_not_match_plain_differ_lines() {
        assert!(!diff_is_binary("diff --git a/readme.md b/readme.md\n--- a/readme.md\n+++ b/readme.md\n@@ -1 +1 @@\n-hello\n+hello there\n"));
        assert!(!diff_is_binary("files a/foo and b/foo differ\n"));
        assert!(diff_is_binary(
            "Binary files a/logo.png and b/logo.png differ\n"
        ));
        assert!(diff_is_binary("Binary file logo.png differs\n"));
    }

    fn run_git(path: &Path, args: &[&str]) {
        let status = windowless_command("git")
            .args(args)
            .current_dir(path)
            .status()
            .unwrap();
        assert!(status.success(), "git {args:?} failed");
    }
}
