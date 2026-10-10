//! Small builders for the tools' JSON Schemas, so each catalog entry reads as a
//! list of named properties.

use serde_json::{json, Map, Value};

pub(super) fn object(properties: &[(&str, Value)], required: &[&str]) -> Value {
    let properties = properties
        .iter()
        .map(|(name, schema)| ((*name).to_owned(), schema.clone()))
        .collect::<Map<_, _>>();
    let mut schema = json!({
        "type": "object",
        "properties": properties,
        "additionalProperties": false,
    });
    if !required.is_empty() {
        schema["required"] = json!(required);
    }
    schema
}

pub(super) fn string(description: &str) -> Value {
    json!({ "type": "string", "minLength": 1, "description": description })
}

pub(super) fn text(description: &str, max_length: u64) -> Value {
    json!({
        "type": "string",
        "minLength": 1,
        "maxLength": max_length,
        "description": description,
    })
}

pub(super) fn boolean(description: &str) -> Value {
    json!({ "type": "boolean", "description": description })
}

pub(super) fn integer(description: &str, minimum: u64, maximum: u64) -> Value {
    json!({
        "type": "integer",
        "minimum": minimum,
        "maximum": maximum,
        "description": description,
    })
}

pub(super) fn one_of(description: &str, values: &[&str]) -> Value {
    json!({ "type": "string", "enum": values, "description": description })
}

pub(super) fn string_list(description: &str, values: &[&str]) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "enum": values },
        "minItems": 1,
        "uniqueItems": true,
        "description": description,
    })
}

/// `clientRequestId`: the same key on a retry returns the first call's result
/// instead of repeating its effect.
pub(super) fn client_request_id() -> Value {
    json!({
        "type": "string",
        "minLength": 8,
        "maxLength": 128,
        "description": "Optional retry key. Reuse it when retrying this call so the change happens once.",
    })
}
