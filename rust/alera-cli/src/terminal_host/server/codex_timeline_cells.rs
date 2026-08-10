//! Construction and coalescing helpers for Codex timeline cells.

use serde_json::{json, Value};

use super::codex_markdown::render_markdown;

pub(super) fn append_delta(
    cells: &mut Vec<Value>,
    turn_id: &str,
    item_id: &str,
    now: &str,
    delta: &str,
    item: &Value,
    source: &str,
) {
    if turn_id.is_empty() || delta.is_empty() {
        return;
    }
    let item_phase = first_string(&[item.get("phase")]);
    let provisional_kind = if source == "agent" {
        if item_phase.is_empty() || item_phase == "final_answer" || item_phase == "final" {
            "assistantMessage"
        } else {
            "progressText"
        }
    } else if source == "reasoning" {
        "reasoning"
    } else {
        kind_for(&first_string(&[item.get("type")]).to_lowercase(), source)
    };
    let provisional_id = if item_id.is_empty() {
        format!("{provisional_kind}-{turn_id}")
    } else {
        format!("item-{item_id}")
    };
    let provisional_existing = cell_by_id(cells, &provisional_id);
    let phase = if item_phase.is_empty() {
        first_string(&[
            provisional_existing.and_then(|value| value.pointer("/metadata/streamPhase"))
        ])
    } else {
        item_phase
    };
    let inferred_kind = if source == "agent" {
        if phase.is_empty() || phase == "final_answer" || phase == "final" {
            "assistantMessage"
        } else {
            "progressText"
        }
    } else {
        provisional_kind
    };
    let id = if item_id.is_empty() {
        format!("{inferred_kind}-{turn_id}")
    } else {
        format!("item-{item_id}")
    };
    let existing = cell_by_id(cells, &id);
    let existing_kind = existing
        .and_then(|value| value.get("kind"))
        .and_then(Value::as_str)
        .unwrap_or(inferred_kind);
    let kind = if source == "agent"
        && (phase == "final_answer" || phase == "final")
        && existing_kind == "progressText"
    {
        "assistantMessage"
    } else {
        existing_kind
    };
    if existing
        .and_then(|value| value.pointer("/metadata/lastDelta"))
        .and_then(Value::as_str)
        == Some(delta)
    {
        return;
    }
    let previous = existing
        .and_then(|value| {
            value.get(if source == "output" {
                "detailsText"
            } else {
                "markdownText"
            })
        })
        .and_then(Value::as_str)
        .unwrap_or_default();
    let mut cell = new_cell(
        &id,
        turn_id,
        kind,
        "inProgress",
        now,
        Some(if source == "reasoning" {
            "Reasoning".to_string()
        } else if source == "output" {
            title_for(&first_string(&[item.get("type")]).to_lowercase(), source)
        } else {
            "Codex".to_string()
        }),
        None,
        if source == "output" {
            None
        } else {
            Some(format!("{previous}{delta}"))
        },
        if source == "output" {
            Some(format!("{previous}{delta}"))
        } else {
            None
        },
        true,
        Some(json!({"lastDelta": delta, "streamSource": source})),
    );
    if source == "agent" {
        if let Some(map) = cell.as_object_mut() {
            if let Some(metadata) = map
                .entry("metadata")
                .or_insert_with(|| json!({}))
                .as_object_mut()
            {
                metadata.insert(
                    "streamPhase".to_string(),
                    Value::String(if kind == "assistantMessage" {
                        "final_answer".to_string()
                    } else {
                        "commentary".to_string()
                    }),
                );
            }
        }
    }
    upsert_cell(cells, cell);
}

#[allow(clippy::too_many_arguments)]
pub(super) fn new_cell(
    id: &str,
    turn_id: &str,
    kind: &str,
    status: &str,
    now: &str,
    title: Option<String>,
    subtitle: Option<String>,
    markdown: Option<String>,
    details: Option<String>,
    streaming: bool,
    metadata: Option<Value>,
) -> Value {
    json!({
        "id": id,
        "turnId": if turn_id.is_empty() { Value::Null } else { Value::String(turn_id.to_string()) },
        "kind": kind,
        "status": status,
        "createdAt": now,
        "updatedAt": now,
        "isStreaming": streaming,
        "isCollapsed": false,
        "title": title,
        "subtitle": subtitle,
        "markdownText": markdown,
        "renderedMarkdownText": markdown.as_deref().map(render_markdown),
        "detailsText": details,
        "metadata": metadata.unwrap_or_else(|| json!({})),
    })
}

pub(super) fn upsert_cell(cells: &mut Vec<Value>, next: Value) {
    let Some(id) = next.get("id").and_then(Value::as_str) else {
        return;
    };
    let Some(index) = cells
        .iter()
        .position(|cell| cell.get("id").and_then(Value::as_str) == Some(id))
    else {
        cells.push(next);
        return;
    };
    let Some(existing) = cells[index].as_object_mut() else {
        return;
    };
    let Some(next_map) = next.as_object() else {
        return;
    };
    for key in [
        "turnId",
        "kind",
        "status",
        "updatedAt",
        "isStreaming",
        "title",
        "subtitle",
        "markdownText",
        "renderedMarkdownText",
        "detailsText",
    ] {
        if let Some(value) = next_map.get(key).filter(|value| !value.is_null()) {
            existing.insert(key.to_string(), value.clone());
        }
    }
    let mut metadata = existing
        .remove("metadata")
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default();
    if let Some(incoming) = next_map.get("metadata").and_then(Value::as_object) {
        metadata.extend(incoming.clone());
    }
    existing.insert("metadata".to_string(), Value::Object(metadata));
}

pub(super) fn complete_context_compaction(cells: &mut Vec<Value>, turn_id: &str, now: &str) {
    if let Some(cell) = cells.iter_mut().rev().find(|cell| {
        cell.get("turnId").and_then(Value::as_str) == Some(turn_id)
            && cell
                .pointer("/metadata/itemType")
                .and_then(Value::as_str)
                .is_some_and(|item_type| item_type.eq_ignore_ascii_case("contextCompaction"))
    }) {
        if let Some(map) = cell.as_object_mut() {
            map.insert("title".to_string(), Value::String("Compacted".to_string()));
            map.insert("status".to_string(), Value::String("completed".to_string()));
            map.insert("isStreaming".to_string(), Value::Bool(false));
            map.insert("updatedAt".to_string(), Value::String(now.to_string()));
        }
        return;
    }
    upsert_cell(
        cells,
        new_cell(
            &format!("compaction-{turn_id}"),
            turn_id,
            "toolCall",
            "completed",
            now,
            Some("Compacted".to_string()),
            None,
            None,
            None,
            false,
            Some(json!({"itemType": "contextCompaction"})),
        ),
    );
}

pub(super) fn cell_by_id<'a>(cells: &'a [Value], id: &str) -> Option<&'a Value> {
    cells
        .iter()
        .find(|cell| cell.get("id").and_then(Value::as_str) == Some(id))
}

pub(super) fn kind_for(item_type: &str, method: &str) -> &'static str {
    if item_type.contains("usermessage") || item_type.contains("user_message") {
        "userMessage"
    } else if item_type.contains("agentmessage") || item_type.contains("assistant") {
        "assistantMessage"
    } else if item_type.contains("reason") {
        "reasoning"
    } else if item_type.contains("filechange")
        || item_type.contains("diff")
        || method.contains("filechange")
    {
        "diff"
    } else if item_type.contains("command") || method.contains("commandexecution") {
        "command"
    } else if item_type.contains("subagent")
        || item_type.contains("collab")
        || method.contains("subagent")
        || method.contains("collab")
    {
        "subAgent"
    } else if item_type.contains("plan") || method.contains("/plan") {
        "plan"
    } else if item_type.contains("websearch")
        || item_type.contains("dynamictool")
        || item_type.contains("imageview")
        || item_type.contains("imagegeneration")
        || item_type.contains("sleep")
        || item_type.contains("contextcompaction")
        || item_type.contains("enteredreview")
        || item_type.contains("exitedreview")
        || item_type.contains("extension")
        || item_type.contains("tool")
        || method.contains("tool")
        || method == "output"
    {
        "toolCall"
    } else {
        "progressText"
    }
}

pub(super) fn title_for(item_type: &str, method: &str) -> String {
    if item_type.contains("command") || method.contains("commandexecution") {
        return "Command".to_string();
    }
    if item_type.contains("filechange") || method.contains("filechange") {
        return "File changes".to_string();
    }
    if item_type.contains("reason") {
        return "Reasoning".to_string();
    }
    if item_type.contains("plan") || method.contains("/plan") {
        return "Plan".to_string();
    }
    if item_type.contains("subagent")
        || item_type.contains("collab")
        || method.contains("subagent")
        || method.contains("collab")
    {
        return "Sub-agent".to_string();
    }
    if item_type.contains("websearch") {
        return "Web search".to_string();
    }
    if item_type.contains("imageview") {
        return "Viewed image".to_string();
    }
    if item_type.contains("imagegeneration") {
        return "Generated image".to_string();
    }
    if item_type.contains("contextcompaction") {
        return if method.contains("completed") {
            "Compacted".to_string()
        } else {
            "Compacting".to_string()
        };
    }
    if item_type.contains("enteredreview") {
        return "Entered review mode".to_string();
    }
    if item_type.contains("exitedreview") {
        return "Exited review mode".to_string();
    }
    if item_type.contains("tool") || method.contains("tool") {
        return "Tool call".to_string();
    }
    "Codex activity".to_string()
}

pub(super) fn first_string(values: &[Option<&Value>]) -> String {
    values
        .iter()
        .filter_map(|value| value.and_then(Value::as_str))
        .map(str::trim)
        .find(|value| !value.is_empty())
        .unwrap_or_default()
        .to_string()
}

pub(super) fn first_delta(values: &[Option<&Value>]) -> String {
    values
        .iter()
        .filter_map(|value| value.and_then(Value::as_str))
        .find(|value| !value.is_empty())
        .unwrap_or_default()
        .to_string()
}

pub(super) fn is_agent_delta(method: &str) -> bool {
    method == "item/agentMessage/delta"
        || (method.contains("agentmessage") && method.contains("delta"))
}

pub(super) fn is_reasoning_delta(method: &str) -> bool {
    method == "item/reasoning/summaryTextDelta"
        || method == "item/reasoning/textDelta"
        || (method.contains("reasoning") && method.contains("delta"))
}

pub(super) fn is_output_delta(method: &str) -> bool {
    matches!(
        method,
        "item/commandExecution/outputDelta"
            | "item/fileChange/outputDelta"
            | "item/mcpToolCall/outputDelta"
            | "item/webSearch/outputDelta"
            | "item/plan/delta"
            | "item/commandExecution/terminalInteraction"
            | "item/mcpToolCall/progress"
    ) || method.contains("outputdelta")
}
