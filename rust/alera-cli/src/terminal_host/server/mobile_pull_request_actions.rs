//! Pull request writes for a paired phone: comments, replies, edits, merge,
//! draft status, close, link, unlink and create. Each verb runs the same `gh`
//! command the desktop forge layer runs (`github_review_actions.dart`,
//! `github_review_comments.dart`) and answers with a fresh snapshot, so the
//! phone never has to guess what a write changed.

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, LOCAL_HOST_ID};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::mobile_pull_request_failures::{gh_failure, gh_missing};
use super::mobile_pull_request_identity::{parse_github_identity, GitHubIdentity};
use super::mobile_pull_request_links::{parse_review_reference, save_link};
use super::mobile_pull_request_requests::{run_gh, snapshot_mobile_pull_request, view_review};
use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;
use super::requests::{optional_string_key, require_string_key};
use super::ServerActor;

/// Verbs that change the workspace link, so the runtime broadcasts
/// `linkedReviewsChanged` after them like it does for `linkedReview.upsert`.
pub(super) const LINK_CHANGING_ACTIONS: &[&str] = &[
    "mobile.pullRequest.link",
    "mobile.pullRequest.unlink",
    "mobile.pullRequest.create",
];

#[derive(Debug, PartialEq)]
pub(super) enum Action {
    Comment {
        number: i64,
        body: String,
        reply_to: Option<i64>,
    },
    CommentUpdate {
        number: i64,
        comment_id: i64,
        source: CommentSource,
        body: String,
    },
    Merge {
        number: i64,
        method: MergeMethod,
    },
    DraftStatus {
        number: i64,
        draft: bool,
    },
    Close {
        number: i64,
    },
    Link {
        reference: String,
    },
    Unlink {
        number: i64,
        url: Option<String>,
    },
    Create {
        base: String,
        title: String,
        body: String,
        draft: bool,
    },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum CommentSource {
    Conversation,
    ReviewSummary,
    ReviewThread,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum MergeMethod {
    MergeCommit,
    Squash,
    Rebase,
}

impl ServerActor {
    /// Link writes broadcast `linkedReviewsChanged` like `linkedReview.upsert`
    /// does, so a desktop showing the same workspace refreshes its panel.
    pub(super) fn broadcast_pull_request_link_change(
        &self,
        request_type: &str,
        result: &HostResult<Value>,
    ) {
        if result.is_ok() && LINK_CHANGING_ACTIONS.contains(&request_type) {
            self.broadcast_authenticated(event("linkedReviewsChanged", json!({})));
        }
    }
}

/// Every `mobile.pullRequest.*` verb: the snapshot read and the writes.
pub(super) async fn handle_mobile_pull_request(
    store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    if request_type == "mobile.pullRequest.snapshot" {
        return snapshot_mobile_pull_request(store, payload).await;
    }
    run_mobile_pull_request_action(store, request_type, payload).await
}

async fn run_mobile_pull_request_action(
    store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    let action = parse_action(request_type, payload)?;
    let workspace = workspace_for_mobile_file_request(store, payload).await?;
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != LOCAL_HOST_ID {
        return Err(HostError::state(
            "Pull request actions are only available for workspaces on this runtime.",
        ));
    }
    let identity = github_identity(&workspace.path).await?;
    let _busy = BusyGuard::acquire(&workspace.id)?;
    match action {
        Action::Link { reference } => {
            let number = parse_review_reference(&reference)
                .ok_or_else(|| HostError::state("Enter a pull request number or URL."))?;
            let review = view_review(&workspace.path, &identity.slug, number)
                .await?
                .ok_or_else(|| {
                    HostError::state(format!("Pull request #{number} was not found."))
                })?;
            let url = review
                .get("url")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned);
            save_link(store, &workspace.id, number, url, false).await?;
        }
        Action::Unlink { number, url } => {
            save_link(store, &workspace.id, number, url, true).await?
        }
        Action::Create { .. } => {
            let head = current_branch(&workspace.path).await?;
            let stdout = run_checked(&workspace.path, &gh_args(&action, &identity, &head)).await?;
            let url = stdout
                .lines()
                .map(str::trim)
                .find(|line| line.starts_with("http"));
            if let Some(number) = url.and_then(parse_review_reference) {
                save_link(
                    store,
                    &workspace.id,
                    number,
                    url.map(ToOwned::to_owned),
                    false,
                )
                .await?;
            }
        }
        _ => {
            run_checked(&workspace.path, &gh_args(&action, &identity, "")).await?;
        }
    }
    snapshot_mobile_pull_request(store, payload).await
}

pub(super) fn parse_action(request_type: &str, payload: &Value) -> HostResult<Action> {
    let number = || positive_i64(payload, "number");
    let body = || {
        let body = require_string_key(payload, "body")?;
        if body.trim().is_empty() {
            return Err(HostError::state("Enter a comment before posting."));
        }
        Ok(body)
    };
    Ok(match request_type {
        "mobile.pullRequest.comment" => Action::Comment {
            number: number()?,
            body: body()?,
            reply_to: payload.get("replyToCommentId").and_then(Value::as_i64),
        },
        "mobile.pullRequest.commentUpdate" => Action::CommentUpdate {
            number: number()?,
            comment_id: positive_i64(payload, "commentId")?,
            source: match require_string_key(payload, "source")?.as_str() {
                "conversation" => CommentSource::Conversation,
                "reviewSummary" => CommentSource::ReviewSummary,
                "reviewThread" => CommentSource::ReviewThread,
                other => return Err(HostError::state(format!("Unknown comment source: {other}"))),
            },
            body: body()?,
        },
        "mobile.pullRequest.merge" => Action::Merge {
            number: number()?,
            method: match require_string_key(payload, "method")?.as_str() {
                "mergeCommit" => MergeMethod::MergeCommit,
                "squash" => MergeMethod::Squash,
                "rebase" => MergeMethod::Rebase,
                "providerDefault" => {
                    return Err(HostError::state(
                        "GitHub does not expose a provider-default merge method through gh.",
                    ))
                }
                other => return Err(HostError::state(format!("Unknown merge method: {other}"))),
            },
        },
        "mobile.pullRequest.draftStatus" => Action::DraftStatus {
            number: number()?,
            draft: payload
                .get("draft")
                .and_then(Value::as_bool)
                .ok_or_else(|| HostError::state("draft must be a boolean."))?,
        },
        "mobile.pullRequest.close" => Action::Close { number: number()? },
        "mobile.pullRequest.link" => Action::Link {
            reference: require_string_key(payload, "reference")?,
        },
        "mobile.pullRequest.unlink" => Action::Unlink {
            number: number()?,
            url: optional_string_key(payload, "url"),
        },
        "mobile.pullRequest.create" => {
            let title = require_string_key(payload, "title")?;
            if title.trim().is_empty() {
                return Err(HostError::state(
                    "Enter a title before creating the pull request.",
                ));
            }
            let base = require_string_key(payload, "baseBranch")?
                .trim()
                .to_string();
            if base.is_empty() {
                return Err(HostError::state("Select a base branch."));
            }
            Action::Create {
                base,
                title: title.trim().to_string(),
                body: optional_string_key(payload, "body").unwrap_or_default(),
                draft: payload
                    .get("draft")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            }
        }
        other => {
            return Err(HostError::state(format!(
                "Unsupported pull request action: {other}"
            )))
        }
    })
}

/// The `gh` argv for an action. `head` is only read by create.
pub(super) fn gh_args(action: &Action, identity: &GitHubIdentity, head: &str) -> Vec<String> {
    let slug = identity.slug.clone();
    let pr = |verb: &str, number: i64| -> Vec<String> {
        vec![
            "pr".into(),
            verb.into(),
            number.to_string(),
            "--repo".into(),
            slug.clone(),
        ]
    };
    let api = |method: &str, endpoint: String, body: &str| -> Vec<String> {
        vec![
            "api".into(),
            "--hostname".into(),
            identity.host.clone(),
            "--method".into(),
            method.into(),
            endpoint,
            "--raw-field".into(),
            format!("body={body}"),
        ]
    };
    let repo = format!("repos/{}/{}", identity.owner, identity.repo);
    match action {
        Action::Comment {
            number,
            body,
            reply_to: None,
        } => {
            let mut args = pr("comment", *number);
            args.extend(["--body".into(), body.clone()]);
            args
        }
        Action::Comment {
            number,
            body,
            reply_to: Some(comment_id),
        } => api(
            "POST",
            format!("{repo}/pulls/{number}/comments/{comment_id}/replies"),
            body,
        ),
        Action::CommentUpdate {
            number,
            comment_id,
            source,
            body,
        } => match source {
            CommentSource::Conversation => api(
                "PATCH",
                format!("{repo}/issues/comments/{comment_id}"),
                body,
            ),
            // GitHub updates a submitted review body with PUT, not PATCH.
            CommentSource::ReviewSummary => api(
                "PUT",
                format!("{repo}/pulls/{number}/reviews/{comment_id}"),
                body,
            ),
            CommentSource::ReviewThread => {
                api("PATCH", format!("{repo}/pulls/comments/{comment_id}"), body)
            }
        },
        Action::Merge { number, method } => {
            let mut args = pr("merge", *number);
            args.push(
                match method {
                    MergeMethod::MergeCommit => "--merge",
                    MergeMethod::Squash => "--squash",
                    MergeMethod::Rebase => "--rebase",
                }
                .into(),
            );
            args
        }
        Action::DraftStatus { number, draft } => {
            let mut args = pr("ready", *number);
            if *draft {
                args.push("--undo".into());
            }
            args
        }
        Action::Close { number } => pr("close", *number),
        Action::Create {
            base,
            title,
            body,
            draft,
        } => {
            let mut args: Vec<String> = [
                "pr", "create", "--repo", &slug, "--base", base, "--head", head, "--title", title,
                "--body", body,
            ]
            .into_iter()
            .map(ToOwned::to_owned)
            .collect();
            if *draft {
                args.push("--draft".into());
            }
            args
        }
        Action::Link { .. } | Action::Unlink { .. } => Vec::new(),
    }
}

async fn run_checked(repo_path: &str, args: &[String]) -> HostResult<String> {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let (code, stdout, stderr) = match run_gh(repo_path, &args).await {
        Ok(output) => output,
        Err(error) if error.wire_message().starts_with("failed to run gh") => {
            return Err(gh_missing())
        }
        Err(error) => return Err(error),
    };
    if code != 0 {
        return Err(gh_failure(&stderr, &stdout));
    }
    Ok(stdout)
}

async fn github_identity(repo_path: &str) -> HostResult<GitHubIdentity> {
    let repo_path = repo_path.to_string();
    let remote = tokio::task::spawn_blocking(move || core_git::repository_remote_url(&repo_path))
        .await
        .map_err(|error| HostError::state(format!("Could not read the git remote: {error}")))?
        .ok()
        .flatten();
    remote
        .as_deref()
        .and_then(parse_github_identity)
        .ok_or_else(|| {
            HostError::state(
                "Pull request actions on mobile are available for GitHub repositories.",
            )
        })
}

async fn current_branch(repo_path: &str) -> HostResult<String> {
    let repo_path = repo_path.to_string();
    let branch = tokio::task::spawn_blocking(move || core_git::current_branch(&repo_path))
        .await
        .map_err(|error| HostError::state(format!("Could not read the current branch: {error}")))?
        .map_err(|error| HostError::state(error.to_string()))?;
    if branch.is_empty() || branch == "HEAD" {
        return Err(HostError::state(
            "Check out a branch before creating a pull request.",
        ));
    }
    Ok(branch)
}

fn positive_i64(payload: &Value, key: &str) -> HostResult<i64> {
    payload
        .get(key)
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
        .ok_or_else(|| HostError::state(format!("{key} must be a positive integer.")))
}

/// One pull request write per workspace at a time: two phones (or one phone
/// retrying) must not merge and close the same review concurrently.
struct BusyGuard(String);

impl BusyGuard {
    fn acquire(workspace_id: &str) -> HostResult<Self> {
        let mut active = active_writes()
            .lock()
            .map_err(|_| HostError::state("Pull request state is unavailable."))?;
        if !active.insert(workspace_id.to_string()) {
            return Err(HostError::conflict(
                "pullRequestBusy",
                "Another pull request action is already running for this workspace.",
                json!({}),
            ));
        }
        Ok(Self(workspace_id.to_string()))
    }
}

impl Drop for BusyGuard {
    fn drop(&mut self) {
        if let Ok(mut active) = active_writes().lock() {
            active.remove(&self.0);
        }
    }
}

fn active_writes() -> &'static Mutex<HashSet<String>> {
    static ACTIVE: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    ACTIVE.get_or_init(Default::default)
}

#[cfg(test)]
#[path = "mobile_pull_request_actions_tests.rs"]
mod tests;
