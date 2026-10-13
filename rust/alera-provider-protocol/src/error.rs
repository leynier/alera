use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProviderError {
    #[error(transparent)]
    Transport(#[from] alera_agent_transport::TransportError),
    #[error("provider protocol error: {0}")]
    Protocol(String),
    #[error("invalid provider state: {0}")]
    InvalidState(String),
    #[error("invalid provider input: {0}")]
    Validation(String),
    #[error("unsupported provider operation: {0}")]
    Unsupported(String),
    #[error("provider RPC error {code}: {message}")]
    Rpc {
        code: i64,
        message: String,
        data: Option<serde_json::Value>,
    },
    #[error("provider operation timed out: {operation}")]
    Timeout { operation: String },
    #[error("provider connection is closed")]
    Closed,
}

pub(crate) fn nonempty(value: &str, name: &str) -> Result<(), ProviderError> {
    if value.trim().is_empty() {
        return Err(ProviderError::Validation(format!(
            "{name} must not be empty"
        )));
    }
    Ok(())
}
