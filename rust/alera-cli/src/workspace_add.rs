//! `alera workspace add` — local or remote (`--host-id`) managed worktree create.

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{RuntimeDirArgs, WorkspaceAddArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_REMOTE_SSH_WORKSPACES_CAPABILITY;

pub async fn run(runtime: RuntimeDirArgs, args: WorkspaceAddArgs, json_output: bool) -> i32 {
    let remote = crate::ssh_remote::is_remote_host_id(args.host_id.as_deref());
    let payload = match workspace_add_payload(args) {
        Ok(payload) => payload,
        Err(error) => return crate::print_error(error),
    };
    let client = if remote {
        RuntimeHostRpcClient::connect_or_start_with_required_capability(
            &crate::runtime_dir(&runtime),
            RUNTIME_HOST_REMOTE_SSH_WORKSPACES_CAPABILITY,
        )
        .await
    } else {
        crate::runtime_host_required(&runtime).await
    };
    let value: Value = match client {
        Ok(mut client) => match client
            .request_value("workspace.createManaged", &payload)
            .await
        {
            Ok(value) => value,
            Err(error) => return crate::print_error(error),
        },
        Err(error) => return crate::print_error(error),
    };
    crate::print_value(&value, json_output, "workspace created");
    0
}

fn workspace_add_payload(args: WorkspaceAddArgs) -> Result<Value> {
    let remote = crate::ssh_remote::is_remote_host_id(args.host_id.as_deref());
    Ok(json!({
        "id": args.id,
        "projectId": args.project_id,
        "name": args.name,
        "branch": args.branch,
        "sourceBranch": args.source_branch,
        "reuseExistingBranch": args.reuse_existing_branch,
        "workspaceRoot": if remote {
            crate::normalized_workspace_path_value(args.workspace_root.as_deref().unwrap_or(""))
        } else {
            crate::host_accessible_optional_string_path(args.workspace_root)?
        },
        "path": if remote {
            crate::normalized_workspace_path_value(args.path.as_deref().unwrap_or(""))
        } else {
            crate::host_accessible_optional_string_path(args.path)?
        },
        "parentWorkspaceId": args.parent_workspace_id,
        "hostId": args.host_id,
    }))
}
