use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::{
    request_value, request_value_with_capability, terminal_handle_env, usage_error,
    workspace_id_env, WAIT_CLIENT_GRACE_MS,
};
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY;

pub(crate) async fn run_agent_spawn(
    runtime: &RuntimeDirArgs,
    args: crate::cli_orchestration::OrchestrationAgentSpawnArgs,
    json_output: bool,
) -> i32 {
    let Some(from) = args.from.or_else(terminal_handle_env) else {
        return usage_error("--from is required (or set ALERA_TERMINAL_HANDLE).");
    };
    let Some(workspace) = args.workspace.or_else(workspace_id_env) else {
        return usage_error(
            "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).",
        );
    };
    let timeout_ms = args.timeout_ms;
    let value = match request_value_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
        "orchestration.agentSpawn",
        json!({
            "workspace": workspace,
            "agent": args.agent,
            "task": args.task,
            "title": args.title,
            "terminal": args.terminal,
            "command": args.command,
            "from": from,
            "keepOnFailure": args.keep_on_failure,
        }),
        None,
    )
    .await
    {
        Ok(value) => value,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let Some(handle) = value
        .get("terminalHandle")
        .or_else(|| value.get("assigneeHandle"))
        .and_then(Value::as_str)
    else {
        if json_output {
            println!("{value}");
        }
        return 0;
    };
    run_terminal_wait(
        runtime,
        handle,
        "dispatch-accepted",
        timeout_ms,
        json_output,
        true,
    )
    .await
}

pub(crate) async fn run_terminal_wait(
    runtime: &RuntimeDirArgs,
    terminal: &str,
    target: &str,
    timeout_ms: u64,
    json_output: bool,
    reconcile_spawn_timeout: bool,
) -> i32 {
    let value = match request_value_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
        "orchestration.terminalWait",
        json!({
            "terminal": terminal,
            "target": target,
            "timeoutMs": timeout_ms,
        }),
        Some(timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
    )
    .await
    {
        Ok(value) => value,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let outcome = terminal_wait_outcome(&value);
    if reconcile_spawn_timeout && matches!(outcome, "timeout" | "failed") {
        reconcile_agent_spawn_failure(runtime, terminal).await;
    }
    print_terminal_wait_result(&value, json_output)
}

pub(crate) fn terminal_wait_outcome(value: &Value) -> &str {
    value
        .get("outcome")
        .and_then(Value::as_str)
        .unwrap_or("failed")
}

pub(crate) fn terminal_wait_exit_code(value: &Value) -> i32 {
    i32::from(terminal_wait_outcome(value) == "failed")
}

pub(crate) fn print_terminal_wait_result(value: &Value, json_output: bool) -> i32 {
    if json_output {
        println!("{value}");
    } else {
        let (message, stderr) = terminal_wait_text(value);
        if stderr {
            eprintln!("{message}");
        } else {
            println!("{message}");
        }
    }
    terminal_wait_exit_code(value)
}

fn terminal_wait_text(value: &Value) -> (String, bool) {
    let outcome = terminal_wait_outcome(value);
    if outcome == "failed" {
        (
            value
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("terminal startup failed")
                .to_string(),
            true,
        )
    } else if outcome == "reached" {
        let message = value
            .get("state")
            .and_then(Value::as_str)
            .filter(|state| !state.is_empty())
            .map(|state| format!("reached: {state}"))
            .unwrap_or_else(|| outcome.to_string());
        (message, false)
    } else {
        (outcome.to_string(), false)
    }
}

async fn reconcile_agent_spawn_failure(runtime: &RuntimeDirArgs, terminal: &str) {
    let _ = request_value(
        runtime,
        "orchestration.agentSpawnTimeout",
        json!({ "terminal": terminal }),
        None,
    )
    .await;
}

#[cfg(test)]
pub(crate) fn terminal_startup_error(terminal: &Value) -> Option<&str> {
    (terminal.get("startupState").and_then(Value::as_str) == Some("failed")).then(|| {
        terminal
            .get("startupError")
            .and_then(Value::as_str)
            .unwrap_or("terminal startup failed")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_wait_exit_code_distinguishes_failures() {
        assert_eq!(terminal_wait_exit_code(&json!({"outcome": "failed"})), 1);
        assert_eq!(terminal_wait_exit_code(&json!({"outcome": "reached"})), 0);
        assert_eq!(terminal_wait_exit_code(&json!({"outcome": "timeout"})), 0);
        assert_eq!(terminal_wait_exit_code(&json!({})), 1);
    }

    #[test]
    fn terminal_wait_text_reports_outcome_and_startup_error() {
        assert_eq!(
            terminal_wait_text(&json!({"outcome": "reached", "state": "agent_ready"})),
            ("reached: agent_ready".to_string(), false)
        );
        assert_eq!(
            terminal_wait_text(&json!({"outcome": "reached", "state": "process_started"})),
            ("reached: process_started".to_string(), false)
        );
        assert_eq!(
            terminal_wait_text(&json!({"outcome": "reached"})),
            ("reached".to_string(), false)
        );
        assert_eq!(
            terminal_wait_text(&json!({"outcome": "timeout"})),
            ("timeout".to_string(), false)
        );
        assert_eq!(
            terminal_wait_text(&json!({"outcome": "failed", "error": "agent exited"})),
            ("agent exited".to_string(), true)
        );
        assert_eq!(
            terminal_wait_text(&json!({})),
            ("terminal startup failed".to_string(), true)
        );
    }
}
