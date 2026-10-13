use alera_agent_transport::TransportError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum MuseSdkError {
    #[error(transparent)]
    Transport(#[from] TransportError),
    #[error("MSP protocol error: {0}")]
    Protocol(String),
    #[error("MSP RPC error {code}: {message}")]
    Rpc {
        code: i64,
        message: String,
        data: Option<serde_json::Value>,
    },
    #[error("MSP operation timed out: {operation}")]
    Timeout { operation: String },
    #[error("MSP client is closed")]
    Closed,
    #[error("invalid MSP client state: {0}")]
    InvalidState(String),
    #[error("unsupported MSP operation: {0}")]
    Unsupported(String),
}

pub type Result<T> = std::result::Result<T, MuseSdkError>;
