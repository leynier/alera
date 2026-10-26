//! Runtime-allocated identities, timestamps and receipt scopes.

use serde_json::Value;

pub(crate) fn new_id(prefix: &str) -> String {
    format!("{prefix}_{}", uuid::Uuid::new_v4().simple())
}

pub(crate) fn now() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

/// A short token naming one provider process of a chat.
pub(crate) fn process_epoch() -> String {
    uuid::Uuid::new_v4().simple().to_string()[..12].to_string()
}

/// Key under which a native id is mapped in memory: the JSON text keeps `7`
/// and `"7"` distinct.
pub(crate) fn native_key(kind: &str, native: &Value) -> (String, String) {
    (kind.to_string(), native.to_string())
}

/// The store keys receipts by `(callerScope, requestId)`. Folding the verb
/// into the scope as a JSON pair keeps one requestId reused across verbs
/// independent, and cannot collide the way a joined string could.
pub(crate) fn receipt_scope(caller_scope: &str, verb: &str) -> String {
    serde_json::to_string(&(caller_scope, verb)).expect("a string pair serializes")
}

/// The digest of a command payload without its idempotency key.
pub(crate) fn payload_digest(payload: &Value) -> String {
    let mut payload = payload.clone();
    if let Some(object) = payload.as_object_mut() {
        object.remove("requestId");
    }
    alera_core::runtime::agent_chat_command_digest(&payload)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn digest_ignores_key_order_and_the_request_id() {
        let a = payload_digest(&json!({"requestId": "1", "b": 1, "a": {"y": 2, "x": 1}}));
        let b = payload_digest(&json!({"a": {"x": 1, "y": 2}, "b": 1, "requestId": "2"}));
        assert_eq!(a, b);
        assert_ne!(a, payload_digest(&json!({"a": {"x": 1, "y": 2}, "b": 2})));
    }

    #[test]
    fn receipt_scopes_are_unambiguous() {
        assert_ne!(receipt_scope("a:b", "c"), receipt_scope("a", "b:c"));
        assert_ne!(
            native_key("request", &json!(7)),
            native_key("request", &json!("7"))
        );
    }
}
