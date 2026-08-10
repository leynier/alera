//! Presentation metadata retained for structured timeline tool details.

use serde_json::{json, Map, Value};

use super::codex_timeline_content::item_details_source;

const MAX_TOOL_METADATA_BYTES: usize = 192 * 1024;
const MAX_TOOL_METADATA_FIELD_BYTES: usize = 64 * 1024;
const MAX_TOOL_STRING_BYTES: usize = 8 * 1024;
const MAX_TOOL_COLLECTION_ITEMS: usize = 32;
const MAX_TOOL_VALUE_DEPTH: usize = 8;
const MAX_TOOL_VALUE_NODES: usize = 128;

pub(super) fn item_timeline_metadata(item: &Value, stream_phase: Option<&str>) -> Value {
    let mut metadata = Map::new();
    let mut remaining_bytes = MAX_TOOL_METADATA_BYTES;
    for (key, value) in [
        ("itemType", item.get("type")),
        ("type", item.get("type")),
        ("durationMs", item.get("durationMs")),
        ("status", item.get("status")),
        ("server", item.get("server")),
        ("tool", item.get("tool")),
        ("namespace", item.get("namespace")),
        ("appContext", item.get("appContext")),
        ("pluginId", item.get("pluginId")),
        ("readOnlyHint", item.get("readOnlyHint")),
        ("success", item.get("success")),
        ("path", item.get("path")),
        ("revisedPrompt", item.get("revisedPrompt")),
        ("savedPath", item.get("savedPath")),
    ] {
        insert_bounded_value(&mut metadata, key, value, &mut remaining_bytes);
    }
    if let Some(source) = item_details_source(item) {
        insert_bounded_value(
            &mut metadata,
            "detailsSource",
            Some(&Value::String(source.to_string())),
            &mut remaining_bytes,
        );
    }
    if let Some(phase) = stream_phase {
        insert_bounded_value(
            &mut metadata,
            "streamPhase",
            Some(&Value::String(phase.to_string())),
            &mut remaining_bytes,
        );
    }
    let changes_count = item
        .get("changes")
        .and_then(Value::as_array)
        .map(|changes| json!(changes.len()));
    insert_bounded_value(
        &mut metadata,
        "changesCount",
        changes_count.as_ref(),
        &mut remaining_bytes,
    );
    for key in [
        "query",
        "url",
        "action",
        "results",
        "changes",
        "arguments",
        "result",
        "error",
        "contentItems",
        "commandActions",
    ] {
        insert_bounded_value(&mut metadata, key, item.get(key), &mut remaining_bytes);
    }
    for key in ["aggregatedOutput", "output", "diff", "commandOutput"] {
        insert_bounded_value(
            &mut metadata,
            key,
            item.get(key).filter(|value| !value.is_string()),
            &mut remaining_bytes,
        );
    }
    Value::Object(metadata)
}

fn insert_bounded_value(
    metadata: &mut Map<String, Value>,
    key: &str,
    value: Option<&Value>,
    remaining_bytes: &mut usize,
) {
    let Some(value) = value.filter(|value| !value.is_null()) else {
        return;
    };
    let mut remaining_nodes = MAX_TOOL_VALUE_NODES;
    let bounded = bounded_tool_value(value, 0, &mut remaining_nodes);
    let encoded_bytes = serde_json::to_vec(&bounded).map_or(usize::MAX, |bytes| bytes.len());
    let bounded = if encoded_bytes > MAX_TOOL_METADATA_FIELD_BYTES {
        truncated_value("Structured tool content exceeded the field size limit.")
    } else {
        bounded
    };
    let encoded_bytes = serde_json::to_vec(&bounded).map_or(usize::MAX, |bytes| bytes.len());
    if encoded_bytes > *remaining_bytes {
        let summary = truncated_value("Structured tool content exceeded the metadata size limit.");
        let summary_bytes = serde_json::to_vec(&summary).map_or(usize::MAX, |bytes| bytes.len());
        if summary_bytes > *remaining_bytes {
            return;
        }
        *remaining_bytes -= summary_bytes;
        metadata.insert(key.to_string(), summary);
        return;
    }
    *remaining_bytes -= encoded_bytes;
    metadata.insert(key.to_string(), bounded);
}

fn bounded_tool_value(value: &Value, depth: usize, remaining_nodes: &mut usize) -> Value {
    if *remaining_nodes == 0 {
        return truncated_value("Additional structured tool content was omitted.");
    }
    *remaining_nodes -= 1;
    if depth >= MAX_TOOL_VALUE_DEPTH && (value.is_array() || value.is_object()) {
        return truncated_value("Nested structured tool content exceeded the depth limit.");
    }
    match value {
        Value::String(value) => Value::String(bounded_string(value)),
        Value::Array(values) => {
            let mut bounded = values
                .iter()
                .take(MAX_TOOL_COLLECTION_ITEMS)
                .map(|value| bounded_tool_value(value, depth + 1, remaining_nodes))
                .collect::<Vec<_>>();
            if values.len() > bounded.len() {
                bounded.push(truncated_value("Additional list items were omitted."));
            }
            Value::Array(bounded)
        }
        Value::Object(values) => {
            if let Some(summary) = embedded_media_summary(values) {
                return summary;
            }
            let mut bounded = Map::new();
            for (key, value) in values.iter().take(MAX_TOOL_COLLECTION_ITEMS) {
                bounded.insert(
                    key.clone(),
                    bounded_tool_value(value, depth + 1, remaining_nodes),
                );
            }
            if values.len() > bounded.len() {
                bounded.insert(
                    "_aleraTruncated".to_string(),
                    Value::String("Additional object fields were omitted.".to_string()),
                );
            }
            Value::Object(bounded)
        }
        _ => value.clone(),
    }
}

fn bounded_string(value: &str) -> String {
    if value.len() <= MAX_TOOL_STRING_BYTES {
        return value.to_string();
    }
    let mut end = MAX_TOOL_STRING_BYTES.min(value.len());
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    format!(
        "{}\n[{} additional bytes omitted]",
        &value[..end],
        value.len() - end
    )
}

fn embedded_media_summary(value: &Map<String, Value>) -> Option<Value> {
    let item_type = value
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let mime_type = value
        .get("mimeType")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let kind = if item_type.eq_ignore_ascii_case("image")
        || item_type.eq_ignore_ascii_case("inputImage")
        || mime_type.starts_with("image/")
    {
        "image"
    } else if item_type.eq_ignore_ascii_case("audio")
        || item_type.eq_ignore_ascii_case("inputAudio")
        || mime_type.starts_with("audio/")
    {
        "audio"
    } else {
        return None;
    };
    let source = value
        .get("data")
        .or_else(|| value.get("blob"))
        .or_else(|| value.get("imageUrl"))
        .or_else(|| value.get("audioUrl"))
        .and_then(Value::as_str)?;
    if !value.contains_key("data") && !value.contains_key("blob") && !source.starts_with("data:") {
        return None;
    }
    let encoded = source
        .split_once(',')
        .map_or(source, |(_, encoded)| encoded)
        .trim_end_matches([' ', '\t', '\n', '\r']);
    let padding = encoded
        .chars()
        .rev()
        .take_while(|character| *character == '=')
        .count();
    let byte_length = encoded.len().saturating_mul(3) / 4;
    Some(json!({
        "type": kind,
        "mimeType": if mime_type.is_empty() { format!("{kind}/*") } else { mime_type.to_string() },
        "byteLength": byte_length.saturating_sub(padding.min(2)),
        "truncated": true,
    }))
}

fn truncated_value(message: &str) -> Value {
    json!({"truncated": true, "message": message})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_original_change_count_when_the_visible_list_is_bounded() {
        let changes = (0..40)
            .map(|index| {
                json!({
                    "path": format!("lib/file_{index}.dart"),
                    "kind": "update",
                    "diff": "+updated"
                })
            })
            .collect::<Vec<_>>();
        let metadata =
            item_timeline_metadata(&json!({"type": "fileChange", "changes": changes}), None);

        assert_eq!(metadata["changesCount"], 40);
        assert_eq!(metadata["changes"].as_array().map(Vec::len), Some(33));
        assert_eq!(metadata["changes"][32]["truncated"], true);
    }
}
