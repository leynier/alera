use std::path::Path;

use alera_core::child_process::windowless_command;
use serde_json::Value;

#[allow(unused_imports)]
pub use crate::forge_api::{
    ForgeAction, ForgeAuthStatus, ForgeCheck, ForgeComment, ForgeIdentity, ForgeReview,
    ForgeService, ForgeSnapshot, ForgeUnavailableReason, MergeMethod,
};

const REVIEW_FIELDS: &str =
    "number,title,body,state,url,isDraft,mergeable,headRefName,baseRefName,author";
const CHECK_FIELDS: &str =
    "name,state,bucket,link,description,event,workflow,startedAt,completedAt";
const REVIEW_THREADS_QUERY: &str = r#"query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved comments(first:100){nodes{id databaseId body url createdAt path line author{login}}}}}}}}"#;

pub(crate) fn load_snapshot(
    _workspace_path: String,
    identity: ForgeIdentity,
    review_number: Option<u64>,
    review_dismissed: bool,
) -> Result<ForgeSnapshot, String> {
    let base_branches = identity.base_branches.clone();
    let suggested_base_branch = suggested_base_branch(&base_branches);
    let auth_status = gh_auth_status(&identity.host);
    if auth_status != ForgeAuthStatus::Authenticated {
        return Ok(ForgeSnapshot {
            provider: "GitHub".to_string(),
            host: identity.host,
            repo_slug: identity.repo_slug,
            branch: identity.branch,
            auth_status,
            unavailable_reason: None,
            base_branches,
            suggested_base_branch,
            review: None,
            suggested_review: None,
            checks: Vec::new(),
            comments: Vec::new(),
        });
    }
    let detected_review = if let Some(number) = review_number {
        Some(parse_review(&run_gh_json(
            vec![
                "pr".into(),
                "view".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug.clone(),
                "--json".into(),
                REVIEW_FIELDS.into(),
            ],
            false,
        )?)?)
    } else {
        let reviews = run_gh_json(
            vec![
                "pr".into(),
                "list".into(),
                "--repo".into(),
                identity.repo_slug.clone(),
                "--head".into(),
                identity.branch.clone(),
                "--state".into(),
                "open".into(),
                "--limit".into(),
                "1".into(),
                "--json".into(),
                REVIEW_FIELDS.into(),
            ],
            false,
        )?;
        reviews
            .as_array()
            .and_then(|items| items.first())
            .map(parse_review)
            .transpose()?
    };
    let (review, suggested_review) = if review_dismissed {
        (None, detected_review)
    } else {
        (detected_review, None)
    };
    let (checks, comments) = if let Some(review) = &review {
        (
            load_checks(&identity.repo_slug, review.number)?,
            load_comments(&identity.repo_slug, review.number)?,
        )
    } else {
        (Vec::new(), Vec::new())
    };
    Ok(ForgeSnapshot {
        provider: "GitHub".to_string(),
        host: identity.host,
        repo_slug: identity.repo_slug,
        branch: identity.branch,
        auth_status,
        unavailable_reason: None,
        base_branches,
        suggested_base_branch,
        review,
        suggested_review,
        checks,
        comments,
    })
}

pub fn unavailable_snapshot(reason: ForgeUnavailableReason) -> ForgeSnapshot {
    ForgeSnapshot {
        unavailable_reason: Some(reason),
        ..ForgeSnapshot::default()
    }
}

fn suggested_base_branch(branches: &[String]) -> String {
    for candidate in ["main", "master"] {
        if branches.iter().any(|branch| branch == candidate) {
            return candidate.to_string();
        }
    }
    branches
        .first()
        .cloned()
        .unwrap_or_else(|| "main".to_string())
}

fn load_checks(repo_slug: &str, number: u64) -> Result<Vec<ForgeCheck>, String> {
    let output = run_gh(
        vec![
            "pr".into(),
            "checks".into(),
            number.to_string(),
            "--repo".into(),
            repo_slug.into(),
            "--json".into(),
            CHECK_FIELDS.into(),
        ],
        true,
    )?;
    if output.trim().is_empty() {
        return Ok(Vec::new());
    }
    let value: Value = serde_json::from_str(&output)
        .map_err(|error| format!("Unexpected gh checks output: {error}"))?;
    Ok(value
        .as_array()
        .into_iter()
        .flatten()
        .map(|item| ForgeCheck {
            name: string(item, "name"),
            _state: string(item, "state"),
            bucket: string(item, "bucket"),
            link: optional_string(item, "link"),
            description: optional_string(item, "description"),
            workflow: optional_string(item, "workflow"),
            event: optional_string(item, "event"),
            started_at: optional_string(item, "startedAt"),
            completed_at: optional_string(item, "completedAt"),
        })
        .collect())
}

fn load_comments(repo_slug: &str, number: u64) -> Result<Vec<ForgeComment>, String> {
    let mut comments = Vec::new();
    comments.extend(load_rest_comments(
        &format!("repos/{repo_slug}/issues/{number}/comments?per_page=100"),
        "created_at",
        crate::forge_api::ForgeCommentSource::Conversation,
    )?);
    comments.extend(load_rest_comments(
        &format!("repos/{repo_slug}/pulls/{number}/reviews?per_page=100"),
        "submitted_at",
        crate::forge_api::ForgeCommentSource::ReviewSummary,
    )?);
    comments.extend(load_review_thread_comments(repo_slug, number)?);
    comments.sort_by(|left, right| left.created_at.cmp(&right.created_at));
    Ok(comments)
}

fn load_rest_comments(
    endpoint: &str,
    created_at_field: &str,
    source: crate::forge_api::ForgeCommentSource,
) -> Result<Vec<ForgeComment>, String> {
    let value = run_gh_json(vec!["api".into(), endpoint.into()], false)?;
    Ok(value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|item| {
            let body = string(item, "body");
            if body.trim().is_empty() {
                return None;
            }
            Some(ForgeComment {
                _id: item
                    .get("id")
                    .and_then(Value::as_i64)
                    .map(|id| id.to_string())
                    .or_else(|| optional_string(item, "id"))
                    .unwrap_or_default(),
                author: item
                    .get("user")
                    .and_then(|user| user.get("login"))
                    .and_then(Value::as_str)
                    .unwrap_or("Unknown")
                    .to_string(),
                body,
                url: optional_string(item, "html_url"),
                created_at: optional_string(item, created_at_field),
                path: None,
                line: None,
                resolved: false,
                source,
            })
        })
        .collect())
}

fn load_review_thread_comments(repo_slug: &str, number: u64) -> Result<Vec<ForgeComment>, String> {
    let Some((owner, repo)) = repo_slug.split_once('/') else {
        return Ok(Vec::new());
    };
    let value = run_gh_json(
        vec![
            "api".into(),
            "graphql".into(),
            "-f".into(),
            format!("query={REVIEW_THREADS_QUERY}"),
            "-F".into(),
            format!("owner={owner}"),
            "-F".into(),
            format!("repo={repo}"),
            "-F".into(),
            format!("number={number}"),
        ],
        false,
    )?;
    let threads = value
        .pointer("/data/repository/pullRequest/reviewThreads/nodes")
        .and_then(Value::as_array)
        .into_iter()
        .flatten();
    let mut comments = Vec::new();
    for thread in threads {
        let resolved = thread
            .get("isResolved")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        for item in thread
            .pointer("/comments/nodes")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let body = string(item, "body");
            if body.trim().is_empty() {
                continue;
            }
            comments.push(ForgeComment {
                _id: item
                    .get("databaseId")
                    .and_then(Value::as_i64)
                    .map(|id| id.to_string())
                    .unwrap_or_else(|| string(item, "id")),
                author: item
                    .get("author")
                    .and_then(|author| author.get("login"))
                    .and_then(Value::as_str)
                    .unwrap_or("Unknown")
                    .to_string(),
                body,
                url: optional_string(item, "url"),
                created_at: optional_string(item, "createdAt"),
                path: optional_string(item, "path"),
                line: item.get("line").and_then(Value::as_u64),
                resolved,
                source: crate::forge_api::ForgeCommentSource::ReviewThread,
            });
        }
    }
    Ok(comments)
}

pub(crate) fn run_action(
    workspace_path: String,
    identity: ForgeIdentity,
    action: ForgeAction,
) -> Result<String, String> {
    let mut arguments = vec!["pr".to_string()];
    let success = match action {
        ForgeAction::Create {
            title,
            body,
            base,
            draft,
        } => {
            push_branch(&workspace_path, &identity.branch)?;
            arguments.extend([
                "create".into(),
                "--repo".into(),
                identity.repo_slug,
                "--base".into(),
                base,
                "--head".into(),
                identity.branch,
                "--title".into(),
                title,
                "--body".into(),
                body,
            ]);
            if draft {
                arguments.push("--draft".into());
            }
            "Pull Request Created"
        }
        ForgeAction::Update {
            number,
            title,
            body,
            base,
        } => {
            arguments.extend([
                "edit".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                "--title".into(),
                title,
                "--body".into(),
                body,
                "--base".into(),
                base,
            ]);
            "Pull Request Updated"
        }
        ForgeAction::Merge { number, method } => {
            arguments.extend([
                "merge".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                match method {
                    MergeMethod::Merge => "--merge",
                    MergeMethod::Squash => "--squash",
                    MergeMethod::Rebase => "--rebase",
                }
                .into(),
            ]);
            "Pull Request Merged"
        }
        ForgeAction::Close { number } => {
            arguments.extend([
                "close".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
            ]);
            "Pull Request Closed"
        }
        ForgeAction::SetDraft { number, draft } => {
            arguments.extend([
                "ready".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
            ]);
            if draft {
                arguments.push("--undo".into());
            }
            if draft {
                "Pull Request Converted To Draft"
            } else {
                "Pull Request Marked Ready"
            }
        }
        ForgeAction::Comment { number, body } => {
            arguments.extend([
                "comment".into(),
                number.to_string(),
                "--repo".into(),
                identity.repo_slug,
                "--body".into(),
                body,
            ]);
            "Comment Added"
        }
        ForgeAction::UpdateComment {
            number,
            comment_id,
            source,
            body,
        } => {
            let endpoint = match source {
                crate::forge_api::ForgeCommentSource::Conversation => {
                    format!("repos/{}/issues/comments/{comment_id}", identity.repo_slug)
                }
                crate::forge_api::ForgeCommentSource::ReviewSummary => {
                    format!("repos/{}/pulls/{number}/reviews/{comment_id}", identity.repo_slug)
                }
                crate::forge_api::ForgeCommentSource::ReviewThread => {
                    format!("repos/{}/pulls/comments/{comment_id}", identity.repo_slug)
                }
            };
            arguments.extend([
                "api".into(),
                endpoint,
                "--method".into(),
                "PATCH".into(),
                "--raw-field".into(),
                format!("body={body}"),
            ]);
            "Review Comment Updated"
        }
    };
    run_gh(arguments, false)?;
    Ok(success.to_string())
}

fn push_branch(workspace_path: &str, branch: &str) -> Result<(), String> {
    let path = Path::new(workspace_path);
    let has_upstream = alera_core::git_cli::git_in_dir(
        path,
        &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
    )
    .is_ok();
    let arguments = if has_upstream {
        vec!["push"]
    } else {
        vec!["push", "-u", "origin", branch]
    };
    alera_core::git_cli::git_in_dir(path, &arguments)
        .map(|_| ())
        .map_err(|error| format!("Could not push the branch: {error}"))
}

pub fn github_identity(
    remote: &str,
    branch: String,
    mut base_branches: Vec<String>,
) -> Result<ForgeIdentity, ForgeUnavailableReason> {
    let (host, path) =
        split_remote(remote).map_err(|_| ForgeUnavailableReason::ProviderNotDetected)?;
    if host != "github.com" {
        return Err(ForgeUnavailableReason::UnsupportedProvider);
    }
    let segments = path
        .trim_matches('/')
        .trim_end_matches(".git")
        .split('/')
        .collect::<Vec<_>>();
    if segments.len() < 2 {
        return Err(ForgeUnavailableReason::ProviderNotDetected);
    }
    if !branch.is_empty() {
        base_branches.push(branch.clone());
    }
    base_branches.sort();
    base_branches.dedup();
    Ok(ForgeIdentity {
        host,
        repo_slug: format!("{}/{}", segments[0], segments[1]),
        branch,
        base_branches,
    })
}

fn split_remote(remote: &str) -> Result<(String, String), String> {
    if let Some((_, remainder)) = remote.split_once("://") {
        let remainder = remainder
            .rsplit_once('@')
            .map(|(_, value)| value)
            .unwrap_or(remainder);
        let (host, path) = remainder
            .split_once('/')
            .ok_or_else(|| "Git remote URL omitted its path.".to_string())?;
        return Ok((host.to_ascii_lowercase(), path.to_string()));
    }
    let without_user = remote
        .rsplit_once('@')
        .map(|(_, value)| value)
        .unwrap_or(remote);
    let (host, path) = without_user
        .split_once(':')
        .ok_or_else(|| "Git remote URL is not recognized.".to_string())?;
    Ok((host.to_ascii_lowercase(), path.to_string()))
}

fn run_gh_json(arguments: Vec<String>, allow_nonzero: bool) -> Result<Value, String> {
    let output = run_gh(arguments, allow_nonzero)?;
    serde_json::from_str(output.trim()).map_err(|error| format!("Unexpected gh JSON: {error}"))
}

fn run_gh(arguments: Vec<String>, allow_nonzero: bool) -> Result<String, String> {
    let result = windowless_command("gh")
        .args(arguments)
        .output()
        .map_err(|error| format!("Failed to run gh: {error}"))?;
    let exit_code = result.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&result.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&result.stderr).into_owned();
    if exit_code != 0 && !allow_nonzero {
        return Err(if stderr.trim().is_empty() {
            format!("gh exited with code {exit_code}.")
        } else {
            stderr.trim().to_string()
        });
    }
    Ok(stdout)
}

fn gh_auth_status(host: &str) -> ForgeAuthStatus {
    match windowless_command("gh")
        .args(["auth", "status", "--hostname", host])
        .output()
    {
        Ok(result) if result.status.success() => ForgeAuthStatus::Authenticated,
        Ok(_) => ForgeAuthStatus::NotAuthenticated,
        Err(_) => ForgeAuthStatus::CliMissing,
    }
}

/// Returns whether the authenticated GitHub user has starred Alera.
/// GitHub reports an unstarred repository as HTTP 404 for this endpoint.
#[allow(dead_code)]
pub(crate) fn github_starred() -> Option<bool> {
    let result = windowless_command("gh")
        .args(["api", "--silent", "-i", "user/starred/leynier/alera"])
        .output()
        .ok()?;
    if result.status.success() {
        return Some(true);
    }
    let output = format!(
        "{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    )
    .to_ascii_lowercase();
    if output.contains("http 404") || output.contains("status: 404") {
        Some(false)
    } else {
        None
    }
}

/// Stars Alera for the authenticated GitHub user.
#[allow(dead_code)]
pub(crate) fn star_github() -> bool {
    windowless_command("gh")
        .args(["api", "--silent", "-X", "PUT", "user/starred/leynier/alera"])
        .output()
        .is_ok_and(|result| result.status.success())
}

fn parse_review(value: &Value) -> Result<ForgeReview, String> {
    Ok(ForgeReview {
        number: value
            .get("number")
            .and_then(Value::as_u64)
            .ok_or_else(|| "gh review omitted number.".to_string())?,
        title: string(value, "title"),
        body: string(value, "body"),
        state: string(value, "state"),
        url: string(value, "url"),
        draft: value
            .get("isDraft")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        mergeable: string(value, "mergeable"),
        head_branch: string(value, "headRefName"),
        base_branch: string(value, "baseRefName"),
        author: value
            .get("author")
            .and_then(|author| author.get("login"))
            .and_then(Value::as_str)
            .unwrap_or("Unknown")
            .to_string(),
    })
}

fn string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn optional_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::{github_identity, split_remote, suggested_base_branch};

    #[test]
    fn parses_https_and_scp_github_remotes() {
        assert_eq!(
            split_remote("https://github.com/zed-industries/zed.git").unwrap(),
            (
                "github.com".to_string(),
                "zed-industries/zed.git".to_string()
            )
        );
        assert_eq!(
            split_remote("git@github.com:leynier/alera.git").unwrap(),
            ("github.com".to_string(), "leynier/alera.git".to_string())
        );
    }

    #[test]
    fn picks_the_same_default_base_branch_order_as_flutter() {
        assert_eq!(
            suggested_base_branch(&["feature".into(), "main".into()]),
            "main"
        );
        assert_eq!(
            suggested_base_branch(&["feature".into(), "master".into()]),
            "master"
        );
        assert_eq!(suggested_base_branch(&["feature".into()]), "feature");
        assert_eq!(suggested_base_branch(&[]), "main");
    }

    #[test]
    fn builds_identity_without_reading_the_repository() {
        let identity = github_identity(
            "https://github.com/owner/repo.git",
            "feature".into(),
            vec!["main".into()],
        )
        .unwrap();
        assert_eq!(identity.host, "github.com");
        assert_eq!(identity.repo_slug, "owner/repo");
        assert_eq!(identity.branch, "feature");
        assert_eq!(
            identity.base_branches,
            vec!["feature".to_string(), "main".to_string()]
        );
    }
}
