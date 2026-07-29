//! `alera workspace setup`: applies a project's worktree setup to an existing
//! workspace through the runtime host.
//!
//! The deferred setup script the desktop runs in its "Setup" terminal calls
//! this with `--copies-only`, so the copy rules keep their Rust validation
//! instead of being rewritten in shell.

use serde_json::{json, Value};

use crate::cli::WorkspaceSetupArgs;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::{print_error, print_value};

/// Runs the command. The error carries the process exit code, so a failed step
/// is reported to whatever shell invoked the script.
pub(crate) async fn run(
    mut client: RuntimeHostRpcClient,
    args: WorkspaceSetupArgs,
    json_output: bool,
) -> Result<(), i32> {
    let payload = json!({
        "id": args.id,
        "copiesOnly": args.copies_only,
    });
    let value: Value = client
        .request_value("workspace.runSetup", &payload)
        .await
        .map_err(print_error)?;
    match print_workspace_setup_report(&value, json_output) {
        Some(exit_code) => Err(exit_code),
        None => Ok(()),
    }
}

/// Prints a `WorktreeSetupReport` one line per step, which is how the Setup
/// terminal shows the copy rules. Returns a non-zero exit code when a step
/// failed, and `None` when the caller should keep going.
fn print_workspace_setup_report(value: &Value, json_output: bool) -> Option<i32> {
    if json_output {
        print_value(value, true, "");
        return None;
    }
    let steps = value
        .get("steps")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut failed = false;
    for step in steps {
        let label = step.get("label").and_then(Value::as_str).unwrap_or("");
        let kind = step.get("kind").and_then(Value::as_str).unwrap_or("step");
        if step.get("succeeded").and_then(Value::as_bool) == Some(true) {
            println!("> {kind} {label}");
            continue;
        }
        failed = true;
        let message = step
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("failed");
        eprintln!("> {kind} {label}: {message}");
    }
    failed.then_some(1)
}
