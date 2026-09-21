//! Hub side of a host link: one persistent `ssh` process per remote host that
//! runs `alera runtime-attach --stdio` on the satellite and multiplexes
//! newline-delimited protocol frames over its stdio.
//!
//! The link never learns the satellite's token: `runtime-attach` performs the
//! `hello` locally on the remote machine and only then starts piping frames.
//! Requests are correlated by id, events are forwarded to the server actor as
//! [`ServerCommand::HostLinkEvent`], and a closed pipe fails every pending
//! request so nothing waits on a dead host.

use std::collections::HashMap;
use std::process::Stdio;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::SshTarget;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, watch};

use super::host_error::{HostError, HostResult};
use super::server::ServerCommand;

/// How long the hub waits for `hostLink.attached` after spawning `ssh`.
pub(crate) const ATTACH_TIMEOUT: Duration = Duration::from_secs(45);
/// Default deadline for one forwarded request. Long operations (clone,
/// fetch) pass their own.
pub(crate) const DEFAULT_REQUEST_TIMEOUT: Duration = Duration::from_secs(120);
const STDERR_TAIL_BYTES: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct HostLinkAttachment {
    pub runtime_dir: String,
    pub platform: String,
    pub arch: String,
    #[serde(default)]
    pub host_version: Option<String>,
    #[serde(default)]
    pub runtime_capabilities: Vec<String>,
}

/// Snapshot of one host's link, as published by `hostLink.status`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "state")]
pub enum HostLinkState {
    Disconnected,
    Connecting,
    Attached { attachment: HostLinkAttachment },
    Failed { error: String },
}

type PendingRequests = Arc<Mutex<HashMap<i64, oneshot::Sender<HostResult<Value>>>>>;

/// Builds the process whose stdio carries the link frames.
pub(crate) type HostLinkLauncher =
    dyn Fn(&SshTarget) -> HostResult<tokio::process::Command> + Send + Sync;

/// The production launcher: `ssh` with the attach arguments.
pub(crate) fn ssh_launcher(target: &SshTarget) -> HostResult<tokio::process::Command> {
    let args = attach_ssh_arguments(target)?;
    let mut command = windowless_async_command("ssh");
    command.args(&args);
    Ok(command)
}

/// Latched close signal shared by the writer, the reader and the link handle.
#[derive(Clone)]
struct CloseSignal {
    sender: watch::Sender<bool>,
}

impl CloseSignal {
    fn new() -> Self {
        Self {
            sender: watch::channel(false).0,
        }
    }

    fn cancel(&self) {
        let _ = self.sender.send(true);
    }

    fn is_cancelled(&self) -> bool {
        *self.sender.borrow()
    }

    async fn cancelled(&self) {
        let mut receiver = self.sender.subscribe();
        while !*receiver.borrow_and_update() {
            if receiver.changed().await.is_err() {
                return;
            }
        }
    }
}

impl std::fmt::Debug for HostLink {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HostLink")
            .field("host_id", &self.host_id)
            .field("platform", &self.attachment.platform)
            .field("closed", &self.is_closed())
            .finish()
    }
}

pub(crate) struct HostLink {
    host_id: String,
    attachment: HostLinkAttachment,
    outbound: mpsc::UnboundedSender<String>,
    pending: PendingRequests,
    next_id: AtomicI64,
    closed: CloseSignal,
    child: Mutex<Option<tokio::process::Child>>,
}

impl HostLink {
    pub(crate) fn attachment(&self) -> &HostLinkAttachment {
        &self.attachment
    }

    pub(crate) fn is_closed(&self) -> bool {
        self.closed.is_cancelled()
    }

    pub(crate) async fn request_with_timeout(
        &self,
        request_type: &str,
        payload: Value,
        deadline: Duration,
    ) -> HostResult<Value> {
        if self.is_closed() {
            return Err(link_closed(&self.host_id));
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = oneshot::channel();
        self.pending
            .lock()
            .expect("host link pending map poisoned")
            .insert(id, sender);
        let line = serde_json::to_string(&json!({
            "id": id,
            "type": request_type,
            "payload": payload,
        }))
        .map_err(|error| HostError::format(error.to_string()))?;
        if self.outbound.send(line).is_err() {
            self.pending
                .lock()
                .expect("host link pending map poisoned")
                .remove(&id);
            return Err(link_closed(&self.host_id));
        }
        match tokio::time::timeout(deadline, receiver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(link_closed(&self.host_id)),
            Err(_) => {
                self.pending
                    .lock()
                    .expect("host link pending map poisoned")
                    .remove(&id);
                Err(HostError::state(format!(
                    "The host {} did not answer {request_type} within {}s.",
                    self.host_id,
                    deadline.as_secs()
                )))
            }
        }
    }

    /// Ends the ssh process. Pending requests fail through the reader task.
    pub(crate) async fn close(&self) {
        self.closed.cancel();
        let child = self.child.lock().expect("host link child poisoned").take();
        if let Some(mut child) = child {
            let _ = child.start_kill();
            let _ = child.wait().await;
        }
    }

    /// Spawns the launcher's process (`ssh <target> alera runtime-attach
    /// --stdio` in production, a local stand-in for the satellite in tests) and
    /// waits for the attachment announcement.
    pub(crate) async fn connect_with(
        target: &SshTarget,
        inbox: mpsc::UnboundedSender<ServerCommand>,
        launcher: &HostLinkLauncher,
    ) -> HostResult<Arc<HostLink>> {
        let host_id = target.id.clone();
        let mut command = launcher(target)?;
        // The hub sidecar starts detached from a GUI launch with none of the
        // user's shell exports, so `ssh` and its agent socket come from here.
        crate::login_shell_environment::apply_login_shell_environment(
            &mut command,
            &std::collections::BTreeMap::new(),
        )
        .await;
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|error| HostError::state(format!("Failed to start the host link: {error}")))?;
        let stdin = child.stdin.take().expect("piped stdin");
        let stdout = child.stdout.take().expect("piped stdout");
        let stderr = child.stderr.take().expect("piped stderr");
        let stderr_tail = Arc::new(Mutex::new(String::new()));
        tokio::spawn(collect_stderr(stderr, stderr_tail.clone()));

        let mut lines = BufReader::new(stdout).lines();
        let first = match tokio::time::timeout(ATTACH_TIMEOUT, lines.next_line()).await {
            Ok(Ok(Some(line))) => line,
            Ok(Ok(None)) => {
                let _ = child.start_kill();
                return Err(attach_failure(
                    &host_id,
                    "ssh closed before attaching",
                    &stderr_tail,
                ));
            }
            Ok(Err(error)) => {
                let _ = child.start_kill();
                return Err(attach_failure(&host_id, &error.to_string(), &stderr_tail));
            }
            Err(_) => {
                let _ = child.start_kill();
                return Err(attach_failure(
                    &host_id,
                    &format!("no attachment within {}s", ATTACH_TIMEOUT.as_secs()),
                    &stderr_tail,
                ));
            }
        };
        let attachment = match parse_attached(&first) {
            Some(attachment) => attachment,
            None => {
                let _ = child.start_kill();
                return Err(attach_failure(
                    &host_id,
                    &format!("unexpected first frame: {}", truncate(&first, 200)),
                    &stderr_tail,
                ));
            }
        };

        let pending: PendingRequests = Arc::new(Mutex::new(HashMap::new()));
        let closed = CloseSignal::new();
        let (outbound, outbound_rx) = mpsc::unbounded_channel::<String>();
        tokio::spawn(write_outbound(stdin, outbound_rx, closed.clone()));
        tokio::spawn(read_inbound(
            host_id.clone(),
            lines,
            pending.clone(),
            inbox,
            closed.clone(),
            stderr_tail,
        ));
        Ok(Arc::new(HostLink {
            host_id,
            attachment,
            outbound,
            pending,
            next_id: AtomicI64::new(1),
            closed,
            child: Mutex::new(Some(child)),
        }))
    }
}

fn link_closed(host_id: &str) -> HostError {
    HostError::state(format!("The link to host {host_id} is closed."))
}

fn attach_failure(host_id: &str, reason: &str, stderr_tail: &Mutex<String>) -> HostError {
    let tail = stderr_tail
        .lock()
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    if tail.is_empty() {
        HostError::state(format!("Could not attach to host {host_id}: {reason}."))
    } else {
        HostError::state(format!(
            "Could not attach to host {host_id}: {reason}. {tail}"
        ))
    }
}

fn truncate(value: &str, max: usize) -> String {
    value.chars().take(max).collect()
}

pub(crate) fn parse_attached(line: &str) -> Option<HostLinkAttachment> {
    let value: Value = serde_json::from_str(line).ok()?;
    if value.get("event")?.as_str()? != crate::runtime_attach::ATTACHED_EVENT {
        return None;
    }
    serde_json::from_value(value.get("payload")?.clone()).ok()
}

async fn collect_stderr(stderr: tokio::process::ChildStderr, tail: Arc<Mutex<String>>) {
    let mut lines = BufReader::new(stderr).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        tracing::warn!(target: "host_link", "ssh: {line}");
        if let Ok(mut tail) = tail.lock() {
            tail.push_str(&line);
            tail.push('\n');
            if tail.len() > STDERR_TAIL_BYTES {
                let cut = tail.len() - STDERR_TAIL_BYTES;
                let boundary = tail
                    .char_indices()
                    .map(|(index, _)| index)
                    .find(|index| *index >= cut)
                    .unwrap_or(0);
                tail.drain(..boundary);
            }
        }
    }
}

async fn write_outbound(
    mut stdin: tokio::process::ChildStdin,
    mut outbound: mpsc::UnboundedReceiver<String>,
    closed: CloseSignal,
) {
    loop {
        let line = tokio::select! {
            _ = closed.cancelled() => break,
            line = outbound.recv() => match line {
                Some(line) => line,
                None => break,
            },
        };
        if stdin.write_all(line.as_bytes()).await.is_err()
            || stdin.write_all(b"\n").await.is_err()
            || stdin.flush().await.is_err()
        {
            closed.cancel();
            break;
        }
    }
}

async fn read_inbound(
    host_id: String,
    mut lines: tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    pending: PendingRequests,
    inbox: mpsc::UnboundedSender<ServerCommand>,
    closed: CloseSignal,
    stderr_tail: Arc<Mutex<String>>,
) {
    loop {
        let line = tokio::select! {
            _ = closed.cancelled() => None,
            line = lines.next_line() => line.ok().flatten(),
        };
        let Some(line) = line else { break };
        let Ok(frame) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if let Some(id) = frame.get("id").and_then(Value::as_i64) {
            let sender = pending
                .lock()
                .expect("host link pending map poisoned")
                .remove(&id);
            if let Some(sender) = sender {
                let _ = sender.send(response_result(&frame));
            }
            continue;
        }
        if frame.get("event").is_some() {
            let _ = inbox.send(ServerCommand::HostLinkEvent {
                host_id: host_id.clone(),
                event: frame,
            });
        }
    }
    closed.cancel();
    let error = {
        let tail = stderr_tail
            .lock()
            .map(|s| s.trim().to_string())
            .unwrap_or_default();
        if tail.is_empty() {
            format!("The link to host {host_id} was closed.")
        } else {
            format!("The link to host {host_id} was closed. {tail}")
        }
    };
    let drained: Vec<_> = pending
        .lock()
        .expect("host link pending map poisoned")
        .drain()
        .collect();
    for (_, sender) in drained {
        let _ = sender.send(Err(HostError::state(error.clone())));
    }
    let _ = inbox.send(ServerCommand::HostLinkClosed { host_id, error });
}

/// Maps a satellite response onto the same [`HostError`] shapes the hub
/// produces itself, so a forwarded error reaches the client unchanged.
pub(crate) fn response_result(frame: &Value) -> HostResult<Value> {
    if frame.get("ok").and_then(Value::as_bool) == Some(true) {
        return Ok(frame.get("payload").cloned().unwrap_or(Value::Null));
    }
    let message = frame
        .get("error")
        .and_then(Value::as_str)
        .unwrap_or("The remote runtime request failed.")
        .to_string();
    if let Some(code) = frame.get("errorCode").and_then(Value::as_str) {
        return Err(HostError::conflict(
            code,
            message,
            frame.get("errorDetails").cloned().unwrap_or(Value::Null),
        ));
    }
    if let Some(rest) = message.strip_prefix("FormatException: ") {
        return Err(HostError::format(rest.to_string()));
    }
    Err(HostError::state(message))
}

/// The `ssh` argument vector for the link. No PTY (`-T`), keep-alives so a
/// dropped network fails the link instead of hanging it, and the remote
/// command shaped for the satellite's shell.
pub(crate) fn attach_ssh_arguments(target: &SshTarget) -> HostResult<Vec<String>> {
    let install_dir = target
        .install_dir
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::state(crate::ssh_remote::host_not_bootstrapped(target)))?;
    let windows = crate::ssh_remote::terminal_platform_windows(target)
        .map_err(|error| HostError::state(error.to_string()))?;
    let mut args = crate::ssh_bootstrap::ssh_args(target);
    let destination = args.pop().expect("ssh_args includes the destination");
    args.push("-T".to_string());
    args.push("-o".to_string());
    args.push("ServerAliveInterval=15".to_string());
    args.push("-o".to_string());
    args.push("ServerAliveCountMax=3".to_string());
    args.push(destination);
    args.push(attach_remote_command(install_dir, windows));
    Ok(args)
}

/// The command the satellite's sshd runs. Both shapes go through the sidecar's
/// `bin/alera` wrapper, which exports `ALERA_RUNTIME_DIR` to the sidecar data
/// directory, so the attach reaches the same runtime the bootstrap validated.
///
/// Windows deliberately avoids PowerShell: when its own stdin is redirected,
/// PowerShell hands a native command a fresh pipe it never feeds unless the
/// command is on the right side of `|`, so the frames the hub writes would
/// never reach `alera.exe`. `cmd.exe` (the sshd default shell) passes the
/// handles straight through and expands `%LOCALAPPDATA%` in the install dir.
pub(crate) fn attach_remote_command(install_dir: &str, windows: bool) -> String {
    if windows {
        let wrapper = format!(
            "{}\\bin\\alera.cmd",
            install_dir.replace('/', "\\").trim_end_matches('\\')
        );
        // sshd runs this as `cmd.exe /c "<line>"`; with more than two quotes
        // cmd strips only the outer pair, which leaves the wrapper path quoted.
        return format!("\"{wrapper}\" runtime-attach --stdio");
    }
    format!(
        "sh -lc {}",
        crate::ssh_bootstrap::shell_quote(&format!(
            "install={}; case \"$install\" in '~/'*) install=\"$HOME/${{install#\"~/\"}}\";; esac; exec \"$install/bin/alera\" runtime-attach --stdio",
            crate::ssh_bootstrap::shell_quote(install_dir)
        ))
    )
}

#[cfg(test)]
#[path = "host_link_tests.rs"]
mod tests;
