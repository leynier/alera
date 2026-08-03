//! The single line-oriented Codex app-server shared by all Codex tabs.
//!
//! The runtime host owns this process so a Flutter client can disappear, a
//! phone can reconnect, or a second client can observe the same thread without
//! creating another Codex process.

use std::collections::HashMap;
use std::process::Stdio;
use std::sync::{
    atomic::{AtomicI64, Ordering},
    Arc,
};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin};
use tokio::sync::{mpsc::UnboundedSender, oneshot, Mutex};

use crate::login_shell_environment::apply_login_shell_path;
use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerCommand;

const CODEX_REQUEST_TIMEOUT: Duration = Duration::from_secs(90);

type PendingRequests = Arc<Mutex<HashMap<i64, oneshot::Sender<HostResult<Value>>>>>;

#[derive(Clone)]
pub(super) struct CodexAppServer {
    stdin: Arc<Mutex<ChildStdin>>,
    pending: PendingRequests,
    _child: Arc<Mutex<Child>>,
    next_id: Arc<AtomicI64>,
}

impl CodexAppServer {
    pub(super) async fn start(
        inbox: UnboundedSender<ServerCommand>,
        cwd: Option<&str>,
    ) -> HostResult<Self> {
        let mut command = windowless_async_command("codex");
        command
            .arg("app-server")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        if let Some(cwd) = cwd.filter(|value| !value.trim().is_empty()) {
            command.current_dir(cwd);
        }
        apply_login_shell_path(&mut command).await;
        let mut child = command.spawn().map_err(|error| {
            HostError::state(format!(
                "Codex app-server could not start. Check that the `codex` executable is installed and authenticated: {error}"
            ))
        })?;
        let stdin = child.stdin.take().ok_or_else(|| {
            HostError::state("Codex app-server did not expose a writable input stream.")
        })?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| HostError::state("Codex app-server did not expose an output stream."))?;
        let server = Self {
            stdin: Arc::new(Mutex::new(stdin)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            _child: Arc::new(Mutex::new(child)),
            next_id: Arc::new(AtomicI64::new(1)),
        };
        tokio::spawn(read_codex_messages(
            BufReader::new(stdout).lines(),
            server.pending.clone(),
            inbox,
        ));
        server
            .request(
                "initialize",
                json!({
                    "clientInfo": {
                        "name": "alera",
                        "title": "Alera",
                        "version": env!("CARGO_PKG_VERSION")
                    },
                    "capabilities": {"experimentalApi": true}
                }),
            )
            .await?;
        server.notify("initialized", json!({})).await?;
        Ok(server)
    }

    pub(super) async fn request(&self, method: &str, params: Value) -> HostResult<Value> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().await.insert(id, sender);
        let message = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        if let Err(error) = self.write_message(message).await {
            self.pending.lock().await.remove(&id);
            return Err(error);
        }
        match tokio::time::timeout(CODEX_REQUEST_TIMEOUT, receiver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(HostError::state(
                "Codex app-server disconnected while processing the request.",
            )),
            Err(_) => {
                self.pending.lock().await.remove(&id);
                Err(HostError::state(format!(
                    "Codex app-server request timed out: {method}"
                )))
            }
        }
    }

    pub(super) async fn notify(&self, method: &str, params: Value) -> HostResult<()> {
        self.write_message(json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        }))
        .await
    }

    pub(super) async fn respond(
        &self,
        id: Value,
        result: Option<Value>,
        error: Option<Value>,
    ) -> HostResult<()> {
        let mut message = json!({"jsonrpc": "2.0", "id": id});
        if let Some(result) = result {
            message["result"] = result;
        }
        if let Some(error) = error {
            message["error"] = error;
        }
        self.write_message(message).await
    }

    pub(super) fn interrupt_in_background(&self, thread_id: String, turn_id: String) {
        let server = self.clone();
        tokio::spawn(async move {
            let _ = server
                .request(
                    "turn/interrupt",
                    json!({"threadId": thread_id, "turnId": turn_id}),
                )
                .await;
        });
    }

    async fn write_message(&self, message: Value) -> HostResult<()> {
        let mut stdin = self.stdin.lock().await;
        let line = serde_json::to_vec(&message)
            .map_err(|error| HostError::state(format!("Codex request encoding failed: {error}")))?;
        stdin
            .write_all(&line)
            .await
            .map_err(|error| HostError::state(format!("Codex app-server input failed: {error}")))?;
        stdin
            .write_all(b"\n")
            .await
            .map_err(|error| HostError::state(format!("Codex app-server input failed: {error}")))?;
        stdin
            .flush()
            .await
            .map_err(|error| HostError::state(format!("Codex app-server input failed: {error}")))
    }
}

async fn read_codex_messages(
    mut lines: tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    pending: PendingRequests,
    inbox: UnboundedSender<ServerCommand>,
) {
    let reason = loop {
        match lines.next_line().await {
            Ok(Some(line)) => {
                let message = match serde_json::from_str::<Value>(&line) {
                    Ok(message) => message,
                    Err(error) => {
                        let _ = inbox.send(ServerCommand::CodexMalformed {
                            reason: format!("Codex app-server returned malformed JSON: {error}"),
                        });
                        continue;
                    }
                };
                if let Some(id) = message.get("id").and_then(Value::as_i64) {
                    if let Some(sender) = pending.lock().await.remove(&id) {
                        let result = if let Some(error) = message.get("error") {
                            Err(HostError::state(codex_error_message(error)))
                        } else {
                            Ok(message.get("result").cloned().unwrap_or(Value::Null))
                        };
                        let _ = sender.send(result);
                        continue;
                    }
                }
                if message.get("method").and_then(Value::as_str).is_some() {
                    let _ = inbox.send(ServerCommand::CodexMessage { message });
                }
            }
            Ok(None) => break "Codex app-server closed its output stream.".to_string(),
            Err(error) => break format!("Codex app-server output failed: {error}"),
        }
    };
    let mut pending = pending.lock().await;
    for (_, sender) in pending.drain() {
        let _ = sender.send(Err(HostError::state(reason.clone())));
    }
    drop(pending);
    let _ = inbox.send(ServerCommand::CodexProcessExited { reason });
}

fn codex_error_message(error: &Value) -> String {
    error
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| "Codex app-server returned an error.".to_string())
}

#[cfg(test)]
mod tests {
    use super::codex_error_message;
    use serde_json::json;

    #[test]
    fn error_message_is_safe_when_server_omits_message() {
        assert_eq!(
            codex_error_message(&json!({"code": -1})),
            "Codex app-server returned an error."
        );
    }
}
