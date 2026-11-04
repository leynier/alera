//! Codex failure classes, read only from the typed `codexErrorInfo`.

use alera_provider_protocol::FailureClass;
use serde_json::Value;

pub(crate) fn failure_class(error_info: &Value) -> FailureClass {
    match error_info {
        Value::String(code) => match code.as_str() {
            "usageLimitExceeded" | "rateLimitExceeded" => FailureClass::UsageLimit,
            "contextWindowExceeded" => FailureClass::ContextWindowFull,
            "unauthorized" => FailureClass::Auth,
            _ => FailureClass::Unknown,
        },
        // Retry exhaustion says why only through the last attempt's HTTP
        // status. Giving up on 429 is a usage or rate limit; other statuses
        // stay provider or transport errors.
        Value::Object(info)
            if info
                .get("responseTooManyFailedAttempts")
                .and_then(|attempts| attempts.get("httpStatusCode"))
                .and_then(Value::as_u64)
                == Some(429) =>
        {
            FailureClass::UsageLimit
        }
        _ => FailureClass::Unknown,
    }
}

/// The `codexErrorInfo` of an `error` notification or a failed turn.
pub(crate) fn error_info(params: &Value) -> Option<&Value> {
    params
        .get("turn")
        .and_then(|turn| turn.get("error"))
        .or_else(|| params.get("error"))
        .and_then(|error| error.get("codexErrorInfo"))
        .filter(|info| !info.is_null())
}
