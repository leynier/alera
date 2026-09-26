//! Hub-side routing of workspace-scoped work to the satellite that owns the
//! workspace's checkout.
//!
//! Every host-scoped verb (files, git, search, processes) starts here: resolve
//! the workspace, open or reuse its host link, and make sure the satellite has
//! the workspace registered before asking it to do anything with it. The
//! mirror call is idempotent and cheap once the record exists, so callers do
//! not track whether they already mirrored.

use std::sync::Arc;

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link::HostLink;
use crate::terminal_host::host_link_registry::HostLinkRegistry;

/// Finds a remote workspace and returns its record. A local workspace is an
/// error here because nothing on the hub should route local work over a link.
pub(crate) async fn remote_workspace(
    store: &RuntimeStore,
    workspace_id: &str,
) -> HostResult<Workspace> {
    let workspace = store
        .find_workspace(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .ok_or_else(|| HostError::state(format!("Unknown workspace: {workspace_id}")))?;
    if !crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
        return Err(HostError::state(format!(
            "Workspace {workspace_id} runs on the local host; it has no host link."
        )));
    }
    Ok(workspace)
}

/// Opens (or reuses) the link to the workspace's host and registers the
/// workspace on the satellite. Returns the link and the satellite's copy of the
/// workspace record, whose `path` is canonical on that host.
pub(crate) async fn mirror_workspace(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    workspace_id: &str,
) -> HostResult<(Arc<HostLink>, Value)> {
    let workspace = remote_workspace(store, workspace_id).await?;
    let registration =
        crate::remote_owner_terminal_launch::satellite_registration(store, &workspace)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
    let link = links.link(&workspace.host_id).await?;
    let mirrored = link
        .request_with_timeout(
            "hub.mirror.workspace",
            registration,
            crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
        )
        .await?;
    Ok((link, mirrored))
}

/// Verbs whose work happens where the checkout is. The `mobile.*` names are
/// the wire names the phone already uses; the desktop shares them for remote
/// workspaces so one satellite implementation serves both.
pub(crate) fn is_host_scoped_workspace_verb(request_type: &str) -> bool {
    request_type.starts_with("workspace.files.")
        || request_type == super::host_process_requests::HOST_PROCESS_RUN
        || request_type.starts_with("git.")
        || request_type.starts_with("mobile.git.")
        || super::remote_pull_request_routing::is_forwarded_pull_request_verb(request_type)
        || matches!(
            request_type,
            "mobile.workspaceFile.read"
                | "mobile.workspaceExplorer.list"
                | "mobile.workspaceQuickOpen.start"
                | "mobile.workspaceSearch.run"
                | "mobile.workspaceSearch.replace"
                | "mobile.workspaceSearch.cancel"
        )
}

/// Verbs that had a one-shot `ssh` implementation before the link existed.
/// When the link cannot be opened they fall back to it, so a host whose
/// `runtime-attach` fails still lists and reads files as it did before.
fn has_legacy_ssh_fallback(request_type: &str) -> bool {
    matches!(
        request_type,
        "workspace.files.list"
            | "workspace.files.read"
            | "mobile.workspaceExplorer.list"
            | "mobile.workspaceFile.read"
    )
}

/// Forwards a workspace-scoped request to the satellite that owns the
/// workspace. `Ok(None)` means the request is local (or must take the legacy
/// path) and the caller handles it as before.
pub(crate) async fn forward_workspace_scoped_request(
    store: &RuntimeStore,
    links: &HostLinkRegistry,
    request_type: &str,
    payload: &Value,
) -> HostResult<Option<Value>> {
    if request_type == "mobile.workspaceQuickOpen.search" {
        let Some(session_id) = payload.get("sessionId").and_then(Value::as_str) else {
            return Ok(None);
        };
        let Some(host_id) = links.remote_session_host(session_id) else {
            return Ok(None);
        };
        let link = links.link(&host_id).await?;
        return link
            .request_with_timeout(
                request_type,
                payload.clone(),
                crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
            )
            .await
            .map(Some);
    }
    if !is_host_scoped_workspace_verb(request_type) {
        return Ok(None);
    }
    let Some(workspace_id) = payload.get("workspaceId").and_then(Value::as_str) else {
        return Ok(None);
    };
    let workspace = store
        .find_workspace(workspace_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let Some(workspace) = workspace else {
        return Ok(None);
    };
    if !crate::ssh_remote::is_remote_host_id(Some(&workspace.host_id)) {
        return Ok(None);
    }
    let link = match mirror_workspace(store, links, workspace_id).await {
        Ok((link, _)) => link,
        Err(error) if has_legacy_ssh_fallback(request_type) => {
            tracing::warn!(
                target: "host_link",
                host_id = workspace.host_id,
                request_type,
                "host link unavailable, using the one-shot ssh path: {error}"
            );
            return Ok(None);
        }
        Err(error) => return Err(error),
    };
    let pull_request =
        super::remote_pull_request_routing::is_forwarded_pull_request_verb(request_type);
    let forwarded = if pull_request {
        super::remote_pull_request_routing::hub_pull_request_payload(store, workspace_id, payload)
            .await?
    } else {
        payload.clone()
    };
    let value = link
        .request_with_timeout(
            request_type,
            forwarded,
            forwarded_request_timeout(request_type),
        )
        .await?;
    if pull_request {
        super::remote_pull_request_routing::adopt_satellite_linked_review(
            store,
            workspace_id,
            request_type,
            &value,
        )
        .await;
    }
    if request_type == "mobile.workspaceQuickOpen.start" {
        if let Some(session_id) = value.get("sessionId").and_then(Value::as_str) {
            links.note_remote_session(session_id, &workspace.host_id);
        }
    }
    Ok(Some(value))
}

/// Network git verbs wait on the remote's credential helper and transfer, so
/// they get the same budget mobile gives its own fetch, pull and push.
fn forwarded_request_timeout(request_type: &str) -> std::time::Duration {
    if request_type == super::host_process_requests::HOST_PROCESS_RUN {
        // The satellite enforces its own budget per request; the link waits
        // long enough to hear about it rather than racing it.
        return super::host_process_requests::MAX_TIMEOUT + std::time::Duration::from_secs(30);
    }
    match request_type {
        "git.fetch"
        | "git.pull"
        | "git.push"
        | "git.fetchHostedReviewRange"
        | "mobile.git.fetch"
        | "mobile.git.pull"
        | "mobile.git.push"
        | "mobile.git.sync"
        | "mobile.pullRequest.create"
        | "mobile.pullRequest.ship" => std::time::Duration::from_secs(5 * 60),
        _ => crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
    }
}

/// Quick Open sessions are stopped best-effort: the caller gets its answer at
/// once and the satellite is told on a spawned task, because the stop is a
/// synchronous actor verb and a slow link must not stall the actor.
pub(crate) fn stop_remote_quick_open_session(links: &HostLinkRegistry, session_id: &str) -> bool {
    let Some(host_id) = links.forget_remote_session(session_id) else {
        return false;
    };
    let links = links.clone();
    let payload = serde_json::json!({ "sessionId": session_id });
    tokio::spawn(async move {
        if let Ok(link) = links.link(&host_id).await {
            let _ = link
                .request_with_timeout(
                    "mobile.workspaceQuickOpen.stop",
                    payload,
                    crate::terminal_host::host_link::DEFAULT_REQUEST_TIMEOUT,
                )
                .await;
        }
    });
    true
}
