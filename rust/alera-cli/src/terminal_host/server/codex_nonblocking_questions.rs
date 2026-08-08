use serde_json::Value;

pub(super) fn is_nonblocking_user_input_request(message: &Value) -> bool {
    let method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    let params = message.get("params").unwrap_or(message);
    matches!(
        method.as_str(),
        "item/tool/requestuserinput" | "item/tool/request_user_input"
    ) && params.get("isBlocking").and_then(Value::as_bool) == Some(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn only_explicitly_nonblocking_user_input_requests_auto_resolve() {
        assert!(is_nonblocking_user_input_request(&json!({
            "id": 1,
            "method": "item/tool/request_user_input",
            "params": {"isBlocking": false},
        })));
        assert!(is_nonblocking_user_input_request(&json!({
            "id": 2,
            "method": "item/tool/requestUserInput",
            "params": {"isBlocking": false},
        })));
        assert!(!is_nonblocking_user_input_request(&json!({
            "id": 3,
            "method": "item/tool/request_user_input",
            "params": {"isBlocking": true},
        })));
        assert!(!is_nonblocking_user_input_request(&json!({
            "id": 4,
            "method": "item/commandExecution/requestApproval",
            "params": {"isBlocking": false},
        })));
        assert!(!is_nonblocking_user_input_request(&json!({
            "id": 5,
            "method": "item/tool/request_user_input",
            "params": {"autoResolutionMs": 1},
        })));
    }
}
