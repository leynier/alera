use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use alera_core::login_shell_environment::apply_login_shell_environment;
use async_trait::async_trait;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::{Child, ChildStderr, ChildStdin};
use tokio::sync::mpsc::{self, Receiver};
use tokio::task::JoinHandle;

use crate::framing::{DEFAULT_MAX_FRAME_BYTES, DEFAULT_SHUTDOWN_TIMEOUT, STDERR_TAIL_BYTES};
#[cfg(unix)]
use crate::process_group::ProcessGroup;
use crate::{JsonTransport, TransportError};

mod read;
mod write;
use read::drain_stdout;
use write::{FrameWriteError, PendingFrame};

const READ_CHUNK_BYTES: usize = 8 * 1024;
const STDOUT_QUEUE_CAPACITY: usize = 32;
type FrameResult = Result<Option<serde_json::Value>, TransportError>;

/// Configuration for a JSON-lines provider child process.
#[derive(Clone, Debug)]
pub struct ProcessConfig {
    /// Executable to launch.
    pub executable: PathBuf,
    /// Arguments passed without shell interpretation.
    pub args: Vec<OsString>,
    /// Optional working directory for the provider process.
    pub cwd: Option<PathBuf>,
    /// Environment overrides added to the inherited environment.
    pub env: BTreeMap<OsString, OsString>,
    /// Maximum encoded JSON frame size, excluding its trailing newline.
    pub max_frame_bytes: usize,
    /// Deadline for writes and output backpressure, and the grace period a
    /// still-running child gets on close before each harder stop: SIGTERM to
    /// its process group on Unix, then SIGKILL.
    pub shutdown_timeout: Duration,
}

impl Default for ProcessConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::new(),
            args: Vec::new(),
            cwd: None,
            env: BTreeMap::new(),
            max_frame_bytes: DEFAULT_MAX_FRAME_BYTES,
            shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
        }
    }
}

#[derive(Debug, Default)]
struct StderrTail {
    bytes: Vec<u8>,
}

impl StderrTail {
    fn append(&mut self, bytes: &[u8]) {
        if bytes.len() >= STDERR_TAIL_BYTES {
            self.bytes.clear();
            self.bytes
                .extend_from_slice(&bytes[bytes.len() - STDERR_TAIL_BYTES..]);
            return;
        }

        let total = self.bytes.len() + bytes.len();
        if total > STDERR_TAIL_BYTES {
            self.bytes
                .drain(..(total - STDERR_TAIL_BYTES).min(self.bytes.len()));
        }
        self.bytes.extend_from_slice(bytes);
    }

    fn text(&self) -> String {
        String::from_utf8_lossy(&self.bytes).into_owned()
    }
}

async fn drain_stderr(mut stderr: ChildStderr, tail: Arc<Mutex<StderrTail>>) {
    let mut buffer = [0_u8; READ_CHUNK_BYTES];
    loop {
        match stderr.read(&mut buffer).await {
            Ok(0) | Err(_) => break,
            Ok(read) => {
                if let Ok(mut tail) = tail.lock() {
                    tail.append(&buffer[..read]);
                }
            }
        }
    }
}

/// A bounded NDJSON transport backed by a child process.
///
/// Cancelled sends retain their frame and original deadline. Sending that same
/// encoded frame resumes it once; a different frame follows it in FIFO order.
///
/// On Unix the child runs in its own process group, which is stopped as a
/// whole on close, on drop, and when this process dies.
pub struct JsonLineProcess {
    child: Option<Child>,
    #[cfg(unix)]
    group: Option<ProcessGroup>,
    stdin: Option<ChildStdin>,
    pending_frame: Option<PendingFrame>,
    pending_error: Option<TransportError>,
    messages: Receiver<FrameResult>,
    stdout_task: Option<JoinHandle<()>>,
    stderr_task: Option<JoinHandle<()>>,
    stderr_tail: Arc<Mutex<StderrTail>>,
    closed: bool,
    exit_success: Option<bool>,
    exit_code: Option<i32>,
    max_frame_bytes: usize,
    shutdown_timeout: Duration,
}

impl std::fmt::Debug for JsonLineProcess {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("JsonLineProcess")
            .field("closed", &self.closed)
            .field("max_frame_bytes", &self.max_frame_bytes)
            .field("shutdown_timeout", &self.shutdown_timeout)
            .finish_non_exhaustive()
    }
}

impl JsonLineProcess {
    /// Spawn a provider process with piped stdin, stdout, and stderr.
    pub async fn spawn(config: ProcessConfig) -> Result<Self, TransportError> {
        if config.executable.as_os_str().is_empty() {
            return Err(TransportError::InvalidConfig {
                reason: "executable must not be empty",
            });
        }
        if config.max_frame_bytes == 0 {
            return Err(TransportError::InvalidConfig {
                reason: "max_frame_bytes must be greater than zero",
            });
        }

        let executable = config.executable.clone();
        let mut command = windowless_async_command(&config.executable);
        apply_login_shell_environment(&mut command, &BTreeMap::new()).await;
        command
            .args(&config.args)
            .envs(&config.env)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(cwd) = &config.cwd {
            command.current_dir(cwd);
        }
        // The group replaces kill_on_drop on Unix, which would skip SIGTERM
        // and reach only the direct child.
        #[cfg(unix)]
        let mut group = ProcessGroup::start(config.shutdown_timeout)
            .map_err(|source| TransportError::io("start process group", source))?;
        #[cfg(unix)]
        group.join(&mut command);
        #[cfg(not(unix))]
        command.kill_on_drop(true);

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(source) => {
                #[cfg(unix)]
                group.kill();
                return Err(TransportError::Spawn { executable, source });
            }
        };
        let stdin = child.stdin.take().ok_or_else(|| {
            TransportError::io("spawn", std::io::Error::other("child stdin was not piped"))
        })?;
        let stdout = child.stdout.take().ok_or_else(|| {
            TransportError::io("spawn", std::io::Error::other("child stdout was not piped"))
        })?;
        let stderr = child.stderr.take().ok_or_else(|| {
            TransportError::io("spawn", std::io::Error::other("child stderr was not piped"))
        })?;

        let stderr_tail = Arc::new(Mutex::new(StderrTail::default()));
        let stderr_task = tokio::spawn(drain_stderr(stderr, Arc::clone(&stderr_tail)));
        let (message_tx, messages) = mpsc::channel(STDOUT_QUEUE_CAPACITY + 1);
        let stdout_task = tokio::spawn(drain_stdout(
            stdout,
            message_tx,
            config.max_frame_bytes,
            config.shutdown_timeout,
        ));

        Ok(Self {
            child: Some(child),
            #[cfg(unix)]
            group: Some(group),
            stdin: Some(stdin),
            pending_frame: None,
            pending_error: None,
            messages,
            stdout_task: Some(stdout_task),
            stderr_task: Some(stderr_task),
            stderr_tail,
            closed: false,
            exit_success: None,
            exit_code: None,
            max_frame_bytes: config.max_frame_bytes,
            shutdown_timeout: config.shutdown_timeout,
        })
    }

    fn ensure_open(&self) -> Result<(), TransportError> {
        if self.closed {
            Err(TransportError::Closed)
        } else {
            Ok(())
        }
    }

    fn stderr_text(&self) -> String {
        self.stderr_tail
            .lock()
            .map_or_else(|_| String::new(), |tail| tail.text())
    }

    fn record_status(&mut self, status: std::process::ExitStatus) {
        self.exit_success = Some(status.success());
        self.exit_code = status.code();
    }

    fn process_exit_error(&self) -> TransportError {
        TransportError::ProcessExited {
            code: self.exit_code,
            stderr: self.stderr_text(),
        }
    }

    /// Kill the child at once and, on Unix, everything left in its group.
    fn kill_child(&mut self) {
        #[cfg(unix)]
        if let Some(group) = self.group.as_mut() {
            group.kill();
        }
        if let Some(child) = self.child.as_mut() {
            let _ = child.start_kill();
        }
    }

    /// Stop a child that outlived its closed stdin. On Unix its whole group
    /// gets SIGTERM and, after the shutdown timeout, SIGKILL; elsewhere the
    /// child is killed at once.
    async fn stop_child(&mut self) -> Option<std::process::ExitStatus> {
        #[cfg(unix)]
        if let Some(group) = self.group.as_mut() {
            group.terminate();
            let wait = self.child.as_mut()?.wait();
            if let Ok(Ok(status)) = tokio::time::timeout(self.shutdown_timeout, wait).await {
                return Some(status);
            }
        }
        self.kill_child();
        self.child.as_mut()?.wait().await.ok()
    }

    async fn close_child(&mut self) -> Result<(), TransportError> {
        let mut first_error = None;
        if let Some(stdin) = self.stdin.as_mut() {
            if let Err(source) = stdin.shutdown().await {
                if source.kind() != std::io::ErrorKind::BrokenPipe {
                    first_error = Some(TransportError::io("close stdin", source));
                }
            }
        }
        self.stdin.take();

        if let Some(child) = self.child.as_mut() {
            let wait = child.wait();
            let status = match tokio::time::timeout(self.shutdown_timeout, wait).await {
                Ok(Ok(status)) => Some(status),
                Ok(Err(source)) => {
                    first_error.get_or_insert_with(|| TransportError::io("wait child", source));
                    self.kill_child();
                    match self.child.as_mut() {
                        Some(child) => child.wait().await.ok(),
                        None => None,
                    }
                }
                Err(_) => {
                    first_error.get_or_insert(TransportError::ShutdownTimeout {
                        timeout: self.shutdown_timeout,
                    });
                    self.stop_child().await
                }
            };
            if let Some(status) = status {
                self.record_status(status);
            }
        }
        self.child.take();
        // Whatever the child left running, such as an MCP server's own child,
        // gets SIGTERM and then SIGKILL. That also ends the stderr pipes such
        // descendants inherited, so the drain below can finish.
        #[cfg(unix)]
        self.group.take();

        self.messages.close();
        if let Some(task) = self.stdout_task.take() {
            task.abort();
        }

        if let Some(task) = self.stderr_task.as_mut() {
            if tokio::time::timeout(self.shutdown_timeout, &mut *task)
                .await
                .is_err()
            {
                // The child is already gone or killed. Aborting only prevents
                // a malformed provider from keeping this transport alive.
                task.abort();
                first_error.get_or_insert(TransportError::ShutdownTimeout {
                    timeout: self.shutdown_timeout,
                });
            }
        }
        self.stderr_task.take();
        first_error.map_or(Ok(()), Err)
    }

    async fn fail<T>(&mut self, error: TransportError) -> Result<T, TransportError> {
        // A cancelled cleanup must never expose the damaged pipe as open.
        self.closed = true;
        self.pending_frame.take();
        self.stdin.take();
        self.kill_child();
        // Keep the original failure owned by the transport until it is
        // returned, because a command can cancel receive during cleanup.
        self.pending_error = Some(error);
        let _ = self.close_child().await;
        Err(self.pending_error.take().expect("failure is retained"))
    }

    async fn finish_pending_frame(&mut self) -> Result<(), TransportError> {
        let Some(frame) = self.pending_frame.as_mut() else {
            return Ok(());
        };
        let stdin = self.stdin.as_mut().ok_or(TransportError::Closed)?;
        match frame.complete(stdin).await {
            Ok(()) => {
                self.pending_frame.take();
                Ok(())
            }
            Err(FrameWriteError::Io(source)) => {
                let status = self
                    .child
                    .as_mut()
                    .and_then(|child| child.try_wait().ok().flatten());
                let error = if let Some(status) = status {
                    self.record_status(status);
                    self.process_exit_error()
                } else if source.kind() == std::io::ErrorKind::BrokenPipe {
                    self.process_exit_error()
                } else {
                    TransportError::io("write stdin", source)
                };
                self.fail(error).await
            }
            Err(FrameWriteError::Timeout) => {
                self.fail(TransportError::IoTimeout {
                    operation: "write stdin",
                    timeout: self.shutdown_timeout,
                })
                .await
            }
        }
    }
}

#[async_trait]
impl JsonTransport for JsonLineProcess {
    async fn send(&mut self, message: serde_json::Value) -> Result<(), TransportError> {
        self.ensure_open()?;
        let mut frame = match serde_json::to_vec(&message) {
            Ok(frame) => frame,
            Err(source) => return self.fail(TransportError::Serialize { source }).await,
        };
        if frame.len() > self.max_frame_bytes {
            return self
                .fail(TransportError::FrameTooLarge {
                    limit: self.max_frame_bytes,
                    observed: frame.len(),
                })
                .await;
        }
        frame.push(b'\n');
        let retry = self
            .pending_frame
            .as_ref()
            .is_some_and(|pending| pending.matches(&frame));
        self.finish_pending_frame().await?;
        if !retry {
            self.pending_frame = Some(PendingFrame::new(frame, self.shutdown_timeout));
            self.finish_pending_frame().await?;
        }
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<serde_json::Value>, TransportError> {
        if self.pending_error.is_some() {
            let _ = self.close_child().await;
            return Err(self.pending_error.take().expect("failure is retained"));
        }
        self.ensure_open()?;
        match self.messages.recv().await {
            Some(Ok(Some(value))) => Ok(Some(value)),
            Some(Ok(None)) | None => {
                if let Some(status) = self
                    .child
                    .as_mut()
                    .and_then(|child| child.try_wait().ok().flatten())
                {
                    self.record_status(status);
                }
                self.close().await?;
                if self.exit_success == Some(true) {
                    Ok(None)
                } else {
                    Err(self.process_exit_error())
                }
            }
            Some(Err(error)) => self.fail(error).await,
        }
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed = true;
        self.finish_pending_frame().await?;
        self.close_child().await
    }
}

impl Drop for JsonLineProcess {
    fn drop(&mut self) {
        if let Some(task) = self.stdout_task.take() {
            task.abort();
        }
        if let Some(task) = self.stderr_task.take() {
            task.abort();
        }
        drop(self.stdin.take());
        // Dropping the group sends SIGTERM to the child and everything it
        // started, then SIGKILL, with or without a runtime. Tokio reaps the
        // dropped child.
        #[cfg(unix)]
        self.group.take();
        #[cfg(not(unix))]
        if let Some(mut child) = self.child.take() {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = child.kill().await;
                    let _ = child.wait().await;
                });
            }
            // Child::kill_on_drop(true) remains the fallback when Drop runs
            // outside a Tokio runtime.
        }
    }
}

#[cfg(test)]
#[path = "process/receive_tests.rs"]
mod receive_tests;
