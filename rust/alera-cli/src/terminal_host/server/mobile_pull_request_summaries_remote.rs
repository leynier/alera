//! Pull request summaries for a project whose folder lives on another host.
//!
//! The local batch reads the repository identity from `project.repo_path` and
//! runs `gh` next to it. For a remote-only project that path is a directory on
//! the host, so opening it here reads nothing or the wrong folder and the
//! hub's `gh` has the wrong credentials. The identity and the reviews come
//! from the host instead: one forwarded `mobile.pullRequest.snapshot` per
//! workspace (`remote_pull_request_routing::snapshot_for_workspace` mirrors
//! and forwards), mapped into the summary row the local batch emits. A
//! workspace whose forward fails, or whose host cannot answer for `gh`, stays
//! out of `evaluatedWorkspaceIds` like a failed batch does, so the phone keeps
//! its last-known icon.

use alera_core::runtime::{RuntimeStore, Workspace};
use futures_util::future::join_all;
use serde_json::Value;
use tracing::warn;

use crate::terminal_host::host_link_registry::HostLinkRegistry;

use super::mobile_pull_request_check_counts::{count_classified_checks, ClassifiedCheck};
use super::mobile_pull_request_summaries::{review_summary_json, ProjectSummaries};
use super::remote_pull_request_routing::snapshot_for_workspace;

pub(super) async fn remote_project_summaries(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    project_id: &str,
    group: &[Workspace],
) -> ProjectSummaries {
    let snapshots = join_all(group.iter().map(|workspace| async move {
        (
            workspace.id.as_str(),
            snapshot_for_workspace(store, links, &workspace.id).await,
        )
    }))
    .await;
    let mut result = ProjectSummaries::default();
    let mut failures = Vec::<String>::new();
    for (workspace_id, snapshot) in snapshots {
        match snapshot {
            Ok(snapshot) if snapshot_answers_for_reviews(&snapshot) => {
                result.evaluated.insert(workspace_id.to_string());
                if let Some(summary) = summary_from_snapshot(workspace_id, &snapshot) {
                    result.summaries.push(summary);
                }
            }
            Ok(snapshot) => failures.push(format!(
                "{workspace_id}: gh on the host is {}",
                snapshot["authStatus"].as_str().unwrap_or("unavailable")
            )),
            Err(error) => failures.push(format!("{workspace_id}: {}", error.wire_message())),
        }
    }
    // One line per project and refresh, as the local batch warns, rather than
    // one per workspace of a host that is offline.
    if !failures.is_empty() {
        warn!(
            "could not load remote pull request summaries for {project_id}: {}",
            failures.join("; ")
        );
    }
    result
}

/// Whether the snapshot is an answer about the reviews rather than about
/// `gh`. The local batch fails as a whole when `gh` is missing or signed out
/// and leaves its workspaces unevaluated; a host in that state gets the same
/// treatment. A repository without a GitHub remote is a quiet empty answer
/// there too, so `undetectable` and `unsupported` do evaluate.
fn snapshot_answers_for_reviews(snapshot: &Value) -> bool {
    !matches!(
        snapshot.get("authStatus").and_then(Value::as_str),
        Some("cliMissing" | "notAuthenticated")
    )
}

/// Maps the snapshot's `review` (the `gh pr view` shape plus `checks` from
/// `gh pr checks`) into the summary row. The snapshot already applied the
/// linked-number, open-only and dismissed rules, so a null review means no
/// row.
fn summary_from_snapshot(workspace_id: &str, snapshot: &Value) -> Option<Value> {
    let review = snapshot.get("review").filter(|review| review.is_object())?;
    let checks = review
        .get("checks")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let counts = count_classified_checks(checks.iter().filter_map(classify_check_bucket));
    Some(review_summary_json(workspace_id, review, &counts))
}

/// `gh pr checks --json bucket` reduces every run to `pass`, `fail`,
/// `pending`, `skipping` or `cancel`; this is `mapGitHubCheck` folded through
/// `deriveReviewChecksRollup`, where a cancelled run counts as failed.
fn classify_check_bucket(check: &Value) -> Option<ClassifiedCheck> {
    let name = check
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("check")
        .to_string();
    let bucket = check
        .get("bucket")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_ascii_lowercase();
    let failed = bucket == "fail" || bucket == "cancel";
    let pending = bucket == "pending";
    Some((name, failed, pending))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn check(name: &str, bucket: &str) -> Value {
        json!({"name": name, "state": "", "bucket": bucket, "url": null})
    }

    /// The shape `snapshot_mobile_pull_request` answers with, as in the
    /// `mobile_pull_request_requests` tests, trimmed to what a summary reads.
    fn snapshot(review: Value, auth_status: &str) -> Value {
        json!({
            "branch": "feature/login",
            "remoteUrl": "git@github.com:leynier/alera.git",
            "provider": "github",
            "identity": {"provider": "github", "host": "github.com", "owner": "leynier", "repo": "alera"},
            "authStatus": auth_status,
            "linkedReview": null,
            "review": review,
            "unavailableReason": if review.is_null() { json!("No open pull request is linked to this branch.") } else { Value::Null },
            "aiAssistEnabled": false,
            "baseBranches": ["main"],
            "suggestedBaseBranch": "main",
            "canComment": true,
        })
    }

    fn review(state: &str, is_draft: bool, checks: Vec<Value>) -> Value {
        json!({
            "number": 42,
            "title": "feat: fork indicators",
            "state": state,
            "url": "https://github.com/leynier/alera/pull/42",
            "isDraft": is_draft,
            "author": "leynier",
            "headRefName": "feature/login",
            "baseRefName": "main",
            "createdAt": "2026-09-20T10:00:00Z",
            "mergeable": "CONFLICTING",
            "headSha": "abc123",
            "checks": checks,
            "comments": [],
            "commentsTruncated": false,
        })
    }

    #[test]
    fn maps_a_snapshot_review_into_the_batch_summary_shape() {
        let checks = vec![
            check("build", "pass"),
            check("test", "pending"),
            check("lint", "fail"),
            check("e2e", "cancel"),
            check("docs", "skipping"),
        ];
        let summary = summary_from_snapshot(
            "ws-1",
            &snapshot(review("OPEN", false, checks), "authenticated"),
        )
        .unwrap();
        assert_eq!(
            summary,
            json!({
                "workspaceId": "ws-1",
                "number": 42,
                "title": "feat: fork indicators",
                "url": "https://github.com/leynier/alera/pull/42",
                "state": "open",
                "mergeable": "CONFLICTING",
                "checksRollup": "failure",
                "pendingCheckCount": 1,
                "failedCheckCount": 2,
                "failingCheckNames": ["lint", "e2e"],
            })
        );
    }

    #[test]
    fn display_state_and_rollup_follow_the_local_batch() {
        let draft = summary_from_snapshot(
            "ws",
            &snapshot(review("OPEN", true, vec![]), "authenticated"),
        )
        .unwrap();
        assert_eq!(draft["state"], "draft");
        assert_eq!(draft["checksRollup"], "none");

        let merged = summary_from_snapshot(
            "ws",
            &snapshot(
                review("MERGED", false, vec![check("build", "pass")]),
                "authenticated",
            ),
        )
        .unwrap();
        assert_eq!(merged["state"], "merged");
        assert_eq!(merged["checksRollup"], "success");

        let pending = summary_from_snapshot(
            "ws",
            &snapshot(
                review(
                    "CLOSED",
                    false,
                    vec![check("build", "pass"), check("test", "pending")],
                ),
                "authenticated",
            ),
        )
        .unwrap();
        assert_eq!(pending["state"], "closed");
        assert_eq!(pending["checksRollup"], "pending");
        assert_eq!(pending["pendingCheckCount"], 1);
    }

    #[test]
    fn a_snapshot_without_a_review_has_no_row() {
        assert!(summary_from_snapshot("ws", &snapshot(Value::Null, "authenticated")).is_none());
        assert!(summary_from_snapshot("ws", &snapshot(Value::Null, "undetectable")).is_none());
    }

    #[test]
    fn only_gh_problems_leave_a_workspace_unevaluated() {
        for status in ["authenticated", "undetectable", "unsupported"] {
            assert!(
                snapshot_answers_for_reviews(&snapshot(Value::Null, status)),
                "{status}"
            );
        }
        for status in ["cliMissing", "notAuthenticated"] {
            assert!(
                !snapshot_answers_for_reviews(&snapshot(Value::Null, status)),
                "{status}"
            );
        }
    }
}
