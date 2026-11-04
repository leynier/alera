//! OpenCode failure classes, read only from the typed fields of a failed
//! execution's or session's `error`.

use alera_provider_protocol::FailureClass;
use serde_json::Value;

pub(crate) fn failure_class(error: &Value) -> FailureClass {
    // 2.x types a usage window, budget or rate limit as provider.quota or
    // provider.rate-limit. An empty balance is provider.quota too, but
    // answered with HTTP 402 and never resets, so it keeps OpenCode's own
    // message without a class.
    let limited = match error.get("type").and_then(Value::as_str) {
        Some("provider.rate-limit") => true,
        Some("provider.quota") => error.get("status").and_then(Value::as_u64) != Some(402),
        _ => false,
    };
    // 1.x reports a provider's HTTP 429 as an APIError.
    let rejected = error.get("name").and_then(Value::as_str) == Some("APIError")
        && error
            .get("data")
            .and_then(|data| data.get("statusCode"))
            .and_then(Value::as_u64)
            == Some(429);
    if limited || rejected {
        FailureClass::UsageLimit
    } else {
        FailureClass::Unknown
    }
}

/// The message of a native error: 2.x carries it at the top, 1.x in `data`.
pub(crate) fn error_message(error: &Value) -> Option<&str> {
    error
        .get("message")
        .or_else(|| error.get("data").and_then(|data| data.get("message")))
        .and_then(Value::as_str)
}
