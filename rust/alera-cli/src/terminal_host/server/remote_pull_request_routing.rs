//! Pull request work for a workspace whose checkout lives on another host.
//!
//! `gh` has to run where the checkout and its credentials are, so the hub
//! forwards the `mobile.pullRequest.*` verbs to the satellite. The one piece of
//! hub-owned state those verbs read and write is the workspace's linked
//! review, and the satellite's copy is disposable: every forwarded request
//! carries the hub's record (`hubLinkedReview`, an object or an explicit null),
//! the satellite adopts it before doing anything, and after a verb that
//! changes the link the hub adopts what the satellite answered. The record
//! therefore never has two owners.

use alera_core::runtime::{LinkedReview, RuntimeStore, Workspace};
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

use super::mobile_pull_request_actions::LINK_CHANGING_ACTIONS;

pub(super) const HUB_LINKED_REVIEW_KEY: &str = "hubLinkedReview";

/// `summaries` spans every workspace of a project and has no `workspaceId`,
/// so it is answered where it is asked.
pub(super) fn is_forwarded_pull_request_verb(request_type: &str) -> bool {
    request_type.starts_with("mobile.pullRequest.")
        && request_type != "mobile.pullRequest.summaries"
}

/// Hub side: the payload to send to the satellite, carrying the hub's link and
/// the AI Assist settings Ship and the snapshot's `aiAssistEnabled` depend on.
pub(super) async fn hub_pull_request_payload(
    store: &RuntimeStore,
    workspace_id: &str,
    payload: &Value,
) -> HostResult<Value> {
    let linked = store
        .find_linked_review(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let mut forwarded = payload.clone();
    forwarded[HUB_LINKED_REVIEW_KEY] = linked.as_ref().map_or(Value::Null, linked_review_json);
    if let Ok(settings) = store.effective_ai_assist_settings().await {
        forwarded[super::remote_ai_assist_requests::AI_ASSIST_SETTINGS_KEY] =
            serde_json::to_value(settings).unwrap_or(Value::Null);
    }
    Ok(forwarded)
}

/// Satellite side: adopt the hub's link before reading or changing it. A
/// payload without the key comes from a client of this runtime (a phone paired
/// to it, or an older hub) and leaves the local record alone.
pub(super) async fn adopt_hub_linked_review(
    store: &RuntimeStore,
    workspace_id: &str,
    payload: &Value,
) -> HostResult<()> {
    let Some(linked) = payload.get(HUB_LINKED_REVIEW_KEY) else {
        return Ok(());
    };
    store_linked_review(store, workspace_id, linked).await
}

/// Hub side: after a verb that may have changed the link, take the record the
/// satellite reports. A response without a snapshot (the mutation applied but
/// the refresh failed) keeps the hub's record; the next snapshot corrects it.
pub(super) async fn adopt_satellite_linked_review(
    store: &RuntimeStore,
    workspace_id: &str,
    request_type: &str,
    response: &Value,
) {
    if !LINK_CHANGING_ACTIONS.contains(&request_type) {
        return;
    }
    let Some(linked) = response.get("linkedReview") else {
        return;
    };
    if let Err(error) = store_linked_review(store, workspace_id, linked).await {
        tracing::warn!(
            target: "host_link",
            workspace_id,
            "could not adopt the linked review a remote host reported: {}",
            error.wire_message()
        );
    }
}

async fn store_linked_review(
    store: &RuntimeStore,
    workspace_id: &str,
    linked: &Value,
) -> HostResult<()> {
    let Some(number) = linked.get("number").and_then(Value::as_i64) else {
        return store
            .remove_linked_review(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()));
    };
    let text = |key: &str| {
        linked
            .get(key)
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
    };
    store
        .upsert_linked_review(LinkedReview {
            workspace_id: workspace_id.to_string(),
            dismissed: linked
                .get("dismissed")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            provider: text("provider"),
            number: Some(number),
            url: text("url"),
            linked_at: Utc::now(),
        })
        .await
        .map(|_| ())
        .map_err(|error| HostError::state(error.to_string()))
}

fn linked_review_json(review: &LinkedReview) -> Value {
    json!({
        "number": review.number,
        "url": review.url,
        "provider": review.provider,
        "dismissed": review.dismissed,
    })
}

/// The snapshot Watch and Fix evaluates, taken on the host that owns the
/// checkout.
pub(super) async fn snapshot_for_workspace(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    workspace_id: &str,
) -> HostResult<Value> {
    let payload = json!({ "workspaceId": workspace_id });
    match super::host_link_routing::forward_workspace_scoped_request(
        store,
        links,
        "mobile.pullRequest.snapshot",
        &payload,
    )
    .await?
    {
        Some(snapshot) => Ok(snapshot),
        None => {
            super::mobile_pull_request_requests::snapshot_mobile_pull_request(store, &payload).await
        }
    }
}

/// Runs `gh` in the workspace's checkout, locally or over the host link.
pub(super) async fn run_gh_for_workspace(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    workspace: &Workspace,
    args: &[&str],
) -> HostResult<(i32, String, String)> {
    let payload = json!({
        "workspaceId": workspace.id,
        "executable": "gh",
        "arguments": args,
    });
    let Some(output) = super::host_link_routing::forward_workspace_scoped_request(
        store,
        links,
        super::host_process_requests::HOST_PROCESS_RUN,
        &payload,
    )
    .await?
    else {
        return super::mobile_pull_request_requests::run_gh(&workspace.path, args).await;
    };
    let text = |key: &str| {
        output
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    Ok((
        output
            .get("exitCode")
            .and_then(Value::as_i64)
            .and_then(|code| i32::try_from(code).ok())
            .unwrap_or(1),
        text("stdout"),
        text("stderr"),
    ))
}

#[cfg(test)]
#[path = "remote_pull_request_routing_tests.rs"]
mod tests;
