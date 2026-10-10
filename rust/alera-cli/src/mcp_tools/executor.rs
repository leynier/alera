//! Runs one catalog tool as a child `alera` process.

use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::sync::oneshot;

use super::origin::ORIGIN_VARIABLE;
use super::{CallOrigin, ToolSpec};

/// One relay frame is capped at 1 MiB, and the result travels inside JSON.
pub(crate) const MAX_STDOUT_BYTES: usize = 768 * 1024;
const MAX_STDERR_BYTES: usize = 32 * 1024;
/// Context a terminal inside Alera exports. A runtime started from such a
/// terminal would otherwise make every tool default to that terminal's
/// workspace or sender.
const CONTEXT_VARIABLES: &[&str] = &[
    "ALERA_WORKSPACE_ID",
    "ALERA_TERMINAL_HANDLE",
    "ALERA_TERMINAL_SESSION_ID",
    "ALERA_TAB_ID",
    "ALERA_AGENT_TYPE",
    "ALERA_AGENT_PROFILE_ID",
    "ALERA_AGENT_CONVERSATION_ID",
    "ALERA_EXTERNAL_INBOX",
    "ALERA_RUNTIME_DIR",
];

#[derive(Debug, Clone)]
pub(crate) struct ToolExecution {
    pub(crate) executable: PathBuf,
    pub(crate) runtime_dir: PathBuf,
}

impl ToolExecution {
    pub(crate) fn current(runtime_dir: PathBuf) -> anyhow::Result<Self> {
        Ok(Self {
            executable: std::env::current_exe()?,
            runtime_dir,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ToolResult {
    pub(crate) text: String,
    pub(crate) is_error: bool,
    /// The result object for clients that read `structuredContent`; errors
    /// carry `{ error: { code, message, retryable } }`.
    pub(crate) structured: Option<Value>,
}

impl ToolResult {
    pub(crate) fn error(text: impl Into<String>) -> Self {
        let text = text.into();
        Self {
            structured: Some(error_object(&text)),
            text,
            is_error: true,
        }
    }

    pub(crate) fn to_mcp(&self) -> Value {
        let mut value = json!({
            "content": [{ "type": "text", "text": self.text }],
            "isError": self.is_error,
        });
        if let Some(structured) = self.structured.as_ref().filter(|value| value.is_object()) {
            value["structuredContent"] = structured.clone();
        }
        value
    }
}

/// Error codes shared by every tool, so a client can branch on them instead
/// of parsing messages.
pub(crate) fn error_code(message: &str) -> (&'static str, bool) {
    let lower = message.to_lowercase();
    if lower.contains("unknown terminal host request") || lower.contains("update alera") {
        ("capability_missing", false)
    } else if lower.contains("did not finish within") {
        ("timeout_pending", true)
    } else if lower.contains("not running") || lower.contains("could not connect") {
        ("runtime_unavailable", true)
    } else if lower.contains("not found")
        || lower.contains("no such")
        || lower.contains("does not exist")
    {
        ("not_found", false)
    } else if lower.contains("already exists") || lower.contains("conflict") {
        ("conflict", false)
    } else if lower.contains("required")
        || lower.contains("invalid")
        || lower.contains("argument")
        || lower.contains("must be")
    {
        ("invalid_argument", false)
    } else if lower.contains("cancelled") {
        ("cancelled", false)
    } else {
        ("failed", false)
    }
}

fn error_object(message: &str) -> Value {
    let (code, retryable) = error_code(message);
    json!({ "error": { "code": code, "message": message, "retryable": retryable } })
}

pub(crate) async fn run_tool(
    execution: &ToolExecution,
    tool: &ToolSpec,
    arguments: &Value,
    origin: &CallOrigin,
    cancelled: Option<oneshot::Receiver<()>>,
) -> ToolResult {
    let invocation = match tool.invocation(arguments) {
        Ok(invocation) => invocation,
        Err(error) => return ToolResult::error(error.0),
    };
    let mut command = windowless_async_command(&execution.executable);
    command
        .arg(invocation.group)
        .arg(format!("--runtime-dir={}", execution.runtime_dir.display()))
        .arg("--json")
        .args(&invocation.args)
        .stdin(if invocation.stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    for variable in CONTEXT_VARIABLES {
        command.env_remove(variable);
    }
    command.env(ORIGIN_VARIABLE, origin.to_env_value());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => return ToolResult::error(format!("Could not start the Alera CLI: {error}")),
    };
    if let (Some(text), Some(mut stdin)) = (invocation.stdin, child.stdin.take()) {
        tokio::spawn(async move {
            let _ = stdin.write_all(text.as_bytes()).await;
            let _ = stdin.shutdown().await;
        });
    }
    let stdout = child
        .stdout
        .take()
        .map(|pipe| tokio::spawn(read_capped(pipe, MAX_STDOUT_BYTES)));
    let stderr = child
        .stderr
        .take()
        .map(|pipe| tokio::spawn(read_capped(pipe, MAX_STDERR_BYTES)));
    let cancelled = async {
        match cancelled {
            Some(receiver) => {
                let _ = receiver.await;
            }
            None => std::future::pending::<()>().await,
        }
    };
    let status = tokio::select! {
        status = child.wait() => status.ok(),
        _ = tokio::time::sleep(tool.timeout()) => {
            let _ = child.kill().await;
            return ToolResult::error(format!(
                "{} did not finish within {} seconds.",
                tool.name, tool.timeout_seconds
            ));
        }
        _ = cancelled => {
            let _ = child.kill().await;
            return ToolResult::error("The call was cancelled.");
        }
    };
    let (stdout, stdout_truncated) = collect(stdout).await;
    let (stderr, _) = collect(stderr).await;
    let succeeded = status.is_some_and(|status| status.success()) || is_wait_timeout(&stdout);
    let mut text = if succeeded {
        if stdout.trim().is_empty() {
            "Done.".to_owned()
        } else {
            without_fields(stdout.trim_end(), tool.omit_fields)
        }
    } else {
        let detail = [stderr.trim(), stdout.trim()]
            .into_iter()
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("\n");
        if detail.is_empty() {
            format!("{} failed.", tool.name)
        } else {
            detail
        }
    };
    let structured = if !succeeded {
        Some(error_object(&text))
    } else if stdout_truncated {
        None
    } else {
        serde_json::from_str::<Value>(&text)
            .ok()
            .filter(Value::is_object)
    };
    if stdout_truncated {
        text.push_str("\n[output truncated; narrow the request or read in smaller pages]");
    }
    ToolResult {
        text,
        is_error: !succeeded,
        structured,
    }
}

/// `inbox wait` exits with 2 when its wait ends with nothing new. For a polling
/// tool that is an ordinary answer, not a failure.
pub(super) fn is_wait_timeout(stdout: &str) -> bool {
    serde_json::from_str::<Value>(stdout.trim()).is_ok_and(|value| value["outcome"] == "timeout")
}

pub(super) fn without_fields(text: &str, fields: &[&str]) -> String {
    if fields.is_empty() {
        return text.to_owned();
    }
    match serde_json::from_str::<Value>(text) {
        Ok(Value::Object(mut object)) => {
            for field in fields {
                object.remove(*field);
            }
            serde_json::to_string_pretty(&Value::Object(object)).unwrap_or_else(|_| text.to_owned())
        }
        _ => text.to_owned(),
    }
}

async fn collect(task: Option<tokio::task::JoinHandle<(Vec<u8>, bool)>>) -> (String, bool) {
    match task {
        Some(task) => match task.await {
            Ok((bytes, truncated)) => (String::from_utf8_lossy(&bytes).into_owned(), truncated),
            Err(_) => (String::new(), false),
        },
        None => (String::new(), false),
    }
}

/// Keeps draining past the cap, so a chatty child never blocks on a full pipe.
async fn read_capped(mut pipe: impl AsyncRead + Unpin, cap: usize) -> (Vec<u8>, bool) {
    let mut kept = Vec::new();
    let mut truncated = false;
    let mut buffer = [0_u8; 16 * 1024];
    loop {
        match tokio::time::timeout(Duration::from_secs(600), pipe.read(&mut buffer)).await {
            Ok(Ok(0)) | Ok(Err(_)) | Err(_) => break,
            Ok(Ok(read)) => {
                let room = cap.saturating_sub(kept.len());
                if read > room {
                    truncated = true;
                }
                kept.extend_from_slice(&buffer[..read.min(room)]);
            }
        }
    }
    (kept, truncated)
}
