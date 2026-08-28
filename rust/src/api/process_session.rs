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

use alera_core::child_process::windowless_async_command;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};
use tokio::process::{Child, Command};
use tokio::runtime::{Builder, Runtime};
use tokio::sync::{mpsc, Notify};

use super::process_shell::{shell_invocation, ShellInvocation};
use super::{ProcessEvent, ProcessEventKind, ProcessRunResult};
use crate::frb_generated::StreamSink;

const READ_CHUNK_BYTES: usize = 64 * 1024;

/// How long output already in flight may take to drain once the child exited.
const DRAIN_GRACE: std::time::Duration = std::time::Duration::from_millis(250);

/// A running command the Dart side still holds a handle to.
struct Session {
    /// Dropped by `close_stdin`, which is what closes the child's stdin.
    stdin: Option<mpsc::UnboundedSender<Vec<u8>>>,
    kill: Arc<Notify>,
}

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static SESSIONS: OnceLock<Mutex<HashMap<i64, Session>>> = OnceLock::new();
static NEXT_SESSION_ID: AtomicI64 = AtomicI64::new(1);

pub(super) fn run(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
) -> Result<ProcessRunResult, String> {
    let mut command = build_command(&executable, &arguments, working_directory, environment);
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

pub(super) fn start(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    events: StreamSink<ProcessEvent>,
) {
    let mut command = build_command(&executable, &arguments, working_directory, environment);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
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

    let pid = child.id().unwrap_or_default() as i32;
    let stdin = child.stdin.take();
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
    let (writes, incoming) = mpsc::unbounded_channel();
    let kill = Arc::new(Notify::new());
    match sessions().lock() {
        Ok(mut sessions) => {
            sessions.insert(
                id,
                Session {
                    stdin: Some(writes),
                    kill: kill.clone(),
                },
            );
        }
        Err(_) => {
            emit_failure(&events, "process registry lock poisoned".to_string());
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
        return;
    }

    runtime().spawn(async move {
        if let Some(mut stdin) = stdin {
            let mut incoming = incoming;
            tokio::spawn(async move {
                while let Some(chunk) = incoming.recv().await {
                    if stdin.write_all(&chunk).await.is_err() {
                        break;
                    }
                    let _ = stdin.flush().await;
                }
            });
        }
        let stdout = forward(stdout, sink.clone(), ProcessEventKind::Stdout);
        let stderr = forward(stderr, sink.clone(), ProcessEventKind::Stderr);
        let status = wait_for_exit(&mut child, kill).await;
        // Both readers are drained before the exit is announced, so a listener
        // that stops on `exitCode` cannot miss output the child already wrote.
        // Bounded, because a grandchild that outlived the shell still holds the
        // pipes open and must not strand the exit event.
        let drained = tokio::time::timeout(DRAIN_GRACE, async {
            let _ = tokio::join!(stdout, stderr);
        })
        .await;
        let _ = drained;
        emit_exit(&sink, id, pid, status);
        forget_session(id);
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
    stdin.send(data).is_ok()
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
) -> Command {
    let mut command = match shell_invocation(executable, arguments) {
        ShellInvocation::Posix { program, arguments } => {
            let mut command = windowless_async_command(program);
            command.args(arguments);
            command
        }
        ShellInvocation::Windows {
            program,
            raw_arguments,
        } => {
            #[cfg_attr(not(windows), allow(unused_mut))]
            let mut command = windowless_async_command(program);
            #[cfg(windows)]
            {
                command.raw_arg(&raw_arguments);
            }
            #[cfg(not(windows))]
            {
                let _ = raw_arguments;
            }
            command
        }
    };
    if let Some(working_directory) = working_directory {
        command.current_dir(working_directory);
    }
    if let Some(environment) = environment {
        // Additive, like `Process.run(includeParentEnvironment: true)`.
        command.envs(environment);
    }
    // The shell does not necessarily exec the command it was given, so killing
    // the child alone can leave the real process running with the output pipes
    // still open. Its own group makes the whole invocation killable at once.
    #[cfg(unix)]
    command.process_group(0);
    command.kill_on_drop(true);
    command
}

/// Waits for the child, killing it if the Dart side asks in the meantime.
/// `Child::wait` is cancel safe, so losing the race in `select!` costs nothing.
async fn wait_for_exit(child: &mut Child, kill: Arc<Notify>) -> Result<i32, String> {
    loop {
        tokio::select! {
            status = child.wait() => {
                return status
                    .map(|status| status.code().unwrap_or(-1))
                    .map_err(|error| error.to_string());
            }
            _ = kill.notified() => {
                kill_group(child);
                let _ = child.start_kill();
            }
        }
    }
}

/// Signals everything the invocation started, not just the shell that fronts
/// it. Windows has no equivalent here: `start_kill` reaches `cmd.exe` alone,
/// which is what `Process.kill` did before this moved into Rust.
#[allow(unused_variables)]
fn kill_group(child: &Child) {
    #[cfg(unix)]
    if let Some(pid) = child.id() {
        // Safe: `kill` only reads the group id, and a group that already exited
        // yields ESRCH.
        unsafe {
            libc::kill(-(pid as i32), libc::SIGKILL);
        }
    }
}

fn forward<R>(
    reader: Option<R>,
    sink: Arc<StreamSink<ProcessEvent>>,
    kind: ProcessEventKind,
) -> tokio::task::JoinHandle<()>
where
    R: AsyncRead + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let Some(mut reader) = reader else {
            return;
        };
        let mut buffer = vec![0_u8; READ_CHUNK_BYTES];
        loop {
            match reader.read(&mut buffer).await {
                Ok(0) | Err(_) => return,
                Ok(read) => {
                    let event = ProcessEvent {
                        kind,
                        session_id: 0,
                        pid: 0,
                        data: buffer[..read].to_vec(),
                        exit_code: 0,
                        message: String::new(),
                    };
                    // A closed sink means the Dart listener is gone; the child
                    // keeps running and is still reaped below.
                    if sink.add(event).is_err() {
                        return;
                    }
                }
            }
        }
    })
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
    let mut command = build_command(executable, arguments, None, None);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    runtime().block_on(async move {
        let mut child = command.spawn().map_err(|error| error.to_string())?;
        // Held open the way `start` does, so the child keeps waiting on stdin
        // instead of seeing the EOF `Child::wait` would cause by dropping it.
        let _stdin = child.stdin.take();
        let signal = kill.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            signal.notify_one();
        });
        wait_for_exit(&mut child, kill).await
    })
}
