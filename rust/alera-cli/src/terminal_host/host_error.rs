use std::fmt;

use serde_json::Value;

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
    /// A typed, recoverable conflict. The message remains available for older
    /// clients while newer clients inspect the additive code and details.
    Conflict {
        code: String,
        message: String,
        details: Value,
    },
}

impl HostError {
    pub fn state(message: impl Into<String>) -> Self {
        HostError::State(message.into())
    }

    pub fn format(message: impl Into<String>) -> Self {
        HostError::Format(message.into())
    }

    pub fn conflict(code: impl Into<String>, message: impl Into<String>, details: Value) -> Self {
        HostError::Conflict {
            code: code.into(),
            message: message.into(),
            details,
        }
    }

    /// The string placed in the `error` field of an error response.
    pub fn wire_message(&self) -> String {
        match self {
            HostError::State(message) => message.clone(),
            HostError::Format(message) => format!("FormatException: {message}"),
            HostError::Conflict { message, .. } => message.clone(),
        }
    }

    pub fn wire_code(&self) -> Option<&str> {
        match self {
            HostError::Conflict { code, .. } => Some(code),
            _ => None,
        }
    }

    pub fn wire_details(&self) -> Option<&Value> {
        match self {
            HostError::Conflict { details, .. } => Some(details),
            _ => None,
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
