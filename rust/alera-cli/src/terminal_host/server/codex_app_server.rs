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
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin};
use tokio::sync::{mpsc::UnboundedSender, oneshot, Mutex};

use crate::login_shell_environment::apply_login_shell_path;
use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerCommand;

const CODEX_REQUEST_TIMEOUT: Duration = Duration::from_secs(90);
const CODEX_OVERLOAD_RETRIES: usize = 3;

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
            .stderr(Stdio::piped())
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
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| HostError::state("Codex app-server did not expose an error stream."))?;
        let server = Self {
            stdin: Arc::new(Mutex::new(stdin)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            _child: Arc::new(Mutex::new(child)),
            next_id: Arc::new(AtomicI64::new(1)),
        };
        tokio::spawn(read_codex_messages(
            BufReader::new(stdout),
            server.pending.clone(),
            inbox,
        ));
        tokio::spawn(read_codex_stderr(BufReader::new(stderr)));
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
        for attempt in 0..=CODEX_OVERLOAD_RETRIES {
            match self.request_once(method, params.clone()).await {
                Err(error) if attempt < CODEX_OVERLOAD_RETRIES && is_codex_overloaded(&error) => {
                    tokio::time::sleep(codex_overload_delay(attempt)).await;
                }
                result => return result,
            }
        }
        unreachable!("Codex overload retry loop always returns");
    }

    async fn request_once(&self, method: &str, params: Value) -> HostResult<Value> {
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

async fn read_codex_messages<R>(
    reader: R,
    pending: PendingRequests,
    inbox: UnboundedSender<ServerCommand>,
) where
    R: AsyncBufRead + Unpin,
{
    let mut lines = reader.lines();
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
                if message.get("method").and_then(Value::as_str).is_some() {
                    let _ = inbox.send(ServerCommand::CodexMessage { message });
                    continue;
                }
                if let Some(id) = message.get("id").and_then(Value::as_i64) {
                    if let Some(sender) = pending.lock().await.remove(&id) {
                        let result = if let Some(error) = message.get("error") {
                            Err(HostError::state(codex_error_message(error)))
                        } else {
                            Ok(message.get("result").cloned().unwrap_or(Value::Null))
                        };
                        let _ = sender.send(result);
                    }
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

async fn read_codex_stderr<R>(reader: R)
where
    R: AsyncBufRead + Unpin,
{
    let mut lines = reader.lines();
    loop {
        match lines.next_line().await {
            Ok(Some(line)) => tracing::debug!(target: "codex_app_server", "{line}"),
            Ok(None) => return,
            Err(error) => {
                tracing::warn!(target: "codex_app_server", "Codex app-server diagnostics failed: {error}");
                return;
            }
        }
    }
}

fn codex_error_message(error: &Value) -> String {
    let message = error
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| "Codex app-server returned an error.".to_string());
    match error.get("code").and_then(Value::as_i64) {
        Some(-32001) => format!("Codex app-server error -32001: {message}"),
        _ => message,
    }
}

fn is_codex_overloaded(error: &HostError) -> bool {
    error.wire_message().contains("error -32001")
}

fn codex_overload_delay(attempt: usize) -> Duration {
    Duration::from_millis(25_u64.saturating_mul(1_u64 << attempt.min(3)))
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{
        codex_error_message, codex_overload_delay, is_codex_overloaded, read_codex_messages,
        PendingRequests,
    };
    use crate::terminal_host::host_error::HostError;
    use serde_json::json;
    use tokio::io::{duplex, AsyncWriteExt, BufReader};
    use tokio::sync::{mpsc, oneshot, Mutex};

    use crate::terminal_host::server::ServerCommand;

    #[test]
    fn error_message_is_safe_when_server_omits_message() {
        assert_eq!(
            codex_error_message(&json!({"code": -1})),
            "Codex app-server returned an error."
        );
    }

    #[test]
    fn overload_errors_use_bounded_exponential_retry_delays() {
        let error = HostError::state(codex_error_message(
            &json!({"code": -32001, "message": "busy"}),
        ));
        assert!(is_codex_overloaded(&error));
        assert_eq!(
            codex_overload_delay(0),
            std::time::Duration::from_millis(25)
        );
        assert_eq!(
            codex_overload_delay(1),
            std::time::Duration::from_millis(50)
        );
        assert_eq!(
            codex_overload_delay(3),
            std::time::Duration::from_millis(200)
        );
        assert_eq!(
            codex_overload_delay(20),
            std::time::Duration::from_millis(200)
        );
    }

    #[tokio::test]
    async fn fake_jsonl_app_server_routes_responses_notifications_and_requests() {
        let (mut writer, reader) = duplex(4096);
        let pending: PendingRequests = Arc::new(Mutex::new(std::collections::HashMap::new()));
        let (response_tx, response_rx) = oneshot::channel();
        pending.lock().await.insert(7, response_tx);
        let (inbox, mut messages) = mpsc::unbounded_channel();
        let read_task = tokio::spawn(read_codex_messages(
            BufReader::new(reader),
            pending.clone(),
            inbox,
        ));
        writer
            .write_all(
                br#"{"jsonrpc":"2.0","id":7,"result":{"thread":{"id":"thread-1"}}}
{"jsonrpc":"2.0","method":"turn/started","params":{"turn":{"id":"turn-1","threadId":"thread-1"}}}
{"jsonrpc":"2.0","id":99,"method":"item/tool/request_user_input","params":{"threadId":"thread-1","questions":[{"id":"mode","question":"Choose","options":[{"label":"Fast"}]}]}}
"#,
            )
            .await
            .unwrap();
        drop(writer);
        assert_eq!(
            response_rx.await.unwrap().unwrap()["thread"]["id"],
            "thread-1"
        );
        let first = messages.recv().await.unwrap();
        let second = messages.recv().await.unwrap();
        match first {
            ServerCommand::CodexMessage { message } => {
                assert_eq!(message["method"], "turn/started");
            }
            _ => panic!("unexpected fake app-server command"),
        }
        match second {
            ServerCommand::CodexMessage { message } => {
                assert_eq!(message["id"], 99);
                assert_eq!(message["params"]["questions"][0]["id"], "mode");
            }
            _ => panic!("unexpected fake app-server command"),
        }
        read_task.await.unwrap();
    }

    #[tokio::test]
    async fn server_request_id_does_not_consume_a_pending_client_response() {
        let (mut writer, reader) = duplex(4096);
        let pending: PendingRequests = Arc::new(Mutex::new(std::collections::HashMap::new()));
        let (response_tx, _response_rx) = oneshot::channel();
        pending.lock().await.insert(7, response_tx);
        let (inbox, mut messages) = mpsc::unbounded_channel();
        let read_task = tokio::spawn(read_codex_messages(
            BufReader::new(reader),
            pending.clone(),
            inbox,
        ));
        writer
            .write_all(
                br#"{"jsonrpc":"2.0","id":7,"method":"mcpServer/elicitation/request","params":{}}
"#,
            )
            .await
            .unwrap();
        let message = messages.recv().await.unwrap();
        assert!(matches!(message, ServerCommand::CodexMessage { message } if message["id"] == 7));
        assert!(pending.lock().await.contains_key(&7));
        drop(writer);
        read_task.await.unwrap();
    }
}
