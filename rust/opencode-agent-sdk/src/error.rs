use std::fmt;

#[derive(Debug, thiserror::Error)]
pub enum OpenCodeError {
    #[error("OpenCode HTTP transport failed: {0}")]
    Transport(String),
    #[error("OpenCode returned HTTP {status}: {message}")]
    Http { status: u16, message: String },
    #[error("invalid OpenCode response: {0}")]
    Protocol(String),
    #[error("OpenCode request timed out: {operation}")]
    Timeout { operation: String },
    #[error("OpenCode client is closed")]
    Closed,
    #[error("OpenCode operation is unsupported: {0}")]
    Unsupported(String),
    #[error("OpenCode SSE frame exceeded {limit} bytes")]
    FrameTooLarge { limit: usize },
    #[error("OpenCode SSE stream was not valid UTF-8")]
    InvalidUtf8,
    #[error("OpenCode SSE stream ended before a complete event")]
    IncompleteSse,
}

impl OpenCodeError {
    pub(crate) fn protocol(message: impl Into<String>) -> Self {
        Self::Protocol(message.into())
    }
}

impl From<std::io::Error> for OpenCodeError {
    fn from(error: std::io::Error) -> Self {
        Self::Transport(error.to_string())
    }
}

impl From<crate::transport::HttpError> for OpenCodeError {
    fn from(error: crate::transport::HttpError) -> Self {
        match error {
            crate::transport::HttpError::Timeout { operation, .. } => Self::Timeout {
                operation: operation.to_owned(),
            },
            crate::transport::HttpError::Closed => Self::Closed,
            crate::transport::HttpError::Status { status, .. } => Self::Http {
                status,
                message: "HTTP transport returned an error status".into(),
            },
            other => Self::Transport(other.to_string()),
        }
    }
}

impl fmt::Display for crate::sse::SseFrame {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SSE frame {:?}", self.event)
    }
}
