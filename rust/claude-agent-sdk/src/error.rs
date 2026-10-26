use thiserror::Error;

pub type Result<T> = std::result::Result<T, ClaudeSdkError>;

#[derive(Debug, Clone, Error)]
pub enum ClaudeSdkError {
    #[error("Claude Code CLI was not found: {0}")]
    CliNotFound(String),
    #[error("Claude Code connection failed: {0}")]
    Connection(String),
    #[error("Claude Code process failed{exit_code}: {message}")]
    Process { message: String, exit_code: String },
    #[error("transport error: {0}")]
    Transport(String),
    #[error("invalid JSON frame: {0}")]
    JsonDecode(String),
    #[error("{operation} timed out after {timeout_ms} ms")]
    Timeout { operation: String, timeout_ms: u64 },
    #[error("control request '{subtype}' failed: {message}")]
    Control { subtype: String, message: String },
    #[error("invalid options: {0}")]
    InvalidOptions(String),
    #[error("invalid client state: {0}")]
    InvalidState(String),
    #[error("callback failed: {0}")]
    Callback(String),
    #[error("unsupported Claude SDK surface: {0}")]
    Unsupported(String),
    #[error("client was closed")]
    Closed,
}

impl ClaudeSdkError {
    pub(crate) fn transport(message: impl Into<String>) -> Self {
        Self::Transport(message.into())
    }
}

impl From<serde_json::Error> for ClaudeSdkError {
    fn from(error: serde_json::Error) -> Self {
        Self::JsonDecode(error.to_string())
    }
}
