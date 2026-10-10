//! The `mobile.pullRequest.snapshot` body for every forge: the linked or
//! detected review, its checks and conversation, in the shape the phone, the
//! CLI, MCP, and Watch and Fix read.

use std::sync::Arc;

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_identity::remote_identity_json;
use super::super::mobile_pull_request_links::{dismissed_number, linked_number};
use super::provider::{AuthStatus, ForgeProvider};
use super::{build_forge, read_workspace_remote, ForgeKind};

pub(crate) async fn load_snapshot(
    store: &RuntimeStore,
    workspace: &Workspace,
) -> HostResult<Value> {
    let linked = store
        .find_linked_review(&workspace.id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let remote = read_workspace_remote(store, workspace).await?;
    let linked_json = linked.as_ref().map(|review| {
        json!({
            "number": review.number,
            "url": review.url,
            "provider": review.provider,
            "dismissed": review.dismissed,
        })
    });
    let envelope =
        |provider: Option<ForgeKind>, auth: &str, review: Value, reason: Option<&str>| {
            snapshot_envelope(
                remote.branch.clone(),
                remote.remote_url.clone(),
                provider.map(ForgeKind::wire),
                auth,
                linked_json.clone(),
                review,
                reason.map(ToOwned::to_owned),
            )
        };
    let (Some(identity), Some(remote_url)) = (remote.identity.clone(), remote.remote_url.clone())
    else {
        return Ok(envelope(
            None,
            "undetectable",
            Value::Null,
            Some("No GitHub, GitLab, or Azure DevOps remote was detected for this workspace."),
        ));
    };
    let kind = identity.kind;
    let forge = build_forge(identity, &remote_url, &workspace.path, None);
    let auth = match forge.auth_status().await {
        Ok(auth) => auth,
        Err(error) => {
            let mut snapshot = envelope(Some(kind), "cliMissing", Value::Null, None);
            snapshot["unavailableReason"] = json!(error.wire_message());
            return Ok(snapshot);
        }
    };
    if auth != AuthStatus::Authenticated {
        return Ok(envelope(
            Some(kind),
            auth.wire(),
            Value::Null,
            Some(&unavailable_reason(kind, auth)),
        ));
    }

    let mut suggested_review = None;
    let review = if let Some(number) = linked_number(linked.as_ref()) {
        forge.review_by_number(number).await?
    } else if let Some(branch) = remote.branch.as_deref() {
        let detected = forge.review_for_branch(branch).await?;
        // An unlinked review stays hidden until the user links it again.
        match (detected, dismissed_number(linked.as_ref())) {
            (Some(review), Some(dismissed)) if review.number == dismissed => {
                suggested_review = Some(json!({
                    "number": review.number,
                    "title": review.title,
                    "url": review.url,
                }));
                None
            }
            (detected, _) => detected,
        }
    } else {
        None
    };
    let review_json = match review {
        Some(review) => review_with_activity(forge.as_ref(), review.to_json()).await,
        None => Value::Null,
    };
    let reason = match (&review_json, &suggested_review) {
        (Value::Null, Some(_)) => {
            Some("The pull request for this branch was unlinked from the workspace.")
        }
        (Value::Null, None) => Some("No open pull request is linked to this branch."),
        _ => None,
    };
    let mut snapshot = envelope(Some(kind), auth.wire(), review_json, reason);
    if let Some(suggested) = suggested_review {
        snapshot["suggestedReview"] = suggested;
    }
    Ok(snapshot)
}

async fn review_with_activity(forge: &dyn ForgeProvider, mut review: Value) -> Value {
    let number = review["number"].as_i64().unwrap_or(0);
    let (checks, (comments, truncated)) =
        tokio::join!(forge.checks(number), forge.comments(number));
    review["checks"] = json!(checks);
    review["comments"] = json!(comments);
    review["commentsTruncated"] = json!(truncated);
    review
}

/// The phone's wording for GitHub stays as it was; the other forges name
/// their own CLI.
fn unavailable_reason(kind: ForgeKind, auth: AuthStatus) -> String {
    match (kind, auth) {
        (ForgeKind::GitHub, AuthStatus::CliMissing) => {
            "Install and authenticate the GitHub CLI (gh) on the paired computer.".into()
        }
        (ForgeKind::GitHub, _) => "Sign in with gh auth login on the paired computer.".into(),
        (_, AuthStatus::CliMissing) => {
            super::model::provider_unavailable(kind, false).wire_message()
        }
        _ => super::model::provider_unavailable(kind, true).wire_message(),
    }
}

pub(crate) fn snapshot_envelope(
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

/// The forge a snapshot already resolved, for work that follows it (merge
/// methods, Watch and Fix merges), running through [runner] when given.
pub(crate) fn snapshot_forge(
    snapshot: &Value,
    repo_path: &str,
    runner: Option<Arc<dyn super::runner::ForgeRunner>>,
) -> Option<Box<dyn ForgeProvider>> {
    let kind = ForgeKind::from_wire(snapshot["provider"].as_str()?)?;
    let remote_url = snapshot["remoteUrl"].as_str()?;
    let identity = super::identity::resolve_identity(remote_url, Some(kind))?;
    Some(build_forge(identity, remote_url, repo_path, runner))
}
