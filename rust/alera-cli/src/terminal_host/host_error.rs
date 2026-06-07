use std::fmt;

/// Errors surfaced to clients over the wire. [`HostError::State`] renders its
/// message as-is because some client recovery paths pattern-match exact text,
/// and [`HostError::Format`] renders like Dart's `FormatException`.
#[derive(Debug, Clone)]
pub enum HostError {
    /// The message is sent verbatim. Some of these strings are pattern-matched
    /// by the app client, so keep them exact.
    State(String),
    /// Equivalent to Dart's `FormatException`; rendered as `FormatException: <msg>`.
    Format(String),
}

impl HostError {
    pub fn state(message: impl Into<String>) -> Self {
        HostError::State(message.into())
    }

    pub fn format(message: impl Into<String>) -> Self {
        HostError::Format(message.into())
    }

    /// The string placed in the `error` field of an error response.
    pub fn wire_message(&self) -> String {
        match self {
            HostError::State(message) => message.clone(),
            HostError::Format(message) => format!("FormatException: {message}"),
        }
    }
}

impl fmt::Display for HostError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.wire_message())
    }
}

impl std::error::Error for HostError {}

pub type HostResult<T> = Result<T, HostError>;
