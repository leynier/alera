//! Spawning and streaming for the commands the app runs on the user's machine.
//!
//! The app process is a GUI-subsystem binary with no console, so every child
//! here goes through `alera_core::child_process::windowless_async_command`.
//! That is the whole reason these spawns live in Rust: `dart:io` cannot pass
//! `CREATE_NO_WINDOW`, so a `Process.run` from Flutter flashes a console window
//! on Windows for as long as the command runs.

use std::collections::HashMap;
use std::process::Stdio;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use tokio::io::AsyncWriteExt;
use tokio::process::{Child, Command};
use tokio::runtime::{Builder, Runtime};
use tokio::sync::{mpsc, Notify};

#[cfg(test)]
use super::ProcessRunResult;
use super::{ProcessEvent, ProcessEventKind};
use crate::frb_generated::StreamSink;

#[path = "process_stdin.rs"]
mod process_stdin;
use process_stdin::{StdinBudget, StdinChunk, PROCESS_STDIN_QUEUE_CAPACITY};

#[path = "process_session_output.rs"]
mod process_session_output;
use process_session_output::{forward, DRAIN_GRACE};

/// A running command the Dart side still holds a handle to.
struct Session {
    /// Dropped by `close_stdin`, which is what closes the child's stdin.
    stdin: Option<mpsc::Sender<StdinChunk>>,
    stdin_budget: Arc<StdinBudget>,
    kill: Arc<Notify>,
}

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static SESSIONS: OnceLock<Mutex<HashMap<i64, Session>>> = OnceLock::new();
static NEXT_SESSION_ID: AtomicI64 = AtomicI64::new(1);

#[cfg(test)]
fn run_with_environment_mode(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    include_parent_environment: bool,
) -> Result<ProcessRunResult, String> {
    let mut command = build_command(
        &executable,
        &arguments,
        working_directory,
        environment,
        include_parent_environment,
    );
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // `Command::output` spawns eagerly, so it has to be called inside the
    // runtime: on unix the child registers with the signal driver at spawn.
    let output = runtime()
        .block_on(async move { command.output().await })
        .map_err(|error| format!("failed to run {executable}: {error}"))?;
    Ok(ProcessRunResult {
        exit_code: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}

#[cfg(test)]
pub(super) fn run_without_parent_environment_for_tests(
    executable: String,
    arguments: Vec<String>,
    environment: HashMap<String, String>,
) -> Result<ProcessRunResult, String> {
    run_with_environment_mode(executable, arguments, None, Some(environment), false)
}

pub(super) fn start(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    include_parent_environment: bool,
    events: StreamSink<ProcessEvent>,
) {
    let mut command = build_command(
        &executable,
        &arguments,
        working_directory,
        environment,
        include_parent_environment,
    );
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    alera_core::captured_process::ProcessTreeGuard::prepare_command(&mut command);
    // `tokio::process` registers the child with the runtime's IO driver, so the
    // spawn itself has to happen inside the runtime context.
    let guard = runtime().enter();
    let spawned = command.spawn();
    drop(guard);
    let mut child = match spawned {
        Ok(child) => child,
        Err(error) => {
            emit_failure(&events, format!("failed to start {executable}: {error}"));
            return;
        }
    };
    let tree = match alera_core::captured_process::ProcessTreeGuard::attach(&child) {
        Ok(tree) => tree,
        Err(error) => {
            abort_unowned_child(child, None);
            emit_failure(&events, format!("failed to start {executable}: {error}"));
            return;
        }
    };

    let pid = child.id().unwrap_or_default() as i32;
    let stdin = child.stdin.take();
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let (writes, incoming) = mpsc::channel(PROCESS_STDIN_QUEUE_CAPACITY);
    let stdin_budget = StdinBudget::new();
    let kill = Arc::new(Notify::new());
    match sessions().lock() {
        Ok(mut sessions) => {
            sessions.insert(
                id,
                Session {
                    stdin: Some(writes),
                    stdin_budget,
                    kill: kill.clone(),
                },
            );
        }
        Err(_) => {
            emit_failure(&events, "process registry lock poisoned".to_string());
            abort_unowned_child(child, Some(tree));
            return;
        }
    }

    let sink = Arc::new(events);
    // The session id travels in band: a stream function cannot also return a
    // value, and buffering output until a second call attached would risk
    // losing the first bytes a fast command writes.
    if sink
        .add(ProcessEvent {
            kind: ProcessEventKind::Started,
            session_id: id,
            pid,
            data: Vec::new(),
            exit_code: 0,
            message: String::new(),
        })
        .is_err()
    {
        forget_session(id);
        abort_unowned_child(child, Some(tree));
        return;
    }

    runtime().spawn(async move {
        if let Some(mut stdin) = stdin {
            let mut incoming = incoming;
            tokio::spawn(async move {
                while let Some(chunk) = incoming.recv().await {
                    if stdin.write_all(&chunk.data).await.is_err() {
                        break;
                    }
                    let _ = stdin.flush().await;
                }
            });
        }
        let mut stdout = forward(stdout, sink.clone(), ProcessEventKind::Stdout);
        let mut stderr = forward(stderr, sink.clone(), ProcessEventKind::Stderr);
        let status = wait_for_exit(&mut child, &tree, kill).await;
        // Both readers are drained before the exit is announced, so a listener
        // that stops on `exitCode` cannot miss output the child already wrote.
        // Bounded, because a grandchild that outlived the shell still holds the
        // pipes open and must not strand the exit event.
        let drained = tokio::time::timeout(DRAIN_GRACE, async {
            let stdout_result = (&mut stdout).await;
            let stderr_result = (&mut stderr).await;
            (stdout_result, stderr_result)
        })
        .await;
        match drained {
            Ok((stdout_result, stderr_result)) => {
                tree.terminate();
                let stream_error = stdout_result.err().or_else(|| stderr_result.err());
                if let Some(stream_error) = stream_error {
                    emit_failure(
                        &sink,
                        format!("process {executable} output failed: {stream_error}"),
                    );
                } else {
                    emit_exit(&sink, id, pid, status);
                }
            }
            Err(_) => {
                tree.terminate();
                stdout.abort();
                stderr.abort();
                let _ = stdout.await;
                let _ = stderr.await;
                emit_failure(
                    &sink,
                    format!(
                        "process {executable} output did not drain before the cleanup grace period"
                    ),
                );
            }
        }
        forget_session(id);
    });
}

/// A process started before its session became observable has no caller that
/// can issue `kill`. Reap it immediately instead of letting a dropped Tokio
/// child continue as an untracked orphan.
fn abort_unowned_child(
    mut child: Child,
    tree: Option<alera_core::captured_process::ProcessTreeGuard>,
) {
    runtime().spawn(async move {
        if let Some(tree) = tree {
            tree.terminate();
        }
        let _ = child.start_kill();
        let _ = child.wait().await;
    });
}

pub(super) fn write_stdin(id: i64, data: Vec<u8>) -> bool {
    let Ok(sessions) = sessions().lock() else {
        return false;
    };
    let Some(session) = sessions.get(&id) else {
        return false;
    };
    let Some(stdin) = session.stdin.as_ref() else {
        return false;
    };
    if !session.stdin_budget.try_reserve(data.len()) {
        return false;
    }
    stdin
        .try_send(StdinChunk::new(data, Arc::clone(&session.stdin_budget)))
        .is_ok()
}

pub(super) fn close_stdin(id: i64) {
    if let Ok(mut sessions) = sessions().lock() {
        if let Some(session) = sessions.get_mut(&id) {
            session.stdin = None;
        }
    }
}

pub(super) fn kill(id: i64) -> bool {
    let Ok(sessions) = sessions().lock() else {
        return false;
    };
    let Some(session) = sessions.get(&id) else {
        return false;
    };
    session.kill.notify_one();
    true
}

fn build_command(
    executable: &str,
    arguments: &[String],
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    include_parent_environment: bool,
) -> Command {
    alera_core::shell_command::shell_command(
        executable,
        arguments,
        working_directory.as_deref(),
        environment.as_ref(),
        include_parent_environment,
    )
}

/// Waits for the child, killing it if the Dart side asks in the meantime.
/// `Child::wait` is cancel safe, so losing the race in `select!` costs nothing.
async fn wait_for_exit(
    child: &mut Child,
    tree: &alera_core::captured_process::ProcessTreeGuard,
    kill: Arc<Notify>,
) -> Result<i32, String> {
    loop {
        tokio::select! {
            status = child.wait() => {
                return match status {
                    Ok(status) => Ok(status.code().unwrap_or(-1)),
                    Err(error) => {
                        tree.terminate();
                        let _ = child.start_kill();
                        let _ = child.wait().await;
                        Err(error.to_string())
                    }
                };
            }
            _ = kill.notified() => {
                tree.terminate();
                let _ = child.start_kill();
            }
        }
    }
}

#[cfg(any(windows, test))]
pub(super) fn windows_process_tree_kill_arguments(pid: u32) -> Vec<String> {
    vec![
        "/PID".to_string(),
        pid.to_string(),
        "/T".to_string(),
        "/F".to_string(),
    ]
}

fn emit_exit(sink: &StreamSink<ProcessEvent>, id: i64, pid: i32, status: Result<i32, String>) {
    let event = match status {
        Ok(exit_code) => ProcessEvent {
            kind: ProcessEventKind::Exit,
            session_id: id,
            pid,
            data: Vec::new(),
            exit_code,
            message: String::new(),
        },
        Err(message) => ProcessEvent {
            kind: ProcessEventKind::Failure,
            session_id: id,
            pid,
            data: Vec::new(),
            exit_code: -1,
            message,
        },
    };
    let _ = sink.add(event);
}

fn emit_failure(sink: &StreamSink<ProcessEvent>, message: String) {
    let _ = sink.add(ProcessEvent {
        kind: ProcessEventKind::Failure,
        session_id: 0,
        pid: 0,
        data: Vec::new(),
        exit_code: -1,
        message,
    });
}

fn forget_session(id: i64) {
    if let Ok(mut sessions) = sessions().lock() {
        sessions.remove(&id);
    }
}

fn sessions() -> &'static Mutex<HashMap<i64, Session>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_time()
            .enable_io()
            .thread_name("alera-process")
            .build()
            .expect("failed to build process runtime")
    })
}

#[cfg(test)]
pub(super) fn wait_for_exit_in_tests(
    executable: &str,
    arguments: &[String],
    kill: std::sync::Arc<Notify>,
    delay: std::time::Duration,
) -> Result<i32, String> {
    let mut command = build_command(executable, arguments, None, None, true);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    alera_core::captured_process::ProcessTreeGuard::prepare_command(&mut command);
    runtime().block_on(async move {
        let mut child = command.spawn().map_err(|error| error.to_string())?;
        let tree = alera_core::captured_process::ProcessTreeGuard::attach(&child)?;
        // Held open the way `start` does, so the child keeps waiting on stdin
        // instead of seeing the EOF `Child::wait` would cause by dropping it.
        let _stdin = child.stdin.take();
        let signal = kill.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            signal.notify_one();
        });
        wait_for_exit(&mut child, &tree, kill).await
    })
}

#[cfg(test)]
mod tests {
    use super::process_stdin::PROCESS_STDIN_MAX_QUEUED_BYTES;
    use super::*;

    #[test]
    fn stdin_queue_rejects_writes_after_its_bounded_capacity() {
        let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = mpsc::channel(PROCESS_STDIN_QUEUE_CAPACITY);
        sessions().lock().expect("process registry lock").insert(
            id,
            Session {
                stdin: Some(sender),
                stdin_budget: StdinBudget::new(),
                kill: Arc::new(Notify::new()),
            },
        );

        for _ in 0..PROCESS_STDIN_QUEUE_CAPACITY {
            assert!(write_stdin(id, vec![b'x']));
        }
        assert!(!write_stdin(id, vec![b'x']));

        drop(receiver);
        sessions()
            .lock()
            .expect("process registry lock")
            .remove(&id);
    }

    #[test]
    fn stdin_queue_rejects_a_chunk_that_exceeds_its_byte_budget() {
        let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
        let (sender, receiver) = mpsc::channel(PROCESS_STDIN_QUEUE_CAPACITY);
        sessions().lock().expect("process registry lock").insert(
            id,
            Session {
                stdin: Some(sender),
                stdin_budget: StdinBudget::new(),
                kill: Arc::new(Notify::new()),
            },
        );

        assert!(write_stdin(id, vec![b'x'; PROCESS_STDIN_MAX_QUEUED_BYTES]));
        assert!(!write_stdin(id, vec![b'x']));

        drop(receiver);
        sessions()
            .lock()
            .expect("process registry lock")
            .remove(&id);
    }
}
