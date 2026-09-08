use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::cli::{RuntimeDirArgs, WorkspaceHandOffArgs, WorkspaceHandOnArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY;
use crate::workspace_context::requested_workspace_id;

pub async fn run_hand_off(
    runtime: RuntimeDirArgs,
    args: WorkspaceHandOffArgs,
    json_output: bool,
) -> i32 {
    match run_hand_off_inner(&runtime, args, json_output).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

pub async fn run_hand_on(
    runtime: RuntimeDirArgs,
    args: WorkspaceHandOnArgs,
    json_output: bool,
) -> i32 {
    match run_hand_on_inner(&runtime, args, json_output).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

async fn run_hand_off_inner(
    runtime: &RuntimeDirArgs,
    args: WorkspaceHandOffArgs,
    json_output: bool,
) -> Result<()> {
    let id = requested_workspace_id(args.id.as_deref()).ok_or_else(|| {
        anyhow!(
            "--id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        )
    })?;
    let payload = json!({
        "id": id,
        "branch": args.branch,
        "name": args.name,
        "reuseExistingBranch": args.reuse_existing_branch,
        "workspaceRoot": crate::host_accessible_optional_string_path(args.workspace_root)?,
        "path": crate::host_accessible_optional_string_path(args.path)?,
    });
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    )
    .await?;
    let value: Value = client.request_value("workspace.handOff", &payload).await?;
    crate::print_value(&value, json_output, "workspace handed off");
    Ok(())
}

async fn run_hand_on_inner(
    runtime: &RuntimeDirArgs,
    args: WorkspaceHandOnArgs,
    json_output: bool,
) -> Result<()> {
    let id = requested_workspace_id(args.id.as_deref()).ok_or_else(|| {
        anyhow!(
            "--id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        )
    })?;
    let payload = json!({
        "id": id,
        "closeSessions": true,
    });
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    )
    .await?;
    let value: Value = client.request_value("workspace.handOn", &payload).await?;
    crate::print_value(&value, json_output, "workspace handed on");
    Ok(())
}
