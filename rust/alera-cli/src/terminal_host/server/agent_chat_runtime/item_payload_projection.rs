//! Bounded visible metadata with one retrievable, redacted full payload.

use serde_json::{Map, Value};

use super::super::wire::{ChatItem, STREAM_TEXT};
use super::item_text_budget::json_text_prefix_len;
use super::{bounded_data, normalized_fields, stream_prefix_len};

const NORMALIZED_FIELD_MAX_BYTES: usize = 768;
const NORMALIZED_MAX_BYTES: usize = 96 * 1024;

pub(crate) struct ProjectedItemData {
    pub normalized: Map<String, Value>,
    pub data: Option<Value>,
    pub payload: Option<String>,
}

fn sensitive_key(key: &str) -> bool {
    let folded: String = key
        .chars()
        .filter(|ch| *ch != '_' && *ch != '-')
        .flat_map(char::to_lowercase)
        .collect();
    matches!(
        folded.as_str(),
        "authorization"
            | "bearer"
            | "bearertoken"
            | "accesstoken"
            | "refreshtoken"
            | "idtoken"
            | "apikey"
            | "secret"
            | "clientsecret"
            | "password"
            | "credentials"
            | "mcpservers"
            | "env"
            | "environment"
            | "environmentvariables"
            | "mcpconfig"
            | "mcpconfiguration"
    )
}

fn redacted_value(value: &Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.iter()
                .filter(|(key, _)| !sensitive_key(key))
                .map(|(key, value)| (key.clone(), redacted_value(value)))
                .collect(),
        ),
        Value::Array(values) => Value::Array(values.iter().map(redacted_value).collect()),
        Value::String(text)
            if text.trim_start().starts_with('{') || text.trim_start().starts_with('[') =>
        {
            // Raw tool arguments may themselves be JSON encoded strings.
            // Check their keys before placing that JSON in a text row.
            if let Ok(parsed @ (Value::Object(_) | Value::Array(_))) =
                serde_json::from_str::<Value>(text)
            {
                let redacted = redacted_value(&parsed);
                if redacted != parsed {
                    return Value::String(redacted.to_string());
                }
            }
            value.clone()
        }
        _ => value.clone(),
    }
}

fn preview(value: &Value) -> Value {
    let text = value.to_string();
    let take = json_text_prefix_len(&text, NORMALIZED_FIELD_MAX_BYTES - 5);
    Value::String(format!("{}…", &text[..take]))
}

/// Excluded fields are strings the caller has already retained in their
/// canonical text/reasoning/output streams, so native data need not repeat them.
pub(crate) fn project_item_data(
    item_type: &str,
    data: &Value,
    canonical_fields: &[&str],
) -> ProjectedItemData {
    let mut retained = redacted_value(data);
    if let Some(object) = retained.as_object_mut() {
        for field in canonical_fields {
            if object.get(*field).is_some_and(Value::is_string) {
                object.remove(*field);
            }
        }
    }
    let mut normalized = normalized_fields(item_type, &retained);
    let mut has_preview = false;
    if serde_json::to_vec(&normalized).map_or(true, |bytes| bytes.len() > NORMALIZED_MAX_BYTES) {
        for value in normalized.values_mut() {
            if value.to_string().len() > NORMALIZED_FIELD_MAX_BYTES {
                *value = preview(value);
                has_preview = true;
            }
        }
    }
    let native_data = bounded_data(Some(&retained));
    if has_preview && native_data.is_some() {
        normalized.insert(
            "payloadRef".into(),
            serde_json::json!({"field":"data", "format":"json"}),
        );
    }
    let payload = native_data.is_none().then(|| retained.to_string());
    ProjectedItemData {
        normalized,
        data: native_data,
        payload,
    }
}

pub(crate) fn payload_items(head: &ChatItem, payload: &str) -> Result<Vec<ChatItem>, String> {
    let mut remaining = payload;
    let mut items = Vec::new();
    let mut index = 1;
    while !remaining.is_empty() {
        let mut item = ChatItem::new(
            format!("{}:payload:{index}", head.item_id),
            "payload",
            &head.created_at,
            head.generation,
        );
        item.turn_id = head.turn_id.clone();
        item.status = head.status.clone();
        item.updated_at = head.updated_at.clone();
        item.actor = head.actor.clone();
        item.normalized.insert("hidden".into(), Value::Bool(true));
        item.normalized
            .insert("payloadOf".into(), Value::String(head.item_id.clone()));
        item.normalized
            .insert("payloadIndex".into(), Value::from(index as u64));
        item.normalized
            .insert("format".into(), Value::String("json".into()));
        let take = stream_prefix_len(&item, STREAM_TEXT, remaining)?;
        if take == 0 {
            return Err(format!(
                "Item {} payload metadata exceeds the store row budget.",
                item.item_id
            ));
        }
        item.text = Some(remaining[..take].to_string());
        remaining = &remaining[take..];
        items.push(item);
        index += 1;
    }
    Ok(items)
}

#[cfg(test)]
#[path = "item_payload_projection_tests.rs"]
mod tests;
