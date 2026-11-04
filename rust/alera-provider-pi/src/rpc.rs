use alera_provider_protocol::{ProviderError, RequestId};
use serde_json::{Map, Value};

pub(crate) fn request(id: &RequestId, command: &str, params: Value) -> Value {
    let mut record = Map::new();
    record.insert("type".into(), Value::String(command.to_owned()));
    record.insert("id".into(), request_id_value(id));
    if let Value::Object(fields) = params {
        record.extend(fields);
    }
    Value::Object(record)
}

pub(crate) fn fire_and_forget(
    command: &str,
    fields: impl IntoIterator<Item = (String, Value)>,
) -> Value {
    let mut record = Map::new();
    record.insert("type".into(), Value::String(command.to_owned()));
    record.extend(fields);
    Value::Object(record)
}

pub(crate) fn request_id_value(id: &RequestId) -> Value {
    match id {
        RequestId::String(value) => Value::String(value.clone()),
        RequestId::Integer(value) => Value::Number((*value).into()),
    }
}

pub(crate) fn request_id(value: &Value) -> Result<RequestId, ProviderError> {
    match value {
        Value::String(value) if !value.is_empty() => Ok(RequestId::String(value.clone())),
        Value::Number(value) => value
            .as_i64()
            .map(RequestId::Integer)
            .ok_or_else(|| ProviderError::Protocol("Pi RPC id must be an integer".into())),
        _ => Err(ProviderError::Protocol(
            "Pi RPC id must be a nonempty string or integer".into(),
        )),
    }
}

pub(crate) fn is_response(record: &Value) -> bool {
    record.get("type").and_then(Value::as_str) == Some("response")
}

pub(crate) fn response_success(record: &Value) -> Result<Value, ProviderError> {
    match record.get("success").and_then(Value::as_bool) {
        Some(true) => Ok(record.get("data").cloned().unwrap_or(Value::Null)),
        Some(false) => Err(ProviderError::Protocol(
            record
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("Pi RPC command failed")
                .to_owned(),
        )),
        None => Err(ProviderError::Protocol(
            "Pi RPC response has no boolean success field".into(),
        )),
    }
}

pub(crate) fn record_type(record: &Value) -> Option<&str> {
    record.get("type").and_then(Value::as_str)
}
