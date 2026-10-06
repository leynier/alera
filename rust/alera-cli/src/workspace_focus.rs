//! `alera workspace focus`.
//!
//! Sends the running host's `workspace.focus`, which hands the request to the
//! connected desktop app. There is no store fallback and the command never
//! starts a host: a host started here would have no app to show anything in.

use std::path::Path;

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{RuntimeDirArgs, WorkspaceFocusArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_WORKSPACE_FOCUS_CAPABILITY;
use crate::workspace_context::resolve_requested_workspace_id;

pub async fn run(runtime: &RuntimeDirArgs, args: WorkspaceFocusArgs, json_output: bool) -> i32 {
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
    match focus(&crate::runtime_dir(runtime), &id).await {
        Ok(value) => {
            crate::print_value(&value, json_output, &focus_summary(&value));
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn focus(runtime_dir: &Path, id: &str) -> Result<Value> {
    let Some(mut client) = RuntimeHostRpcClient::connect_with_required_capability(
        runtime_dir,
        RUNTIME_HOST_WORKSPACE_FOCUS_CAPABILITY,
    )
    .await?
    else {
        // A live host without the capability is already refused above.
        anyhow::bail!("Alera is not running for this runtime. Open Alera and try again.");
    };
    client
        .request_value("workspace.focus", &json!({ "workspaceId": id }))
        .await
}

fn focus_summary(value: &Value) -> String {
    let name = value
        .get("name")
        .and_then(Value::as_str)
        .or_else(|| value.get("workspaceId").and_then(Value::as_str))
        .unwrap_or("workspace");
    format!("focus requested for {name} in Alera")
}

#[cfg(test)]
#[path = "workspace_focus_tests.rs"]
mod tests;
