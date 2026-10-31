//! Cursor failure classes, read only from typed bridge fields: a run's
//! `errorCode`, a Connect code and an HTTP status.

use alera_provider_protocol::{FailureClass, ProviderError};
use cursor_agent_sdk::{is_usage_limit_code, CursorSdkError};
use serde_json::Value;

/// The class of a failed run result envelope.
pub(crate) fn result_class(result: &Value) -> FailureClass {
    let run_result = result.get("result").unwrap_or(result);
    let usage_limit = [result, run_result]
        .into_iter()
        .flat_map(|value| {
            [
                value.get("errorCode"),
                value.get("error_code"),
                value.get("error").and_then(|error| error.get("code")),
            ]
        })
        .flatten()
        .filter_map(Value::as_str)
        .any(is_usage_limit_code);
    if usage_limit {
        FailureClass::UsageLimit
    } else {
        FailureClass::Unknown
    }
}

pub(crate) fn sdk_error_class(error: &CursorSdkError) -> FailureClass {
    if error.is_usage_limit() {
        FailureClass::UsageLimit
    } else {
        FailureClass::Unknown
    }
}

/// A send the bridge refused; a usage limit keeps its class.
pub(crate) fn send_error(error: CursorSdkError) -> ProviderError {
    match sdk_error_class(&error) {
        FailureClass::Unknown => ProviderError::Protocol(error.to_string()),
        class => ProviderError::Rejected {
            class,
            detail: error.to_string(),
        },
    }
}
