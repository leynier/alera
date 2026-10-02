//! Bounded output capture shared by the desktop bridge and the terminal host.
//!
//! A command may write stdout and stderr at the same time. Reading both pipes
//! concurrently avoids the deadlock that a sequential reader can create, and
//! one atomic byte budget keeps an untrusted command from growing memory
//! without bound. The process tree guard also survives reaping the direct
//! child, which is required when a shell descendant still owns a pipe.

use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::process::{Child, Command};
use tokio::task::JoinError;

#[path = "captured_process_tasks.rs"]
mod process_tasks;
use process_tasks::AbortOnDrop;

#[path = "captured_process_tree.rs"]
mod process_tree;
pub use process_tree::ProcessTreeGuard;

pub const DEFAULT_MAX_OUTPUT_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_OUTPUT_BYTES: usize = 64 * 1024 * 1024;
const READ_CHUNK_BYTES: usize = 64 * 1024;
// A child can have already exited while the OS still has a large final pipe
// buffer to deliver. Keep this bounded, but leave loaded desktops enough time
// to preserve that tail before declaring a detached descendant.
const DRAIN_GRACE: Duration = Duration::from_secs(2);

pub struct CapturedProcessOutput {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Runs a fully configured command with bounded concurrent stdout/stderr
/// capture. `timeout = None` preserves the historical no-timeout behavior.
/// When a limit, read, wait, or timeout error occurs, the process tree is
/// terminated and reaped before the error is returned.
pub async fn run_command(
    mut command: Command,
    executable: &str,
    stdin: Option<Vec<u8>>,
    max_output_bytes: usize,
    timeout: Option<Duration>,
) -> Result<CapturedProcessOutput, String> {
    if !(1..=MAX_OUTPUT_BYTES).contains(&max_output_bytes) {
        return Err(format!(
            "process output limit must be between 1 and {MAX_OUTPUT_BYTES} bytes"
        ));
    }
    command
        .stdin(if stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    ProcessTreeGuard::prepare_command(&mut command);
    let mut child = command
        .spawn()
        .map_err(|error| format!("failed to run {executable}: {error}"))?;
    let tree = match ProcessTreeGuard::attach(&child) {
        Ok(tree) => tree,
        Err(error) => {
            let _ = child.start_kill();
            let _ = child.wait().await;
            return Err(format!("{executable}: {error}"));
        }
    };
    let stdout = match child.stdout.take() {
        Some(stdout) => stdout,
        None => {
            terminate_and_reap(&mut child, &tree).await;
            return Err(format!("failed to capture stdout from {executable}"));
        }
    };
    let stderr = match child.stderr.take() {
        Some(stderr) => stderr,
        None => {
            terminate_and_reap(&mut child, &tree).await;
            return Err(format!("failed to capture stderr from {executable}"));
        }
    };
    let mut stdin_task = child.stdin.take().map(|mut pipe| {
        AbortOnDrop::new(tokio::spawn(async move {
            if let Some(data) = stdin {
                let _ = pipe.write_all(&data).await;
            }
            let _ = pipe.shutdown().await;
        }))
    });
    let budget = Arc::new(OutputBudget::new(max_output_bytes));
    let mut stdout_task = AbortOnDrop::new(tokio::spawn(read_pipe(
        stdout,
        Arc::clone(&budget),
        "stdout",
    )));
    let mut stderr_task = AbortOnDrop::new(tokio::spawn(read_pipe(stderr, budget, "stderr")));
    let mut stdout_result = None;
    let mut stderr_result = None;
    let mut exit_result = None;
    let timeout_message = timeout.map(|value| format!("{}ms", value.as_millis()));
    let timeout_future = async move {
        match timeout {
            Some(timeout) => tokio::time::sleep(timeout).await,
            None => std::future::pending().await,
        }
    };
    tokio::pin!(timeout_future);

    loop {
        tokio::select! {
            _ = timeout_future.as_mut() => {
                terminate_and_reap(&mut child, &tree).await;
                abort_pending(
                    &mut stdout_task,
                    &mut stderr_task,
                    &mut stdin_task,
                    &stdout_result,
                    &stderr_result,
                )
                .await;
                return Err(format!(
                    "{executable}: process timed out after {}",
                    timeout_message.as_deref().unwrap_or("the configured timeout"),
                ));
            }
            result = stdout_task.as_mut().expect("stdout task is present"), if stdout_result.is_none() => {
                stdout_result = Some(join_reader(result, "stdout"));
            }
            result = stderr_task.as_mut().expect("stderr task is present"), if stderr_result.is_none() => {
                stderr_result = Some(join_reader(result, "stderr"));
            }
            result = child.wait(), if exit_result.is_none() => {
                exit_result = Some(
                    result
                        .map(|status| status.code().unwrap_or(-1))
                        .map_err(|error| error.to_string()),
                );
            }
        }

        if stdout_result.as_ref().is_some_and(Result::is_err)
            || stderr_result.as_ref().is_some_and(Result::is_err)
        {
            let message = stdout_result
                .as_ref()
                .and_then(|result| result.as_ref().err())
                .or_else(|| {
                    stderr_result
                        .as_ref()
                        .and_then(|result| result.as_ref().err())
                })
                .map(ToString::to_string)
                .unwrap_or_else(|| "process output capture failed".to_string());
            terminate_and_reap(&mut child, &tree).await;
            abort_pending(
                &mut stdout_task,
                &mut stderr_task,
                &mut stdin_task,
                &stdout_result,
                &stderr_result,
            )
            .await;
            return Err(format!("{executable}: {message}"));
        }
        if exit_result.is_some() {
            break;
        }
    }

    let drained = tokio::time::timeout(
        DRAIN_GRACE,
        finish_readers(
            &mut stdout_task,
            &mut stderr_task,
            &mut stdout_result,
            &mut stderr_result,
        ),
    )
    .await;
    if drained.is_err() {
        terminate_and_reap(&mut child, &tree).await;
        abort_pending(
            &mut stdout_task,
            &mut stderr_task,
            &mut stdin_task,
            &stdout_result,
            &stderr_result,
        )
        .await;
        return Err(format!(
            "{executable}: process output did not drain before the cleanup grace period"
        ));
    }
    if let Some(stdin_task) = stdin_task.as_mut() {
        if tokio::time::timeout(
            DRAIN_GRACE,
            stdin_task.as_mut().expect("stdin task is present"),
        )
        .await
        .is_ok()
        {
            let _ = stdin_task.take();
        } else {
            stdin_task.abort_and_join().await;
        }
    }
    tree.terminate();

    let exit_code = match exit_result.expect("child exit result is present after the wait loop") {
        Ok(exit_code) => exit_code,
        Err(error) => {
            terminate_and_reap(&mut child, &tree).await;
            return Err(format!("{executable}: failed waiting for process: {error}"));
        }
    };
    let stdout = match stdout_result {
        Some(Ok(bytes)) => String::from_utf8_lossy(&bytes).into_owned(),
        Some(Err(error)) => return Err(format!("{executable}: {error}")),
        None => String::new(),
    };
    let stderr = match stderr_result {
        Some(Ok(bytes)) => String::from_utf8_lossy(&bytes).into_owned(),
        Some(Err(error)) => return Err(format!("{executable}: {error}")),
        None => String::new(),
    };
    Ok(CapturedProcessOutput {
        exit_code,
        stdout,
        stderr,
    })
}

struct OutputBudget {
    used: std::sync::atomic::AtomicUsize,
    limit: usize,
}

impl OutputBudget {
    fn new(limit: usize) -> Self {
        Self {
            used: std::sync::atomic::AtomicUsize::new(0),
            limit,
        }
    }

    fn reserve(&self, bytes: usize) -> bool {
        use std::sync::atomic::Ordering;

        let mut current = self.used.load(Ordering::Acquire);
        loop {
            let Some(next) = current.checked_add(bytes) else {
                return false;
            };
            if next > self.limit {
                return false;
            }
            match self.used.compare_exchange_weak(
                current,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => return true,
                Err(observed) => current = observed,
            }
        }
    }
}

#[derive(Debug)]
enum CaptureError {
    OutputLimit {
        stream: &'static str,
        limit: usize,
    },
    Read {
        stream: &'static str,
        message: String,
    },
}

impl std::fmt::Display for CaptureError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::OutputLimit { stream, limit } => write!(
                formatter,
                "{stream} exceeded the combined process output limit of {limit} bytes",
            ),
            Self::Read { stream, message } => {
                write!(formatter, "failed reading {stream}: {message}")
            }
        }
    }
}

async fn read_pipe<R>(
    mut reader: R,
    budget: Arc<OutputBudget>,
    stream: &'static str,
) -> Result<Vec<u8>, CaptureError>
where
    R: AsyncRead + Send + Unpin + 'static,
{
    let mut output = Vec::new();
    let mut buffer = vec![0_u8; READ_CHUNK_BYTES];
    loop {
        let read = reader
            .read(&mut buffer)
            .await
            .map_err(|error| CaptureError::Read {
                stream,
                message: error.to_string(),
            })?;
        if read == 0 {
            return Ok(output);
        }
        if !budget.reserve(read) {
            return Err(CaptureError::OutputLimit {
                stream,
                limit: budget.limit,
            });
        }
        output.extend_from_slice(&buffer[..read]);
    }
}

fn join_reader(
    result: Result<Result<Vec<u8>, CaptureError>, JoinError>,
    stream: &'static str,
) -> Result<Vec<u8>, CaptureError> {
    result.map_err(|error| CaptureError::Read {
        stream,
        message: error.to_string(),
    })?
}

async fn finish_readers(
    stdout_task: &mut AbortOnDrop<Result<Vec<u8>, CaptureError>>,
    stderr_task: &mut AbortOnDrop<Result<Vec<u8>, CaptureError>>,
    stdout_result: &mut Option<Result<Vec<u8>, CaptureError>>,
    stderr_result: &mut Option<Result<Vec<u8>, CaptureError>>,
) {
    if stdout_result.is_none() {
        *stdout_result = Some(join_reader(stdout_task.join().await, "stdout"));
    }
    if stderr_result.is_none() {
        *stderr_result = Some(join_reader(stderr_task.join().await, "stderr"));
    }
}

async fn abort_pending(
    stdout_task: &mut AbortOnDrop<Result<Vec<u8>, CaptureError>>,
    stderr_task: &mut AbortOnDrop<Result<Vec<u8>, CaptureError>>,
    stdin_task: &mut Option<AbortOnDrop<()>>,
    stdout_result: &Option<Result<Vec<u8>, CaptureError>>,
    stderr_result: &Option<Result<Vec<u8>, CaptureError>>,
) {
    if stdout_result.is_none() {
        stdout_task.abort_and_join().await;
    }
    if stderr_result.is_none() {
        stderr_task.abort_and_join().await;
    }
    if let Some(stdin_task) = stdin_task.take() {
        let mut stdin_task = stdin_task;
        stdin_task.abort_and_join().await;
    }
}

async fn terminate_and_reap(child: &mut Child, tree: &ProcessTreeGuard) {
    tree.terminate();
    let _ = child.start_kill();
    let _ = child.wait().await;
}

#[cfg(test)]
#[path = "captured_process_tests.rs"]
mod tests;
