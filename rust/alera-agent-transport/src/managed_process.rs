//! A bounded line-oriented child process for HTTP and RPC provider servers.

use std::collections::{BTreeMap, VecDeque};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[cfg(not(unix))]
use alera_core::captured_process::ProcessTreeGuard;
use alera_core::child_process::windowless_async_command;
use alera_core::login_shell_environment::apply_login_shell_environment;
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::process::Child;
use tokio::sync::mpsc::{self, Receiver, Sender};
use tokio::sync::Notify;
use tokio::task::JoinHandle;

#[cfg(unix)]
use crate::process_group::ProcessGroup;
use crate::{ProcessConfig, TransportError};

const READ_CHUNK_BYTES: usize = 8 * 1024;
const LINE_QUEUE_CAPACITY: usize = 32;

#[derive(Debug, Default)]
struct LineQueueState {
    lines: VecDeque<String>,
    closed: bool,
}

#[derive(Debug, Default)]
struct LineQueue {
    state: Mutex<LineQueueState>,
    notify: Notify,
}

impl LineQueue {
    fn push(&self, line: String) {
        if let Ok(mut state) = self.state.lock() {
            if state.closed {
                return;
            }
            if state.lines.len() >= LINE_QUEUE_CAPACITY {
                state.lines.pop_front();
            }
            state.lines.push_back(line);
        }
        self.notify.notify_one();
    }

    fn close(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.closed = true;
        }
        self.notify.notify_waiters();
    }

    async fn next(&self) -> Option<String> {
        loop {
            let notified = self.notify.notified();
            if let Ok(mut state) = self.state.lock() {
                if let Some(line) = state.lines.pop_front() {
                    return Some(line);
                }
                if state.closed {
                    return None;
                }
            } else {
                return None;
            }
            notified.await;
        }
    }
}

fn send_end(sender: &Sender<Option<String>>) {
    let _ = sender.try_send(None);
}

async fn drain_lines<R>(mut stream: R, sender: Sender<Option<String>>, max_frame_bytes: usize)
where
    R: AsyncRead + Unpin,
{
    let mut buffered = Vec::new();
    loop {
        let mut chunk = [0_u8; READ_CHUNK_BYTES];
        let read = match stream.read(&mut chunk).await {
            Ok(read) => read,
            Err(_) => {
                send_end(&sender);
                return;
            }
        };
        if read == 0 {
            if buffered.is_empty() {
                send_end(&sender);
                return;
            }
            if buffered.len() > max_frame_bytes {
                send_end(&sender);
                return;
            }
            let line = match String::from_utf8(std::mem::take(&mut buffered)) {
                Ok(line) => line,
                Err(_) => {
                    send_end(&sender);
                    return;
                }
            };
            if sender.try_send(Some(line)).is_err() {
                return;
            }
            send_end(&sender);
            return;
        }

        buffered.extend_from_slice(&chunk[..read]);
        loop {
            let Some(newline) = buffered.iter().position(|byte| *byte == b'\n') else {
                if buffered.len() > max_frame_bytes {
                    send_end(&sender);
                    return;
                }
                break;
            };

            let mut line = buffered.drain(..=newline).collect::<Vec<_>>();
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            if line.len() > max_frame_bytes {
                send_end(&sender);
                return;
            }
            let line = match String::from_utf8(line) {
                Ok(line) => line,
                Err(_) => {
                    send_end(&sender);
                    return;
                }
            };
            if sender.try_send(Some(line)).is_err() {
                return;
            }
        }
    }
}

async fn drain_stderr(
    mut stream: impl AsyncRead + Unpin,
    queue: Arc<LineQueue>,
    max_frame_bytes: usize,
) {
    let mut buffered = Vec::new();
    let mut oversized = false;
    loop {
        let mut chunk = [0_u8; READ_CHUNK_BYTES];
        let read = match stream.read(&mut chunk).await {
            Ok(read) => read,
            Err(_) => {
                queue.close();
                return;
            }
        };
        if read == 0 {
            if !oversized && !buffered.is_empty() && buffered.len() <= max_frame_bytes {
                queue.push(String::from_utf8_lossy(&buffered).into_owned());
            }
            queue.close();
            return;
        }

        if oversized {
            let Some(newline) = chunk[..read].iter().position(|byte| *byte == b'\n') else {
                continue;
            };
            oversized = false;
            buffered.extend_from_slice(&chunk[newline + 1..read]);
        } else {
            buffered.extend_from_slice(&chunk[..read]);
        }
        while let Some(newline) = buffered.iter().position(|byte| *byte == b'\n') {
            let mut line = buffered.drain(..=newline).collect::<Vec<_>>();
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            if !oversized && line.len() <= max_frame_bytes {
                queue.push(String::from_utf8_lossy(&line).into_owned());
            }
            oversized = false;
        }
        if !oversized && buffered.len() > max_frame_bytes {
            buffered.clear();
            oversized = true;
        }
    }
}

/// A bounded line-oriented child process used by providers that expose HTTP,
/// SSE, or RPC endpoints on a local port.
///
/// On Unix the child runs in its own process group, which is stopped as a
/// whole on close, on drop, and when this process dies.
pub struct ManagedProcess {
    child: Option<Child>,
    #[cfg(unix)]
    group: Option<ProcessGroup>,
    #[cfg(not(unix))]
    tree: Option<ProcessTreeGuard>,
    lines: Receiver<Option<String>>,
    stderr_lines: Arc<LineQueue>,
    stdout_task: Option<JoinHandle<()>>,
    stderr_task: Option<JoinHandle<()>>,
    pid: Option<u32>,
    shutdown_timeout: Duration,
    closed: bool,
}

impl std::fmt::Debug for ManagedProcess {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ManagedProcess")
            .field("pid", &self.pid)
            .field("closed", &self.closed)
            .finish_non_exhaustive()
    }
}

impl ManagedProcess {
    /// Spawn a process with bounded stdout line framing and independent stderr
    /// draining. Explicit environment values take precedence over login-shell
    /// hydration, matching [`JsonLineProcess`].
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
        let explicit = config
            .env
            .iter()
            .filter_map(|(key, value)| {
                Some((key.to_str()?.to_string(), value.to_str()?.to_string()))
            })
            .collect::<BTreeMap<_, _>>();
        apply_login_shell_environment(&mut command, &explicit).await;
        command
            .args(&config.args)
            .envs(&config.env)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(cwd) = &config.cwd {
            command.current_dir(cwd);
        }
        #[cfg(unix)]
        let mut group = ProcessGroup::start(config.shutdown_timeout)
            .map_err(|source| TransportError::io("start process group", source))?;
        #[cfg(unix)]
        group.join(&mut command);
        #[cfg(not(unix))]
        {
            command.kill_on_drop(true);
            ProcessTreeGuard::prepare_command(&mut command);
        }

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(source) => {
                #[cfg(unix)]
                group.kill();
                return Err(TransportError::Spawn { executable, source });
            }
        };
        #[cfg(not(unix))]
        let tree = match ProcessTreeGuard::attach(&child) {
            Ok(tree) => tree,
            Err(reason) => {
                let _ = child.start_kill();
                let _ = child.wait().await;
                return Err(TransportError::io(
                    "attach process tree",
                    std::io::Error::other(reason),
                ));
            }
        };
        let pid = child.id();
        let stdout = match child.stdout.take() {
            Some(stdout) => stdout,
            None => {
                #[cfg(unix)]
                group.kill();
                #[cfg(not(unix))]
                tree.terminate();
                let _ = child.start_kill();
                let _ = child.wait().await;
                return Err(TransportError::io(
                    "spawn",
                    std::io::Error::other("child stdout was not piped"),
                ));
            }
        };
        let stderr = match child.stderr.take() {
            Some(stderr) => stderr,
            None => {
                #[cfg(unix)]
                group.kill();
                #[cfg(not(unix))]
                tree.terminate();
                let _ = child.start_kill();
                let _ = child.wait().await;
                return Err(TransportError::io(
                    "spawn",
                    std::io::Error::other("child stderr was not piped"),
                ));
            }
        };

        let (sender, lines) = mpsc::channel(LINE_QUEUE_CAPACITY);
        let stderr_lines = Arc::new(LineQueue::default());
        let stdout_task = tokio::spawn(drain_lines(stdout, sender, config.max_frame_bytes));
        let stderr_task = tokio::spawn(drain_stderr(
            stderr,
            Arc::clone(&stderr_lines),
            config.max_frame_bytes,
        ));
        Ok(Self {
            child: Some(child),
            #[cfg(unix)]
            group: Some(group),
            #[cfg(not(unix))]
            tree: Some(tree),
            lines,
            stderr_lines,
            stdout_task: Some(stdout_task),
            stderr_task: Some(stderr_task),
            pid,
            shutdown_timeout: config.shutdown_timeout,
            closed: false,
        })
    }

    /// Read the next complete stdout line, or `None` at EOF, malformed output,
    /// queue overflow, or after close.
    pub async fn next_stdout_line(&mut self) -> Option<String> {
        if self.closed {
            return None;
        }
        match self.lines.recv().await {
            Some(Some(line)) => Some(line),
            Some(None) | None => {
                let _ = self.close().await;
                None
            }
        }
    }

    /// Read the next complete stderr line, or `None` at stderr EOF. Stderr is
    /// drained independently so startup diagnostics such as a server's ready
    /// marker cannot fill the child pipe while stdout is idle.
    pub async fn next_stderr_line(&mut self) -> Option<String> {
        self.stderr_lines.next().await
    }

    /// Return the operating-system process id while the child is owned.
    pub fn pid(&self) -> Option<u32> {
        self.pid
    }

    /// Stop and reap the child. On Unix its whole group gets SIGTERM and,
    /// after the configured shutdown timeout, SIGKILL; elsewhere the child is
    /// killed at once and reaped within that timeout.
    pub async fn close(&mut self) -> Result<(), TransportError> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        self.pid = None;
        self.lines.close();
        self.stderr_lines.close();
        if let Some(task) = self.stdout_task.take() {
            task.abort();
        }

        let mut first_error = None;
        #[cfg(unix)]
        if let Some(group) = self.group.as_mut() {
            group.terminate();
        }
        #[cfg(not(unix))]
        if let Some(tree) = self.tree.take() {
            tree.terminate();
        }
        if let Some(mut child) = self.child.take() {
            #[cfg(not(unix))]
            let _ = child.kill().await;
            let status = tokio::time::timeout(self.shutdown_timeout, child.wait()).await;
            #[cfg(unix)]
            let status = match status {
                // The child ignored SIGTERM for the whole shutdown timeout.
                Err(_) => {
                    if let Some(group) = self.group.as_mut() {
                        group.kill();
                    }
                    tokio::time::timeout(self.shutdown_timeout, child.wait()).await
                }
                status => status,
            };
            match status {
                Ok(Ok(_)) => {}
                Ok(Err(source)) => {
                    first_error = Some(TransportError::io("wait child", source));
                }
                Err(_) => {
                    first_error = Some(TransportError::ShutdownTimeout {
                        timeout: self.shutdown_timeout,
                    });
                }
            }
        }
        // Whatever the child left running gets SIGTERM and then SIGKILL, which
        // also ends the stderr pipes such descendants inherited.
        #[cfg(unix)]
        self.group.take();
        if let Some(mut task) = self.stderr_task.take() {
            if tokio::time::timeout(self.shutdown_timeout, &mut task)
                .await
                .is_err()
            {
                task.abort();
                first_error.get_or_insert(TransportError::ShutdownTimeout {
                    timeout: self.shutdown_timeout,
                });
            }
        }
        first_error.map_or(Ok(()), Err)
    }
}

impl Drop for ManagedProcess {
    fn drop(&mut self) {
        if let Some(task) = self.stdout_task.take() {
            task.abort();
        }
        if let Some(task) = self.stderr_task.take() {
            task.abort();
        }
        // Dropping the group sends SIGTERM to the child and everything it
        // started, then SIGKILL, with or without a runtime. Tokio reaps the
        // dropped child.
        #[cfg(unix)]
        self.group.take();
        #[cfg(not(unix))]
        if let Some(tree) = self.tree.take() {
            tree.terminate();
        }
        #[cfg(not(unix))]
        if let Some(mut child) = self.child.take() {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = child.kill().await;
                    let _ = child.wait().await;
                });
            }
        }
    }
}
