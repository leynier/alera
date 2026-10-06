//! `alera workspace sleep`.
//!
//! Sends the running host's `workspace.sleep`, the same verb the desktop and
//! mobile Sleep actions use: the host stops the workspace's terminal sessions,
//! keeps its tab records, layout, branch, and files, records which terminals it
//! stopped (`workspace.sleptTabs`), and broadcasts the change. Unlike archive,
//! the workspace stays visible in the sidebar. Without a running host there are
//! no live sessions, so the store fallback records the same sleep state the
//! host would; a host that is alive but unreachable fails the command instead.

use std::path::Path;

use alera_core::runtime::{
    RuntimeStore, Workspace, WorkspaceStatus, WorkspaceTabRecord, LOCAL_HOST_ID,
};
use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use serde_json::json;

use crate::cli::IdArgs;
use crate::runtime_host_client::RuntimeHostRpcClient;

/// Every request is bounded, so a host that accepts the connection and then
/// stops answering fails the command instead of hanging it.
#[cfg(not(test))]
const LOOKUP_DEADLINE_MS: u64 = 10_000;
#[cfg(test)]
const LOOKUP_DEADLINE_MS: u64 = 500;
/// The host answers a sleep once it stopped every session and flushed its
/// history.
const SLEEP_DEADLINE_MS: u64 = 60_000;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct WorkspaceSleepOutcome {
    pub(crate) workspace: Workspace,
    /// Terminal tabs the sleep stopped. Their records stay, so they restart on wake.
    pub(crate) slept_tab_ids: Vec<String>,
    /// False when no runtime host was running, so no session was live to stop.
    pub(crate) runtime_host: bool,
}

pub async fn run(runtime_dir: &Path, args: IdArgs, json_output: bool) -> i32 {
    let calling_workspace_id = crate::orchestration_commands::workspace_id_env();
    match sleep(runtime_dir, &args.id, calling_workspace_id.as_deref()).await {
        Ok(outcome) => {
            let message = sleep_message(&outcome);
            crate::print_value(&outcome, json_output, &message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

pub(crate) async fn sleep(
    runtime_dir: &Path,
    id: &str,
    calling_workspace_id: Option<&str>,
) -> Result<WorkspaceSleepOutcome> {
    let id = id.trim();
    if id.is_empty() {
        bail!("--id cannot be empty.");
    }
    if calling_workspace_id == Some(id) {
        bail!(
            "Refusing to sleep workspace {id} from one of its own terminals: sleeping it would stop this terminal too. Run the command from another workspace or use Sleep in the app."
        );
    }
    if let Some(mut client) = RuntimeHostRpcClient::connect(runtime_dir).await? {
        let workspace: Option<Workspace> = serde_json::from_value(
            client
                .request_value_with_deadline(
                    "workspace.find",
                    &json!({ "id": id }),
                    LOOKUP_DEADLINE_MS,
                )
                .await?,
        )?;
        let workspace = require_sleepable(workspace, id)?;
        let tabs: Vec<WorkspaceTabRecord> = serde_json::from_value(
            client
                .request_value_with_deadline(
                    "tab.list",
                    &json!({ "workspaceId": id }),
                    LOOKUP_DEADLINE_MS,
                )
                .await?,
        )?;
        client
            .request_value_with_deadline(
                "workspace.sleep",
                &json!({ "workspaceId": id }),
                SLEEP_DEADLINE_MS,
            )
            .await
            .map_err(|error| anyhow!("{error}. The host may still finish the sleep."))?;
        // The host's own record also counts a terminal opened after the list
        // above; an older host without it, or one that stops answering now
        // that the sleep is done, leaves only that list.
        let recorded = client
            .request_value_with_deadline("workspace.sleptTabs", &json!({}), LOOKUP_DEADLINE_MS)
            .await
            .ok()
            .and_then(|slept| slept.get(id).cloned())
            .and_then(|tab_ids| serde_json::from_value::<Vec<String>>(tab_ids).ok());
        return Ok(WorkspaceSleepOutcome {
            workspace,
            slept_tab_ids: recorded.unwrap_or_else(|| terminal_tab_ids(&tabs)),
            runtime_host: true,
        });
    }
    // Recording the sleep without a host is only right when no host owns
    // sessions; one that did not answer would keep them running.
    if let Some(owner) = crate::terminal_host::runtime_owner::live_owner_identity(runtime_dir)? {
        bail!(
            "The Alera runtime host (process {}) is running but did not answer, so its terminals cannot be stopped. Retry, or restart Alera.",
            owner.pid
        );
    }
    let store = RuntimeStore::open(runtime_dir).await?;
    let workspace = require_sleepable(store.find_workspace(id).await?, id)?;
    store
        .record_workspace_activity(id, chrono::Utc::now())
        .await?;
    let slept_tab_ids = store.record_workspace_sleep(id).await?;
    Ok(WorkspaceSleepOutcome {
        workspace,
        slept_tab_ids,
        runtime_host: false,
    })
}

fn require_sleepable(workspace: Option<Workspace>, id: &str) -> Result<Workspace> {
    let Some(workspace) = workspace else {
        bail!("Workspace not found: {id}");
    };
    if workspace.status != WorkspaceStatus::Active {
        bail!("Workspace is not active: {id}");
    }
    // The hub's `workspace.sleep` stops only the sessions it owns; a remote
    // host's satellite runtime keeps its terminals running.
    if workspace.host_id != LOCAL_HOST_ID {
        bail!(
            "Workspace {id} runs on SSH host {}, and its terminals belong to that host's runtime, which this command cannot stop yet.",
            workspace.host_id
        );
    }
    if workspace.is_archived {
        bail!(
            "Workspace {id} is archived, so its sessions are already stopped. Unarchive it first to keep it visible while asleep."
        );
    }
    Ok(workspace)
}

/// The same rule the host applies when it records a sleep.
fn terminal_tab_ids(tabs: &[WorkspaceTabRecord]) -> Vec<String> {
    tabs.iter()
        .filter(|tab| tab.kind == "terminal")
        .map(|tab| tab.id.clone())
        .collect()
}

fn sleep_message(outcome: &WorkspaceSleepOutcome) -> String {
    let count = outcome.slept_tab_ids.len();
    let terminals = if count == 1 { "terminal" } else { "terminals" };
    if outcome.runtime_host {
        format!("workspace slept: {count} {terminals} stopped; tabs, branch, and files preserved")
    } else {
        format!(
            "workspace slept: no runtime host was running, {count} {terminals} marked asleep; tabs, branch, and files preserved"
        )
    }
}

#[cfg(test)]
#[path = "workspace_sleep_tests.rs"]
mod tests;
