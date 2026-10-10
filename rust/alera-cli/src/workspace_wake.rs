//! `alera workspace wake`: start again the terminals a sleep stopped, as
//! opening the workspace in the app does. The host attaches each slept tab
//! from its record (`workspace.wake`), so agent tabs resume their sessions.

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{IdArgs, RuntimeDirArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_WORKSPACE_WAKE_CAPABILITY;

/// Starting a terminal can wait on the login shell and on agent hooks.
const WAKE_DEADLINE_MS: u64 = 45_000;

pub async fn run(runtime: RuntimeDirArgs, args: IdArgs, json_output: bool) -> i32 {
    match wake(&runtime, args.id.trim()).await {
        Ok(value) => {
            let count = value["woken"].as_array().map_or(0, Vec::len);
            let message = if value["wasAsleep"] == true {
                format!("workspace woke: {count} terminals started")
            } else {
                "workspace was not asleep".to_string()
            };
            crate::print_value(&value, json_output, &message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn wake(runtime: &RuntimeDirArgs, id: &str) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_WORKSPACE_WAKE_CAPABILITY,
    )
    .await?;
    client
        .request_value_with_deadline(
            "workspace.wake",
            &json!({ "workspaceId": id }),
            WAKE_DEADLINE_MS,
        )
        .await
}
