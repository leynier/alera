use std::fmt;

use serde_json::{json, Value};

/// Why an issue could not be read. Absence (`NotFound`) is kept apart from
/// tooling and transport problems so callers never confuse the two.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IssueFetchError {
    InvalidUrl(String),
    Unsupported(String),
    CliMissing { cli: String, hint: String },
    NotAuthenticated { cli: String, hint: String },
    NotFound(String),
    Failed(String),
}

impl IssueFetchError {
    pub fn code(&self) -> &'static str {
        match self {
            IssueFetchError::InvalidUrl(_) => "invalidUrl",
            IssueFetchError::Unsupported(_) => "unsupported",
            IssueFetchError::CliMissing { .. } => "cliMissing",
            IssueFetchError::NotAuthenticated { .. } => "notAuthenticated",
            IssueFetchError::NotFound(_) => "notFound",
            IssueFetchError::Failed(_) => "failed",
        }
    }

    pub fn to_json(&self) -> Value {
        json!({ "code": self.code(), "message": self.to_string() })
    }
}

impl fmt::Display for IssueFetchError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            IssueFetchError::InvalidUrl(message)
            | IssueFetchError::Unsupported(message)
            | IssueFetchError::NotFound(message)
            | IssueFetchError::Failed(message) => formatter.write_str(message),
            IssueFetchError::CliMissing { cli, hint } => {
                write!(formatter, "{cli} is not available. {hint}")
            }
            IssueFetchError::NotAuthenticated { cli, hint } => {
                write!(formatter, "{cli} is not authenticated. {hint}")
            }
        }
    }
}

impl std::error::Error for IssueFetchError {}
