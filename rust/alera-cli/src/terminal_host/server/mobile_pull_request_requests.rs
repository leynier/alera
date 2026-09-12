use std::collections::BTreeMap;
use std::process::Stdio;
use std::time::Duration;

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::{json, Value};
use tokio::time::timeout;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_pull_request_identity::{
    detect_provider, parse_github_identity, remote_identity_json,
};
use super::mobile_pull_request_links::{dismissed_number, linked_number, suggested_review_json};
use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;

const GH_TIMEOUT: Duration = Duration::from_secs(45);
const GH_REVIEW_FIELDS: &str =
    "number,title,state,url,createdAt,isDraft,mergeable,headRefName,baseRefName,author";
const GH_CHECK_FIELDS: &str = "name,state,bucket,link";

pub(super) async fn snapshot_mobile_pull_request(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let mut snapshot = load_snapshot(runtime_store, &workspace).await?;
    super::mobile_pull_request_snapshot_extras::decorate_snapshot(
        runtime_store,
        &workspace,
        &mut snapshot,
    )
    .await;
    Ok(snapshot)
}

async fn load_snapshot(runtime_store: &RuntimeStore, workspace: &Workspace) -> HostResult<Value> {
    let linked = runtime_store
        .find_linked_review(&workspace.id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let repo_path = workspace.path.clone();
    let branch = tokio::task::spawn_blocking({
        let repo_path = repo_path.clone();
        move || core_git::current_branch(&repo_path)
    })
    .await
    .map_err(|error| HostError::state(format!("Could not read the current branch: {error}")))?
    .ok();
    let remote_url = tokio::task::spawn_blocking({
        let repo_path = repo_path.clone();
        move || core_git::repository_remote_url(&repo_path)
    })
    .await
    .map_err(|error| HostError::state(format!("Could not read the git remote: {error}")))?
    .ok()
    .flatten();

    let identity = remote_url.as_deref().and_then(parse_github_identity);
    let provider = identity
        .as_ref()
        .map(|_| "github")
        .or_else(|| detect_provider(remote_url.as_deref()));
    let linked_json = linked.as_ref().map(|review| {
        json!({
            "number": review.number,
            "url": review.url,
            "provider": review.provider,
            "dismissed": review.dismissed,
        })
    });

    if provider != Some("github") {
        return Ok(snapshot_envelope(
            branch,
            remote_url,
            provider,
            if provider.is_some() {
                "unsupported"
            } else {
                "undetectable"
            },
            linked_json,
            Value::Null,
            Some(
                if provider.is_some() {
                    "This hosting provider is available on desktop. Mobile v1 loads GitHub pull requests through gh."
                } else {
                    "No GitHub remote was detected for this workspace."
                }
                .to_string(),
            ),
        ));
    }
    let identity = identity.unwrap();

    let auth_status = match run_gh(
        &repo_path,
        &["auth", "status", "--hostname", &identity.host],
    )
    .await
    {
        Ok((0, _, _)) => "authenticated",
        Ok(_) => "notAuthenticated",
        Err(error) if looks_like_missing_cli(&error) => "cliMissing",
        Err(error) => {
            return Ok(snapshot_envelope(
                branch,
                remote_url,
                Some("github"),
                "cliMissing",
                linked_json,
                Value::Null,
                Some(error.wire_message()),
            ));
        }
    };
    if auth_status != "authenticated" {
        return Ok(snapshot_envelope(
            branch,
            remote_url,
            Some("github"),
            auth_status,
            linked_json,
            Value::Null,
            Some(
                match auth_status {
                    "cliMissing" => {
                        "Install and authenticate the GitHub CLI (gh) on the paired computer."
                    }
                    _ => "Sign in with gh auth login on the paired computer.",
                }
                .to_string(),
            ),
        ));
    }

    let mut suggested_review = None;
    let review = if let Some(number) = linked_number(linked.as_ref()) {
        view_review(&repo_path, &identity.slug, number).await?
    } else if let Some(branch) = branch.as_deref() {
        let detected = list_review_for_branch(&repo_path, &identity.slug, branch).await?;
        // An unlinked review stays hidden until the user links it again.
        match (detected, dismissed_number(linked.as_ref())) {
            (Some(review), Some(dismissed))
                if review.get("number").and_then(Value::as_i64) == Some(dismissed) =>
            {
                suggested_review = Some(suggested_review_json(&review));
                None
            }
            (detected, _) => detected,
        }
    } else {
        None
    };

    let review_json = if let Some(review) = review {
        let number = review.get("number").and_then(Value::as_i64).unwrap_or(0);
        let checks = load_checks(&repo_path, &identity.slug, number).await;
        let comments = super::mobile_pull_request_comments::load_comments(
            &repo_path,
            &identity.host,
            &identity.owner,
            &identity.repo,
            number,
        )
        .await;
        let mut review = review;
        if let Some(object) = review.as_object_mut() {
            object.insert("checks".into(), json!(checks));
            object.insert("comments".into(), json!(comments));
        }
        review
    } else {
        Value::Null
    };

    let unavailable = match (&review_json, &suggested_review) {
        (Value::Null, Some(_)) => {
            Some("The pull request for this branch was unlinked from the workspace.".to_string())
        }
        (Value::Null, None) => Some("No open pull request is linked to this branch.".to_string()),
        _ => None,
    };
    let mut snapshot = snapshot_envelope(
        branch,
        remote_url,
        Some("github"),
        auth_status,
        linked_json,
        review_json,
        unavailable,
    );
    if let Some(suggested) = suggested_review {
        snapshot["suggestedReview"] = suggested;
    }
    Ok(snapshot)
}

fn snapshot_envelope(
    branch: Option<String>,
    remote_url: Option<String>,
    provider: Option<&str>,
    auth_status: &str,
    linked_review: Option<Value>,
    review: Value,
    unavailable_reason: Option<String>,
) -> Value {
    json!({
        "branch": branch,
        "remoteUrl": remote_url,
        "provider": provider,
        "identity": remote_identity_json(remote_url.as_deref(), provider),
        "authStatus": auth_status,
        "linkedReview": linked_review,
        "review": review,
        "unavailableReason": unavailable_reason,
    })
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

async fn list_review_for_branch(
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

async fn load_checks(repo_path: &str, slug: &str, number: i64) -> Vec<Value> {
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
    let output = timeout(GH_TIMEOUT, command.output())
        .await
        .map_err(|_| HostError::state("The GitHub CLI timed out."))?
        .map_err(|error| HostError::state(format!("failed to run gh: {error}")))?;
    Ok((
        output.status.code().unwrap_or(1),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    ))
}

fn looks_like_missing_cli(error: &HostError) -> bool {
    let message = error.wire_message().to_ascii_lowercase();
    message.contains("no such file")
        || message.contains("not found")
        || message.contains("cannot find")
        || message.contains("program not found")
}
