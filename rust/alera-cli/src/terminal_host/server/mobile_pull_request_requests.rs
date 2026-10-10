//! The pull request snapshot verb and the `gh` reads GitHub's provider uses.

use std::collections::BTreeMap;
use std::process::Stdio;
use std::time::Duration;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::time::timeout;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;

const GH_TIMEOUT: Duration = Duration::from_secs(45);
const GH_REVIEW_FIELDS: &str =
    "number,title,state,url,createdAt,isDraft,mergeable,headRefName,baseRefName,headRefOid,author";
const GH_CHECK_FIELDS: &str = "name,state,bucket,link";

pub(super) async fn snapshot_mobile_pull_request(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let mut snapshot = super::pull_request_forges::load_snapshot(runtime_store, &workspace).await?;
    super::mobile_pull_request_snapshot_extras::decorate_snapshot(
        runtime_store,
        &workspace,
        payload,
        &mut snapshot,
    )
    .await;
    Ok(snapshot)
}

pub(super) async fn view_review(
    repo_path: &str,
    slug: &str,
    number: i64,
) -> HostResult<Option<Value>> {
    let number = number.to_string();
    let (code, stdout, stderr) = run_gh(
        repo_path,
        &[
            "pr",
            "view",
            &number,
            "--repo",
            slug,
            "--json",
            GH_REVIEW_FIELDS,
        ],
    )
    .await?;
    if code != 0 {
        if stderr.to_ascii_lowercase().contains("could not find")
            || stderr.to_ascii_lowercase().contains("not found")
        {
            return Ok(None);
        }
        return Err(HostError::state(if stderr.is_empty() {
            stdout
        } else {
            stderr
        }));
    }
    parse_review_object(&stdout)
}

pub(super) async fn list_review_for_branch(
    repo_path: &str,
    slug: &str,
    branch: &str,
) -> HostResult<Option<Value>> {
    let (code, stdout, stderr) = run_gh(
        repo_path,
        &[
            "pr",
            "list",
            "--repo",
            slug,
            "--head",
            branch,
            "--state",
            "open",
            "--limit",
            "20",
            "--json",
            GH_REVIEW_FIELDS,
        ],
    )
    .await?;
    if code != 0 {
        return Err(HostError::state(if stderr.is_empty() {
            stdout
        } else {
            stderr
        }));
    }
    let parsed: Value = serde_json::from_str(&stdout)
        .map_err(|error| HostError::state(format!("Could not parse gh output: {error}")))?;
    let Some(items) = parsed.as_array() else {
        return Ok(None);
    };
    Ok(items.first().cloned().and_then(normalize_review))
}

pub(super) async fn load_checks(repo_path: &str, slug: &str, number: i64) -> Vec<Value> {
    let number = number.to_string();
    let Ok((_, stdout, _)) = run_gh(
        repo_path,
        &[
            "pr",
            "checks",
            &number,
            "--repo",
            slug,
            "--json",
            GH_CHECK_FIELDS,
        ],
    )
    .await
    else {
        return Vec::new();
    };
    serde_json::from_str::<Value>(&stdout)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .map(|entry| {
            json!({
                "name": entry.get("name").and_then(Value::as_str).unwrap_or("check"),
                "state": entry.get("state").and_then(Value::as_str).unwrap_or(""),
                "bucket": entry.get("bucket").and_then(Value::as_str).unwrap_or(""),
                "url": entry.get("link").and_then(Value::as_str),
            })
        })
        .collect()
}

fn parse_review_object(stdout: &str) -> HostResult<Option<Value>> {
    let parsed: Value = serde_json::from_str(stdout)
        .map_err(|error| HostError::state(format!("Could not parse gh output: {error}")))?;
    Ok(normalize_review(parsed))
}

fn normalize_review(value: Value) -> Option<Value> {
    let object = value.as_object()?;
    Some(json!({
        "number": object.get("number").and_then(Value::as_i64).unwrap_or(0),
        "title": object.get("title").and_then(Value::as_str).unwrap_or(""),
        "state": object.get("state").and_then(Value::as_str).unwrap_or("OPEN"),
        "url": object.get("url").and_then(Value::as_str).unwrap_or(""),
        "isDraft": object.get("isDraft").and_then(Value::as_bool).unwrap_or(false),
        "author": object
            .get("author")
            .and_then(|author| author.get("login"))
            .and_then(Value::as_str),
        "headRefName": object.get("headRefName").and_then(Value::as_str),
        "baseRefName": object.get("baseRefName").and_then(Value::as_str),
        "createdAt": object.get("createdAt").and_then(Value::as_str),
        "mergeable": object.get("mergeable").and_then(Value::as_str),
        "headSha": object.get("headRefOid").and_then(Value::as_str),
    }))
}

pub(super) async fn run_gh(repo_path: &str, args: &[&str]) -> HostResult<(i32, String, String)> {
    let mut command = alera_core::child_process::windowless_async_command("gh");
    command
        .args(args)
        .current_dir(repo_path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    crate::login_shell_environment::apply_login_shell_environment(&mut command, &BTreeMap::new())
        .await;
    let output = github_cli_output(command, GH_TIMEOUT).await?;
    Ok((
        output.status.code().unwrap_or(1),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    ))
}

async fn github_cli_output(
    mut command: tokio::process::Command,
    deadline: Duration,
) -> HostResult<std::process::Output> {
    command.kill_on_drop(true);
    timeout(deadline, command.output())
        .await
        .map_err(|_| {
            HostError::state(
                "The GitHub CLI timed out. Verify the pull request before retrying a write.",
            )
        })?
        .map_err(|error| HostError::state(format!("failed to run gh: {error}")))
}

#[cfg(all(test, unix))]
mod process_lifetime_tests {
    use super::*;

    #[tokio::test]
    async fn github_timeout_prevents_a_delayed_process_write() {
        let root = tempfile::tempdir().unwrap();
        let marker = root.path().join("late-write");
        let mut command = alera_core::child_process::windowless_async_command("/bin/sh");
        command
            .args(["-c", "sleep 2; printf late > \"$1\"", "fixture"])
            .arg(&marker)
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let error = github_cli_output(command, Duration::from_millis(50))
            .await
            .unwrap_err();
        assert!(error.to_string().contains("timed out"));
        tokio::time::sleep(Duration::from_millis(2200)).await;
        assert!(!marker.exists(), "timed-out process continued writing");
    }
}

#[cfg(test)]
mod normalize_review_tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn maps_head_ref_oid_to_head_sha() {
        let review = normalize_review(json!({
            "number": 42,
            "title": "feat",
            "state": "OPEN",
            "url": "https://github.com/leynier/alera/pull/42",
            "headRefOid": "abc123",
            "headRefName": "feat",
            "baseRefName": "main",
        }))
        .unwrap();
        assert_eq!(review["headSha"], "abc123");
        assert_eq!(review["number"], 42);
    }
}
