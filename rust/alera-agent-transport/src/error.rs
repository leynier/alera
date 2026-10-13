use std::io;
use std::path::PathBuf;
use std::str::Utf8Error;
use std::time::Duration;

/// Errors returned by a JSON-lines transport.
#[derive(Debug, thiserror::Error)]
pub enum TransportError {
    /// The process configuration cannot provide a usable bounded transport.
    #[error("invalid transport configuration: {reason}")]
    InvalidConfig { reason: &'static str },

    /// The child process could not be started.
    #[error("failed to spawn `{executable}`: {source}")]
    Spawn {
        executable: PathBuf,
        #[source]
        source: io::Error,
    },

    /// An I/O operation on the process pipes failed.
    #[error("transport {operation} failed: {source}")]
    Io {
        operation: &'static str,
        #[source]
        source: io::Error,
    },

    /// A serialized or received frame exceeded the configured limit.
    #[error("JSON frame is too large: {observed} bytes exceeds the {limit}-byte limit")]
    FrameTooLarge { limit: usize, observed: usize },

    /// The caller did not consume received messages quickly enough.
    #[error("received message queue is full at {capacity} messages")]
    OutputQueueFull { capacity: usize },

    /// A received frame was not valid UTF-8.
    #[error("received JSON frame is not valid UTF-8: {source}")]
    InvalidUtf8 {
        #[source]
        source: Utf8Error,
    },

    /// A received UTF-8 frame was not valid JSON.
    #[error("received invalid JSON: {source}")]
    InvalidJson {
        #[source]
        source: serde_json::Error,
    },

    /// A value could not be serialized for the outgoing protocol.
    #[error("could not serialize JSON frame: {source}")]
    Serialize {
        #[source]
        source: serde_json::Error,
    },

    /// The child closed the protocol unexpectedly or exited unsuccessfully.
    #[error("provider process exited{}{}", format_exit_code(*code), format_stderr(stderr))]
    ProcessExited { code: Option<i32>, stderr: String },

    /// The transport was used after it was closed.
    #[error("transport is closed")]
    Closed,

    /// The child did not stop within the configured shutdown timeout.
    #[error("provider process did not stop within {timeout:?}")]
    ShutdownTimeout { timeout: Duration },

    /// A write to the child did not complete within the configured timeout.
    #[error("transport {operation} timed out after {timeout:?}")]
    IoTimeout {
        operation: &'static str,
        timeout: Duration,
    },
}

fn format_exit_code(code: Option<i32>) -> String {
    code.map_or_else(String::new, |code| format!(" with exit code {code}"))
}

fn format_stderr(stderr: &str) -> String {
    if stderr.is_empty() {
        String::new()
    } else {
        format!("; stderr tail: {stderr:?}")
    }
}

impl TransportError {
    pub(crate) fn io(operation: &'static str, source: io::Error) -> Self {
        Self::Io { operation, source }
    }
}
