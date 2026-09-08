use std::collections::BTreeMap;
use std::process::Stdio;
use std::time::Duration;

use alera_core::git as core_git;
use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::time::timeout;

use crate::terminal_host::host_error::{HostError, HostResult};

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
        return Ok(json!({
            "branch": branch,
            "remoteUrl": remote_url,
            "provider": provider,
            "authStatus": if provider.is_some() { "unsupported" } else { "undetectable" },
            "linkedReview": linked_json,
            "review": Value::Null,
            "unavailableReason": if provider.is_some() {
                "This hosting provider is available on desktop. Mobile v1 loads GitHub pull requests through gh."
            } else {
                "No GitHub remote was detected for this workspace."
            },
        }));
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
            return Ok(json!({
                "branch": branch,
                "remoteUrl": remote_url,
                "provider": "github",
                "authStatus": "cliMissing",
                "linkedReview": linked_json,
                "review": Value::Null,
                "unavailableReason": error.wire_message(),
            }));
        }
    };
    if auth_status != "authenticated" {
        return Ok(json!({
            "branch": branch,
            "remoteUrl": remote_url,
            "provider": "github",
            "authStatus": auth_status,
            "linkedReview": linked_json,
            "review": Value::Null,
            "unavailableReason": match auth_status {
                "cliMissing" => "Install and authenticate the GitHub CLI (gh) on the paired computer.",
                _ => "Sign in with gh auth login on the paired computer.",
            },
        }));
    }

    let review = if let Some(number) = linked.as_ref().and_then(|review| review.number) {
        view_review(&repo_path, &identity.slug, number).await?
    } else if let Some(branch) = branch.as_deref() {
        list_review_for_branch(&repo_path, &identity.slug, branch).await?
    } else {
        None
    };

    let review_json = if let Some(review) = review {
        let number = review.get("number").and_then(Value::as_i64).unwrap_or(0);
        let checks = load_checks(&repo_path, &identity.slug, number).await;
        let comments = load_comments(&repo_path, &identity.owner, &identity.repo, number).await;
        let mut review = review;
        if let Some(object) = review.as_object_mut() {
            object.insert("checks".into(), json!(checks));
            object.insert("comments".into(), json!(comments));
        }
        review
    } else {
        Value::Null
    };

    Ok(json!({
        "branch": branch,
        "remoteUrl": remote_url,
        "provider": "github",
        "authStatus": auth_status,
        "linkedReview": linked_json,
        "review": review_json,
        "unavailableReason": if review_json.is_null() {
            Value::from("No open pull request is linked to this branch.")
        } else {
            Value::Null
        },
    }))
}

struct GitHubIdentity {
    host: String,
    owner: String,
    repo: String,
    slug: String,
}

fn parse_github_identity(url: &str) -> Option<GitHubIdentity> {
    let parsed = parse_remote_url(url)?;
    if parsed.hostname != "github.com" && !parsed.hostname.ends_with(".github.com") {
        return None;
    }
    if parsed.segments.len() < 2 {
        return None;
    }
    let owner = parsed.segments[0].clone();
    let repo = parsed.segments[1].clone();
    let slug = if parsed.hostname == "github.com" {
        format!("{owner}/{repo}")
    } else {
        format!("{}/{owner}/{repo}", parsed.host)
    };
    Some(GitHubIdentity {
        host: parsed.host,
        owner,
        repo,
        slug,
    })
}

fn detect_provider(url: Option<&str>) -> Option<&'static str> {
    let url = url?;
    let parsed = parse_remote_url(url)?;
    if parsed.hostname == "gitlab.com" || parsed.hostname.contains("gitlab") {
        return Some("gitlab");
    }
    if parsed.hostname == "dev.azure.com"
        || parsed.hostname.ends_with(".visualstudio.com")
        || parsed.hostname.contains("azure")
    {
        return Some("azureDevops");
    }
    None
}

struct ParsedRemote {
    host: String,
    hostname: String,
    segments: Vec<String>,
}

fn parse_remote_url(raw: &str) -> Option<ParsedRemote> {
    let url = raw.trim();
    if url.is_empty() {
        return None;
    }
    let (host, path) = if let Some(scheme_end) = url.find("://") {
        let rest = &url[scheme_end + 3..];
        let rest = rest.split_once('@').map_or(rest, |(_, rest)| rest);
        let (host, path) = rest.split_once('/')?;
        (host.to_string(), path.to_string())
    } else {
        let rest = url.split_once('@').map_or(url, |(_, rest)| rest);
        let (host, path) = rest.split_once(':')?;
        (host.to_string(), path.to_string())
    };
    let hostname = host
        .split(':')
        .next()
        .unwrap_or(&host)
        .trim()
        .to_ascii_lowercase();
    let segments = path
        .trim_start_matches('/')
        .trim_end_matches(".git")
        .split('/')
        .filter(|segment| !segment.is_empty())
        .map(ToOwned::to_owned)
        .collect::<Vec<_>>();
    if hostname.is_empty() || segments.is_empty() {
        return None;
    }
    Some(ParsedRemote {
        host: host.to_string(),
        hostname,
        segments,
    })
}

async fn view_review(repo_path: &str, slug: &str, number: i64) -> HostResult<Option<Value>> {
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

async fn load_comments(repo_path: &str, owner: &str, repo: &str, number: i64) -> Vec<Value> {
    let endpoint = format!("repos/{owner}/{repo}/issues/{number}/comments?per_page=50");
    let Ok((code, stdout, _)) = run_gh(repo_path, &["api", &endpoint]).await else {
        return Vec::new();
    };
    if code != 0 {
        return Vec::new();
    }
    serde_json::from_str::<Value>(&stdout)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .map(|entry| {
            json!({
                "id": entry.get("id").and_then(Value::as_i64).unwrap_or(0),
                "author": entry.get("user").and_then(|user| user.get("login")).and_then(Value::as_str),
                "body": entry.get("body").and_then(Value::as_str).unwrap_or(""),
                "createdAt": entry.get("created_at").and_then(Value::as_str),
                "url": entry.get("html_url").and_then(Value::as_str),
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

async fn run_gh(repo_path: &str, args: &[&str]) -> HostResult<(i32, String, String)> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_github_https_and_ssh_remotes() {
        let https = parse_github_identity("https://github.com/leynier/alera.git").unwrap();
        assert_eq!(https.slug, "leynier/alera");
        let ssh = parse_github_identity("git@github.com:leynier/alera.git").unwrap();
        assert_eq!(ssh.owner, "leynier");
        assert_eq!(ssh.repo, "alera");
        assert!(parse_github_identity("https://gitlab.com/group/project.git").is_none());
        assert_eq!(
            detect_provider(Some("https://gitlab.com/group/project.git")),
            Some("gitlab")
        );
    }
}
