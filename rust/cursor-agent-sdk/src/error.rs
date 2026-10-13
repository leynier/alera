use std::time::Duration;

#[derive(Debug, thiserror::Error)]
pub enum CursorSdkError {
    #[error("cursor bridge transport failed: {0}")]
    Transport(String),
    #[error("cursor bridge returned HTTP status {status}: {message}")]
    Http { status: u16, message: String },
    #[error("cursor bridge RPC `{method}` failed with {code}: {message}")]
    Rpc {
        method: String,
        code: String,
        message: String,
        details: serde_json::Value,
    },
    #[error("cursor bridge protocol error: {0}")]
    Protocol(String),
    #[error("cursor bridge is closed")]
    Closed,
    #[error("cursor bridge operation `{operation}` timed out after {timeout:?}")]
    Timeout {
        operation: String,
        timeout: Duration,
    },
    #[error("cursor bridge ready handshake failed: {0}")]
    Handshake(String),
    #[error("cursor bridge process failed: {0}")]
    Process(String),
}

impl From<alera_agent_http::HttpError> for CursorSdkError {
    fn from(error: alera_agent_http::HttpError) -> Self {
        match error {
            alera_agent_http::HttpError::Timeout { operation, timeout } => Self::Timeout {
                operation: operation.into(),
                timeout,
            },
            other => Self::Transport(other.to_string()),
        }
    }
}
