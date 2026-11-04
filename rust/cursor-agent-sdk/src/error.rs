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
        details: Box<serde_json::Value>,
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

impl CursorSdkError {
    /// A usage, quota or rate limit stopped the call, read only from the HTTP
    /// status or the Connect code.
    pub fn is_usage_limit(&self) -> bool {
        match self {
            Self::Http { status, .. } => *status == 429,
            Self::Rpc { code, .. } => is_usage_limit_code(code),
            _ => false,
        }
    }
}

/// Whether a Connect code or a run's `errorCode` names a usage or rate limit.
/// Cursor's SDK reports codes like `PRO_USER_USAGE_LIMIT` or `RATE_LIMITED`;
/// the bridge's error taxonomy adds `USAGE_LIMIT_EXCEEDED` and
/// `RATE_LIMIT_EXCEEDED`, optionally prefixed with `SDK_ERROR_CODE_`.
pub fn is_usage_limit_code(code: &str) -> bool {
    if code.is_empty()
        || !code
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
    {
        return false;
    }
    let code = code.to_ascii_lowercase();
    let code = code.strip_prefix("sdk_error_code_").unwrap_or(&code);
    matches!(
        code,
        "resource_exhausted"
            | "rate_limited"
            | "rate_limited_changeable"
            | "usage_limit_exceeded"
            | "rate_limit_exceeded"
    ) || ["_usage_limit", "_rate_limit", "_rate_limit_exceeded"]
        .iter()
        .any(|suffix| code.ends_with(suffix))
}

impl From<alera_agent_http::HttpError> for CursorSdkError {
    fn from(error: alera_agent_http::HttpError) -> Self {
        match error {
            alera_agent_http::HttpError::Timeout { operation, timeout } => Self::Timeout {
                operation: operation.into(),
                timeout,
            },
            alera_agent_http::HttpError::Status { status, .. } => Self::Http {
                status,
                message: "bridge request failed".into(),
            },
            other => Self::Transport(other.to_string()),
        }
    }
}
