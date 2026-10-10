//! Pull request writes for a paired phone, the CLI, and MCP: comments,
//! replies, edits, merge, draft status, close, link, unlink, create and Ship.
//! The verbs run through `pull_request_forges` for every forge and answer with
//! a fresh snapshot, so a client never has to guess what a write changed. The
//! `gh` argv here is GitHub's, the same command the desktop forge layer runs
//! (`github_review_actions.dart`, `github_review_comments.dart`).

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::event;

use super::mobile_pull_request_identity::GitHubIdentity;
use super::mobile_pull_request_requests::snapshot_mobile_pull_request;
use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;
use super::ServerActor;

/// Verbs that change the workspace link, so the runtime broadcasts
/// `linkedReviewsChanged` after them like it does for `linkedReview.upsert`.
pub(super) const LINK_CHANGING_ACTIONS: &[&str] = &[
    "mobile.pullRequest.link",
    "mobile.pullRequest.unlink",
    "mobile.pullRequest.create",
    "mobile.pullRequest.ship",
    "pullRequestStack.create",
    "pullRequestStack.link",
    "pullRequestStack.merge",
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

/// Every `mobile.pullRequest.*` verb with a workspace: the snapshot read and
/// the writes. `summaries` spans projects and hosts and is dispatched to
/// `mobile_pull_request_summaries` by the caller.
pub(super) async fn handle_mobile_pull_request(
    store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    if let Some(workspace_id) = payload.get("workspaceId").and_then(Value::as_str) {
        super::remote_pull_request_routing::adopt_hub_linked_review(store, workspace_id, payload)
            .await?;
    }
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
    let workspace = workspace_for_mobile_file_request(store, payload).await?;
    super::pull_request_forges::run_forge_action(store, &workspace, request_type, payload).await?;
    Ok(completed_action_snapshot(
        snapshot_mobile_pull_request(store, payload).await,
    ))
}

fn completed_action_snapshot(snapshot: HostResult<Value>) -> Value {
    match snapshot {
        Ok(mut snapshot) => {
            snapshot["mutationApplied"] = json!(true);
            snapshot
        }
        Err(error) => json!({"mutationApplied": true, "refreshError": error.to_string()}),
    }
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
    }
}

#[cfg(test)]
#[path = "mobile_pull_request_actions_tests.rs"]
mod tests;
