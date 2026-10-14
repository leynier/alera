use alera_provider_protocol::{ProviderError, RequestId};
use serde_json::Value;

pub(crate) fn request(id: i64, method: &str, params: Value) -> Value {
    serde_json::json!({ "id": id, "method": method, "params": params })
}

pub(crate) fn notification(method: &str, params: Value) -> Value {
    serde_json::json!({ "method": method, "params": params })
}

pub(crate) fn response(id: &RequestId, result: Value) -> Value {
    serde_json::json!({ "id": request_id_value(id), "result": result })
}

pub(crate) fn request_id_value(id: &RequestId) -> Value {
    match id {
        RequestId::String(value) => Value::String(value.clone()),
        RequestId::Integer(value) => Value::Number((*value).into()),
    }
}

pub(crate) fn request_id(value: &Value) -> Result<RequestId, ProviderError> {
    match value {
        Value::String(value) => Ok(RequestId::String(value.clone())),
        Value::Number(value) => value
            .as_i64()
            .map(RequestId::Integer)
            .ok_or_else(|| ProviderError::Protocol("Codex request id must be an integer".into())),
        _ => Err(ProviderError::Protocol(
            "Codex request id must be a string or integer".into(),
        )),
    }
}

pub(crate) fn method(message: &Value) -> Option<&str> {
    message.get("method").and_then(Value::as_str)
}

pub(crate) fn params(message: &Value) -> Value {
    message.get("params").cloned().unwrap_or(Value::Null)
}

pub(crate) fn string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub(crate) fn nested_string(value: &Value, parent: &str, key: &str) -> Option<String> {
    value
        .get(parent)
        .and_then(|child| child.get(key))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub(crate) fn rpc_error(message: &Value) -> Option<ProviderError> {
    let error = message.get("error")?.as_object()?;
    let code = error.get("code").and_then(Value::as_i64).unwrap_or(-1);
    let text = error
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or("Codex app-server request failed")
        .to_owned();
    Some(ProviderError::Rpc {
        code,
        message: text,
        data: error.get("data").cloned(),
    })
}

pub(crate) fn result(message: &Value) -> Result<Value, ProviderError> {
    if let Some(error) = rpc_error(message) {
        return Err(error);
    }
    message.get("result").cloned().ok_or_else(|| {
        ProviderError::Protocol("Codex response has neither result nor error".into())
    })
}
