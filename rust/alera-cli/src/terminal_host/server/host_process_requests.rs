//! `host.process.run`: runs a tool for a workspace on the host that owns its
//! checkout. Local clients only; this verb is not on the mobile allowlist and
//! MUST NOT be added to it, because it executes whatever the caller names.
//!
//! The desktop's `ProcessRunner` uses it for a remote workspace (forge CLIs
//! such as `gh`, `glab` and `az`), and Watch and Fix uses it to merge on the
//! satellite. The command is built by `alera_core::shell_command`, the same
//! code the desktop bridge spawns through, so a tool that resolves through a
//! `.cmd` shim on Windows or the user's login-shell `PATH` on macOS behaves the
//! way it would have if the checkout were local.
//!
//! `cwd` defaults to the workspace root and may only name a directory inside
//! it: the workspace is the scope the caller was granted, not the whole host.

use std::collections::{BTreeMap, HashMap};
use std::process::Stdio;
use std::time::Duration;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_workspace_file_requests::workspace_for_mobile_file_request;
use super::requests::{optional_string_key, require_string_key};
use super::workspace_git_requests::path_is_within;

pub(super) const HOST_PROCESS_RUN: &str = "host.process.run";

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(120);
/// The longest a forwarded tool may run; a forge CLI that has not answered
/// in this time is not going to, and the hub's own forwarding budget is sized
/// to outlive it.
pub(super) const MAX_TIMEOUT: Duration = Duration::from_secs(10 * 60);
/// Output is captured whole because the caller reads it whole; a tool that
/// prints more than this is not something a `ProcessRunner.run` call wanted.
const MAX_OUTPUT_BYTES: usize = 16 * 1024 * 1024;

pub(super) async fn handle_host_process_run(
    runtime_store: &RuntimeStore,
    payload: &Value,
) -> HostResult<Value> {
    let workspace = workspace_for_mobile_file_request(runtime_store, payload).await?;
    let executable = require_string_key(payload, "executable")?;
    let arguments = string_list(payload, "arguments")?;
    let cwd = optional_string_key(payload, "cwd").unwrap_or_else(|| workspace.path.clone());
    if !path_is_within(&workspace.path, &cwd) {
        return Err(HostError::state(format!(
            "Working directory {cwd} is outside workspace {}",
            workspace.path
        )));
    }
    let environment = environment_map(payload)?;
    let stdin = payload
        .get("stdin")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let timeout = payload
        .get("timeoutMs")
        .and_then(Value::as_u64)
        .map(Duration::from_millis)
        .unwrap_or(DEFAULT_TIMEOUT)
        .min(MAX_TIMEOUT);

    let mut command = alera_core::shell_command::shell_command(
        &executable,
        &arguments,
        Some(&cwd),
        Some(&environment),
        true,
    );
    // The satellite starts detached, so a GUI-launched sidecar has none of the
    // user's shell exports; the login-shell environment is what puts `gh` on
    // PATH. Explicit variables from the caller still win.
    crate::login_shell_environment::apply_login_shell_environment(
        &mut command,
        &environment
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect::<BTreeMap<_, _>>(),
    )
    .await;
    command
        .stdin(if stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command
        .spawn()
        .map_err(|error| HostError::state(format!("failed to run {executable}: {error}")))?;
    if let Some(stdin) = stdin {
        if let Some(mut pipe) = child.stdin.take() {
            // A tool that exits without reading stdin closes the pipe; that is
            // its answer, not an error of ours.
            let _ = pipe.write_all(stdin.as_bytes()).await;
            let _ = pipe.shutdown().await;
        }
    }
    let output = match tokio::time::timeout(timeout, child.wait_with_output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(error)) => {
            return Err(HostError::state(format!(
                "failed to run {executable}: {error}"
            )))
        }
        Err(_) => {
            return Err(HostError::state(format!(
                "{executable} timed out after {}s on the workspace host.",
                timeout.as_secs()
            )))
        }
    };
    Ok(json!({
        "exitCode": output.status.code().unwrap_or(-1),
        "stdout": bounded_lossy(&output.stdout),
        "stderr": bounded_lossy(&output.stderr),
    }))
}

fn string_list(payload: &Value, key: &str) -> HostResult<Vec<String>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(Vec::new()),
        Some(Value::Array(items)) => items
            .iter()
            .map(|item| {
                item.as_str()
                    .map(str::to_owned)
                    .ok_or_else(|| HostError::format(format!("{key} must be a list of strings")))
            })
            .collect(),
        Some(_) => Err(HostError::format(format!(
            "{key} must be a list of strings"
        ))),
    }
}

fn environment_map(payload: &Value) -> HostResult<HashMap<String, String>> {
    match payload.get("environment") {
        None | Some(Value::Null) => Ok(HashMap::new()),
        Some(Value::Object(entries)) => entries
            .iter()
            .map(|(key, value)| {
                value
                    .as_str()
                    .map(|value| (key.clone(), value.to_owned()))
                    .ok_or_else(|| {
                        HostError::format("environment values must be strings".to_string())
                    })
            })
            .collect(),
        Some(_) => Err(HostError::format(
            "environment must be an object of strings".to_string(),
        )),
    }
}

fn bounded_lossy(bytes: &[u8]) -> String {
    let end = bytes.len().min(MAX_OUTPUT_BYTES);
    String::from_utf8_lossy(&bytes[..end]).into_owned()
}

#[cfg(test)]
#[path = "host_process_requests_tests.rs"]
mod tests;
