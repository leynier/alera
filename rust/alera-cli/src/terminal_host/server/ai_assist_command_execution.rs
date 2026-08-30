use super::ai_assist_failure_detail::ai_assist_failure_detail;
use super::ai_assist_requests::AiAssistCommandPlan;
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::child_process::windowless_async_command;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::sync::oneshot;
const MAX_OUTPUT_BYTES: usize = 1024 * 1024;

pub(super) async fn run_command(
    plan: AiAssistCommandPlan,
    working_directory: &str,
    timeout_seconds: u64,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<String> {
    let mut command = windowless_async_command(&plan.binary);
    command
        .args(&plan.arguments)
        .current_dir(working_directory)
        .kill_on_drop(true)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(if plan.stdin_payload.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    crate::login_shell_environment::apply_login_shell_environment(
        &mut command,
        &plan
            .environment
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
    )
    .await;
    // Internal generation must never identify as a user terminal or emit its hooks.
    for key in [
        "ALERA_TERMINAL_SESSION_ID",
        "ALERA_WORKSPACE_ID",
        "ALERA_TAB_ID",
        "ALERA_AGENT_HOOK_ENDPOINT",
        "ALERA_AGENT_HOOK_PORT",
        "ALERA_AGENT_HOOK_TOKEN",
        "ALERA_RUNTIME_DIR",
    ] {
        command.env_remove(key);
    }
    let mut child = command.spawn().map_err(|_| {
        HostError::state(format!(
            "{} could not be started. Check that {} is installed and on PATH.",
            plan.label, plan.binary
        ))
    })?;
    if let Some(payload) = plan.stdin_payload {
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| HostError::state("AI Assist process stdin is unavailable."))?;
        stdin
            .write_all(payload.as_bytes())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
    }
    let output_future = child.wait_with_output();
    tokio::pin!(output_future);
    let result = tokio::select! {
        _ = cancel_rx => Err(HostError::state("AI Assist was canceled.")),
        _ = tokio::time::sleep(Duration::from_secs(timeout_seconds)) => {
            Err(HostError::state(format!("AI Assist timed out after {timeout_seconds}s.")))
        }
        output = &mut output_future => {
            let output = output.map_err(|error| HostError::state(error.to_string()))?;
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let detail = ai_assist_failure_detail(&stdout, &stderr);
                Err(HostError::state(match detail {
                    Some(detail) => format!("{} failed: {detail}", plan.label),
                    None => format!(
                        "{} failed. Check the agent CLI configuration and try again.",
                        plan.label
                    ),
                }))
            } else if output.stdout.len() > MAX_OUTPUT_BYTES {
                Err(HostError::state(format!("{} returned too much output.", plan.label)))
            } else {
                Ok(stdout)
            }
        }
    };
    if let Some(directory) = plan.temporary_directory {
        let _ = std::fs::remove_dir_all(directory);
    }
    result
}
