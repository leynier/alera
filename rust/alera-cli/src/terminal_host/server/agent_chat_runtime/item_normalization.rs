//! Lifts the provider-neutral fields the apps render (`normalized`) out of an
//! item's native data, and bounds what is stored per item.

use serde_json::{Map, Value};

#[path = "item_payload_projection.rs"]
mod item_payload_projection;
pub(crate) use item_payload_projection::{payload_items, project_item_data};

#[path = "item_text_budget.rs"]
mod item_text_budget;
#[cfg(test)]
pub(crate) use item_text_budget::serialized_item_bytes;
pub(crate) use item_text_budget::{
    continuation_item, continuation_item_id, segment_complete_item, stream_prefix_len,
    MAX_SEGMENT_ITEM_BYTES,
};

/// Budget for direct inline native data. Larger data uses the linked payload
/// projection and remains available through explicit paged reads.
const MAX_ITEM_DATA_BYTES: usize = 64 * 1024;

const FIELD_ALIASES: &[(&str, &[&str])] = &[
    ("command", &["command", "cmd"]),
    ("cwd", &["cwd", "workingDirectory"]),
    ("exitCode", &["exitCode", "exit_code"]),
    ("durationMs", &["durationMs", "duration_ms"]),
    ("changes", &["changes", "fileChanges"]),
    ("toolName", &["toolName", "tool", "name"]),
    ("server", &["server", "serverName"]),
    ("input", &["input", "arguments", "args", "rawInput"]),
    ("result", &["result", "rawOutput"]),
    ("query", &["query"]),
    ("url", &["url"]),
    ("imagePath", &["imagePath", "path", "savedPath"]),
    ("planSteps", &["planSteps", "plan", "steps"]),
    ("explanation", &["explanation"]),
];

pub(crate) fn normalized_fields(item_type: &str, data: &Value) -> Map<String, Value> {
    let mut normalized = Map::new();
    let Some(object) = data.as_object() else {
        return normalized;
    };
    let image = matches!(item_type, "image_view" | "image_generation");
    for (field, aliases) in FIELD_ALIASES {
        if *field == "imagePath" && !image {
            continue;
        }
        // A generated image's result is the encoded image itself; clients
        // load the saved file instead.
        if *field == "result" && item_type == "image_generation" {
            continue;
        }
        if let Some(value) = aliases
            .iter()
            .find_map(|alias| object.get(*alias))
            .filter(|value| !value.is_null())
        {
            let value = match *field {
                "command" => command_string(value),
                "planSteps" => plan_steps(value),
                _ => Some(value.clone()),
            };
            if let Some(value) = value {
                normalized.insert((*field).into(), value);
            }
        }
    }
    normalized
}

fn command_string(value: &Value) -> Option<Value> {
    match value {
        Value::String(_) => Some(value.clone()),
        Value::Array(parts) => Some(Value::String(
            parts
                .iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(" "),
        )),
        _ => None,
    }
}

fn plan_steps(value: &Value) -> Option<Value> {
    let steps = value.as_array()?;
    Some(Value::Array(
        steps
            .iter()
            .filter_map(|step| {
                let text = step
                    .get("step")
                    .or_else(|| step.get("content"))
                    .or_else(|| step.get("title"))
                    .and_then(Value::as_str)?;
                let status = match step.get("status").and_then(Value::as_str) {
                    Some("completed" | "done") => "completed",
                    Some("inProgress" | "in_progress" | "active") => "inProgress",
                    _ => "pending",
                };
                Some(serde_json::json!({"step": text, "status": status}))
            })
            .collect(),
    ))
}

/// The native data kept on the item, or `None` when it is too large to carry
/// to a phone.
pub(crate) fn bounded_data(data: Option<&Value>) -> Option<Value> {
    let data = data?;
    let size = serde_json::to_vec(data)
        .map(|bytes| bytes.len())
        .unwrap_or(usize::MAX);
    (size <= MAX_ITEM_DATA_BYTES).then(|| data.clone())
}

/// Text an item reports as a whole (a completed assistant message, say).
pub(crate) fn final_text(data: &Value) -> Option<String> {
    data.get("text")
        .and_then(Value::as_str)
        .or_else(|| data.get("message").and_then(Value::as_str))
        .map(str::to_string)
        .filter(|text| !text.is_empty())
}

pub(crate) fn final_output(data: &Value) -> Option<String> {
    data.get("aggregatedOutput")
        .or_else(|| data.get("output"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .filter(|text| !text.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn command_items_expose_command_cwd_and_exit_code() {
        let data = json!({"command": ["git", "status"], "cwd": "/w", "exitCode": 0});
        let normalized = normalized_fields("command_execution", &data);
        assert_eq!(normalized["command"], "git status");
        assert_eq!(normalized["cwd"], "/w");
        assert_eq!(normalized["exitCode"], 0);
    }

    #[test]
    fn generated_images_expose_their_saved_path_but_not_their_bytes() {
        let data = json!({"savedPath": "/codex/generated_images/a.png", "result": "aW1hZ2U="});
        let normalized = normalized_fields("image_generation", &data);
        assert_eq!(normalized["imagePath"], "/codex/generated_images/a.png");
        assert!(!normalized.contains_key("result"));
        let viewed = normalized_fields("image_view", &json!({"path": "/w/a.png"}));
        assert_eq!(viewed["imagePath"], "/w/a.png");
        let tool = normalized_fields("dynamic_tool_call", &json!({"savedPath": "/w/a.png"}));
        assert!(!tool.contains_key("imagePath"));
    }

    #[test]
    fn claude_task_lists_become_plan_steps() {
        let data = json!({"plan": [
            {"id": "1", "content": "Inspect", "status": "in_progress", "activeForm": "Inspecting"},
            {"id": "2", "content": "Fix", "status": "pending", "blockedBy": ["1"]},
            {"id": "3", "content": "Read", "status": "completed"},
        ]});
        assert_eq!(
            normalized_fields("plan", &data)["planSteps"],
            json!([
                {"step": "Inspect", "status": "inProgress"},
                {"step": "Fix", "status": "pending"},
                {"step": "Read", "status": "completed"},
            ])
        );
        assert_eq!(
            normalized_fields("plan", &json!({"plan": []}))["planSteps"],
            json!([])
        );
    }

    #[test]
    fn inline_data_budget_rejects_oversized_values() {
        let data = json!({"blob": "x".repeat(MAX_ITEM_DATA_BYTES)});
        assert!(bounded_data(Some(&data)).is_none());
        assert!(bounded_data(Some(&json!({"a": 1}))).is_some());
    }
}
