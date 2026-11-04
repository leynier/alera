use std::fmt;
use std::time::Duration;

/// A bounded non-success response body.
///
/// The bytes are available to protocol clients that need to decode a structured
/// error, while `Debug` and `Display` never print them.
#[derive(Clone, Eq, PartialEq)]
pub struct HttpErrorBody(Vec<u8>);

impl HttpErrorBody {
    pub(crate) fn new(bytes: Vec<u8>) -> Self {
        Self(bytes)
    }

    /// Borrow the bounded response bytes for protocol-specific decoding.
    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }

    /// Consume this body and return its bounded bytes.
    pub fn into_bytes(self) -> Vec<u8> {
        self.0
    }
}

impl fmt::Debug for HttpErrorBody {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpErrorBody")
            .field("len", &self.0.len())
            .finish()
    }
}

/// Errors returned by the HTTP transport boundary.
///
/// Error messages intentionally do not include request URLs, header values, or
/// underlying reqwest diagnostics because those may contain credentials or
/// provider tokens.
#[derive(thiserror::Error)]
pub enum HttpError {
    /// The client configuration is unusable.
    #[error("invalid HTTP transport configuration: {reason}")]
    InvalidConfig { reason: &'static str },

    /// A method, URL, header name, or header value could not be represented.
    #[error("invalid HTTP {kind}")]
    InvalidInput { kind: &'static str },

    /// The request or response body exceeds the configured bound.
    #[error("HTTP {kind} exceeds the {limit}-byte limit ({observed} bytes)")]
    BodyTooLarge {
        kind: &'static str,
        limit: usize,
        observed: usize,
    },

    /// A request operation exceeded its deadline.
    #[error("HTTP {operation} timed out after {timeout:?}")]
    Timeout {
        operation: &'static str,
        timeout: Duration,
    },

    /// A request failed before a response could be produced.
    #[error("HTTP {operation} failed")]
    Request { operation: &'static str },

    /// The server returned a non-success status.
    #[error("HTTP request returned status {status}")]
    Status { status: u16, body: HttpErrorBody },

    /// A scripted mock has no response left.
    #[error("HTTP mock script is exhausted")]
    MockScriptExhausted,

    /// A byte stream was used after it was closed.
    #[error("HTTP byte stream is closed")]
    Closed,
}

impl fmt::Debug for HttpError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidConfig { reason } => formatter
                .debug_struct("InvalidConfig")
                .field("reason", reason)
                .finish(),
            Self::InvalidInput { kind } => formatter
                .debug_struct("InvalidInput")
                .field("kind", kind)
                .finish(),
            Self::BodyTooLarge {
                kind,
                limit,
                observed,
            } => formatter
                .debug_struct("BodyTooLarge")
                .field("kind", kind)
                .field("limit", limit)
                .field("observed", observed)
                .finish(),
            Self::Timeout { operation, timeout } => formatter
                .debug_struct("Timeout")
                .field("operation", operation)
                .field("timeout", timeout)
                .finish(),
            Self::Request { operation } => formatter
                .debug_struct("Request")
                .field("operation", operation)
                .finish(),
            Self::Status { status, body } => formatter
                .debug_struct("Status")
                .field("status", status)
                .field("body", body)
                .finish(),
            Self::MockScriptExhausted => formatter.write_str("MockScriptExhausted"),
            Self::Closed => formatter.write_str("Closed"),
        }
    }
}
