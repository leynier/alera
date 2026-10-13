use serde_json::{Map, Value};

pub const JSONRPC: &str = "2.0";

pub fn request(id: u64, method: &str, params: Value) -> Value {
    let mut frame = Map::new();
    frame.insert("jsonrpc".into(), Value::String(JSONRPC.into()));
    frame.insert("id".into(), Value::from(id));
    frame.insert("method".into(), Value::String(method.into()));
    frame.insert("params".into(), params);
    Value::Object(frame)
}

pub fn notification(method: &str, params: Option<Value>) -> Value {
    let mut frame = Map::new();
    frame.insert("jsonrpc".into(), Value::String(JSONRPC.into()));
    frame.insert("method".into(), Value::String(method.into()));
    if let Some(params) = params {
        frame.insert("params".into(), params);
    }
    Value::Object(frame)
}

pub fn response(id: &Value, result: Value) -> Value {
    serde_json::json!({"jsonrpc": JSONRPC, "id": id, "result": result})
}

pub fn frame_id(frame: &Value) -> Option<Value> {
    frame
        .get("id")
        .filter(|id| id.is_string() || id.is_i64())
        .cloned()
}

pub fn frame_params(frame: &Value) -> Value {
    frame
        .get("params")
        .cloned()
        .unwrap_or_else(|| Value::Object(Map::new()))
}

pub fn id_key(id: &Value) -> String {
    match id {
        Value::String(value) => format!("s:{value}"),
        Value::Number(value) => format!("n:{value}"),
        _ => format!("x:{id}"),
    }
}

pub fn canonical(value: &Value) -> String {
    match value {
        Value::Null => "null".into(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => serde_json::to_string(value).unwrap_or_default(),
        Value::Array(values) => format!(
            "[{}]",
            values.iter().map(canonical).collect::<Vec<_>>().join(",")
        ),
        Value::Object(values) => {
            let mut keys = values.keys().collect::<Vec<_>>();
            keys.sort();
            format!(
                "{{{}}}",
                keys.into_iter()
                    .map(|key| format!(
                        "{}:{}",
                        serde_json::to_string(key).unwrap(),
                        canonical(&values[key])
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
    }
}
