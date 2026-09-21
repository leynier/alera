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
