//! Muse failure classes, read only from the typed `turn/completed` error.

use alera_provider_protocol::FailureClass;
use serde_json::Value;

/// The class of a failed `turn/completed`. Muse types a used-up
/// subscription quota as `error.quota`; its message is never read.
pub(crate) fn turn_failure_class(params: &Value) -> FailureClass {
    let error = params.get("error");
    if error
        .and_then(|error| error.get("quota"))
        .is_some_and(Value::is_object)
    {
        FailureClass::UsageLimit
    } else {
        FailureClass::Unknown
    }
}
