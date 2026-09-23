//! `alera workspace setup`: applies a project's worktree setup to an existing
//! workspace through the runtime host.
//!
//! The deferred setup script the desktop runs in its "Setup" terminal calls
//! this with `--copies-only`, so copy rules and `.worktreeinclude` matches keep
//! their Rust validation instead of being rewritten in shell.

use serde_json::{json, Value};

use crate::cli::WorkspaceSetupArgs;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::{print_error, print_value};

pub(crate) fn print_recovery(
    items: &[alera_core::runtime::WorkspaceRelocationRecovery],
    json_output: bool,
) {
    if json_output {
        print_value(
            &json!({"kind": "workspaceRelocationRecovery", "items": items}),
            true,
            "",
        );
        return;
    }
    if items.is_empty() {
        println!("No relocation history for this task.");
    }
    for item in items {
        if item.setup_cancellation_requested {
            println!("{}: Setup cancellation requested", item.relocation.id);
        }
        let setup = match item.setup.as_ref() {
            None => "Not prepared",
            Some(receipt) => match receipt.report.as_ref() {
                Some(report) if report.steps.iter().all(|step| step.succeeded) => "Completed",
                Some(_) => "Failed",
                None if receipt.attempt_id.is_some() => "Unconfirmed",
                None => "Pending",
            },
        };
        println!(
            "{}: {:?}; Setup: {setup}\n  {} -> {}",
            item.relocation.id,
            item.relocation.phase,
            item.relocation.source.path,
            item.relocation.destination.path
        );
        if let Some(attempt) = item
            .setup
            .as_ref()
            .and_then(|receipt| receipt.attempt_id.as_deref())
        {
            println!("  Setup Attempt: {attempt}");
        }
        for process in &item.setup_root_processes {
            println!(
                "  Command {} Root: {:?}; PID: {:?}; Start Marker: {:?}",
                process.command_index + 1,
                process.phase,
                process.pid,
                process.start_marker
            );
        }
        for observation in &item.setup_root_observations {
            println!(
                "  Command {} Root Now: {:?}; {}",
                observation.command_index + 1,
                observation.state,
                observation.reason
            );
        }
        for process in &item.setup_descendants {
            println!(
                "  Command {} Descendant: {}; Start Marker: {}; Exit Verified: {}",
                process.command_index + 1,
                process.pid,
                process.start_marker,
                process.exit_verified
            );
        }
    }
}

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
        "relocationId": args.relocation_id,
        "attemptId": args.attempt_id,
    });
    let operation = if args.recover {
        "workspace.recoverRelocationSetup"
    } else if args.cancel {
        "workspace.cancelRelocationSetup"
    } else if args.prepare {
        "workspace.prepareRelocationSetup"
    } else {
        "workspace.runSetup"
    };
    let value: Value = client
        .request_value(operation, &payload)
        .await
        .map_err(print_error)?;
    if args.cancel {
        print_value(&value, json_output, "Cancellation requested; process closure is not yet confirmed. Inspect workspace recovery for its current state.");
        return Ok(());
    }
    if args.prepare {
        if json_output {
            print_value(&value, true, "");
        } else if let Some(command) = value.get("deferredSetupCommand").and_then(Value::as_str) {
            println!("{command}");
        } else {
            println!("Setup has no pending commands; inspect its recorded report with workspace recovery.");
        }
        return Ok(());
    }
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
        return value
            .get("steps")
            .and_then(Value::as_array)
            .is_some_and(|steps| {
                steps
                    .iter()
                    .any(|step| step.get("succeeded").and_then(Value::as_bool) != Some(true))
            })
            .then_some(1);
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
        if let Some(output) = step.get("stdoutTail").and_then(Value::as_str) {
            println!("{output}");
        }
        if let Some(output) = step.get("stderrTail").and_then(Value::as_str) {
            eprintln!("{output}");
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn setup_launcher_preparation_requires_a_receipt_and_rejects_copy_only_mode() {
        let base = ["alera", "workspace", "setup", "--id", "task", "--prepare"];
        assert!(crate::cli::Cli::try_parse_from(base).is_err());
        let args = base.into_iter().chain(["--relocation-id", "relocation"]);
        assert!(crate::cli::Cli::try_parse_from(args.clone()).is_ok());
        assert!(crate::cli::Cli::try_parse_from(args.chain(["--copies-only"])).is_err());
    }

    #[test]
    fn json_setup_report_preserves_failure_exit_status() {
        assert_eq!(
            print_workspace_setup_report(&json!({"steps": [{"succeeded": false}]}), true),
            Some(1)
        );
        assert_eq!(
            print_workspace_setup_report(&json!({"steps": [{"succeeded": true}]}), true),
            None
        );
    }

    #[test]
    fn setup_recovery_requires_exact_scope_and_cannot_run_commands() {
        let base = ["alera", "workspace", "setup", "--id", "task", "--recover"];
        assert!(crate::cli::Cli::try_parse_from(base).is_err());
        let args =
            base.into_iter()
                .chain(["--relocation-id", "relocation", "--attempt-id", "attempt"]);
        assert!(crate::cli::Cli::try_parse_from(args.clone()).is_ok());
        for incompatible in ["--prepare", "--cancel", "--copies-only"] {
            assert!(crate::cli::Cli::try_parse_from(args.clone().chain([incompatible])).is_err());
        }
        assert!(crate::cli::Cli::try_parse_from([
            "alera",
            "workspace",
            "setup",
            "--id",
            "task",
            "--relocation-id",
            "relocation",
            "--attempt-id",
            "attempt"
        ])
        .is_err());
    }

    #[test]
    fn setup_cancellation_requires_the_exact_attempt_and_cannot_prepare_or_copy() {
        let base = [
            "alera",
            "workspace",
            "setup",
            "--id",
            "task",
            "--relocation-id",
            "relocation",
            "--cancel",
        ];
        assert!(crate::cli::Cli::try_parse_from(base).is_err());
        let args = base.into_iter().chain(["--attempt-id", "attempt"]);
        assert!(crate::cli::Cli::try_parse_from(args.clone()).is_ok());
        assert!(crate::cli::Cli::try_parse_from(args.clone().chain(["--prepare"])).is_err());
        assert!(crate::cli::Cli::try_parse_from(args.chain(["--copies-only"])).is_err());
    }
}
