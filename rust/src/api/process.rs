//! The process boundary the app spawns through.
//!
//! Dart cannot ask Windows for a windowless console, so `Process.run` from the
//! GUI-subsystem runner opens a console window for every `gh`, `az`, `ollama`
//! or setup command it runs. Routing those spawns through here keeps one
//! implementation for all three platforms and lets the sidecar's spawn rules
//! (`alera_core::child_process`) apply to the app as well.

use std::collections::HashMap;

use crate::frb_generated::StreamSink;

#[path = "process_session.rs"]
mod process_session;
#[path = "process_shell.rs"]
mod process_shell;

pub struct ProcessRunResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// What a running process reported. `Started` always arrives first and carries
/// the session id the other calls take; output arrives as it is produced; `Exit`
/// and `Failure` are terminal and arrive once the output is drained.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProcessEventKind {
    Started,
    Stdout,
    Stderr,
    Exit,
    Failure,
}

pub struct ProcessEvent {
    pub kind: ProcessEventKind,
    pub session_id: i64,
    pub pid: i32,
    pub data: Vec<u8>,
    pub exit_code: i32,
    pub message: String,
}

/// Runs a command to completion and returns everything it wrote.
pub fn process_run(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
) -> Result<ProcessRunResult, String> {
    process_session::run(executable, arguments, working_directory, environment)
}

/// Starts a command and streams its output until it exits. A spawn that fails
/// reports a `Failure` event rather than an error, so callers only ever read the
/// stream. The session id is valid until `Exit` or `Failure` arrives.
pub fn process_start(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    include_parent_environment: bool,
    events: StreamSink<ProcessEvent>,
) {
    process_session::start(
        executable,
        arguments,
        working_directory,
        environment,
        include_parent_environment,
        events,
    );
}

/// Queues `data` for the process's stdin. False once the process is gone or its
/// stdin was closed.
pub fn process_write_stdin(id: i64, data: Vec<u8>) -> bool {
    process_session::write_stdin(id, data)
}

/// Closes the process's stdin, which is what a child waiting on EOF needs.
pub fn process_close_stdin(id: i64) {
    process_session::close_stdin(id);
}

/// Kills the process. Reaches the direct child only, matching `Process.kill`.
pub fn process_kill(id: i64) -> bool {
    process_session::kill(id)
}

#[cfg(test)]
#[path = "process_tests.rs"]
mod process_tests;
