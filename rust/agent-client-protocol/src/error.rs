use std::time::Duration;

#[derive(Debug, thiserror::Error)]
pub enum AcpError {
    #[error(transparent)]
    Transport(#[from] alera_agent_transport::TransportError),
    #[error("ACP JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("ACP protocol error: {0}")]
    Protocol(String),
    #[error("ACP RPC error {code}: {message}")]
    Rpc {
        code: i64,
        message: String,
        data: Option<serde_json::Value>,
    },
    #[error("ACP request `{method}` timed out after {timeout:?}")]
    Timeout { method: String, timeout: Duration },
    #[error("ACP client is closed")]
    Closed,
    #[error("ACP queue is full at {capacity} items")]
    QueueFull { capacity: usize },
    #[error("ACP method is not supported: {0}")]
    Unsupported(String),
}
