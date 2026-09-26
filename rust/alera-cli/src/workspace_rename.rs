//! `alera workspace rename`.
//!
//! Goes through the running host's `workspace.rename`, which broadcasts
//! `workspacesChanged` so desktop and mobile refresh the sidebar; otherwise
//! edits the runtime store directly, the same fallback `workspace pin` uses.

use std::path::Path;

use alera_core::runtime::{RuntimeStore, Workspace};
use anyhow::Result;
use serde_json::json;

use crate::cli::{RuntimeDirArgs, WorkspaceRenameArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::workspace_context::resolve_requested_workspace_id;

pub async fn run(runtime: &RuntimeDirArgs, args: WorkspaceRenameArgs, json_output: bool) -> i32 {
    let id = match resolve_requested_workspace_id(runtime, args.id.as_deref()).await {
        Ok(Some(id)) => id,
        Ok(None) => {
            eprintln!(
                "--id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
            );
            return crate::USAGE_EXIT_CODE;
        }
        Err(error) => return crate::print_error(error),
    };
    match rename(&crate::runtime_dir(runtime), &id, &args.name).await {
        Ok(workspace) => {
            crate::print_value(
                &workspace,
                json_output,
                &format!("workspace renamed to {}", workspace.name),
            );
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn rename(runtime_dir: &Path, id: &str, name: &str) -> Result<Workspace> {
    let name = name.trim();
    if name.is_empty() {
        anyhow::bail!("Workspace name cannot be empty.");
    }
    if let Some(mut client) = RuntimeHostRpcClient::connect(runtime_dir).await? {
        return client
            .request(
                "workspace.rename",
                &json!({ "workspaceId": id, "name": name }),
            )
            .await;
    }
    RuntimeStore::open(runtime_dir)
        .await?
        .rename_workspace(id, name)
        .await
}

#[cfg(test)]
#[path = "workspace_rename_tests.rs"]
mod tests;
