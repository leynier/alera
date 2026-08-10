//! Streaming Codex events reduced into stable timeline cells.

use chrono::Utc;
use serde_json::{json, Value};

use super::{
    codex_timeline_cells::{
        append_delta, cell_by_id, first_delta, first_string, is_agent_delta, is_output_delta,
        is_reasoning_delta, kind_for, new_cell, title_for, upsert_cell,
    },
    codex_timeline_content::{item_details, item_markdown, update_turn_separator_metrics},
    trim_cells, turn_id_from_message,
};

pub(super) fn reduce_timeline(snapshot: &mut Value, message: &Value) {
    let Some(object) = snapshot.as_object_mut() else {
        return;
    };
    let mut cells = object
        .remove("timelineCells")
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default();
    let raw_method = message
        .get("method")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let method = match raw_method {
        "codex/event/item_started" => "item/started",
        "codex/event/item_completed" => "item/completed",
        "codex/event/task_complete" => "turn/completed",
        "codex/event/token_count" => "token_count",
        other => other,
    };
    let params = message.get("params").cloned().unwrap_or(Value::Null);
    let legacy_msg = params.get("msg").cloned().unwrap_or(Value::Null);
    let legacy_turn_id = first_string(&[legacy_msg.get("turn_id"), legacy_msg.get("turnId")]);
    let turn_id = turn_id_from_message(message)
        .or_else(|| (!legacy_turn_id.is_empty()).then_some(legacy_turn_id))
        .unwrap_or_default();
    let item = params
        .get("item")
        .or_else(|| legacy_msg.get("item"))
        .cloned()
        .unwrap_or(Value::Null);
    let item_id = first_string(&[
        params.get("itemId"),
        params.get("item_id"),
        item.get("id"),
        params.get("id"),
    ]);
    let item_type = first_string(&[item.get("type"), params.get("type")]).to_lowercase();
    let lower = method.to_lowercase();
    let now = Utc::now().to_rfc3339();

    if super::codex_timeline_modern::reduce_modern_notification(
        &mut cells, method, &params, &turn_id, &item_id, &now,
    ) {
        trim_cells(&mut cells);
        object.insert("timelineCells".to_string(), Value::Array(cells));
        return;
    }

    if raw_method == "codex/event/task_complete" {
        let text = first_string(&[
            legacy_msg.get("last_agent_message"),
            legacy_msg.get("lastAgentMessage"),
        ]);
        if !text.is_empty() && !turn_id.is_empty() {
            upsert_cell(
                &mut cells,
                new_cell(
                    &format!("assistant-{turn_id}"),
                    &turn_id,
                    "assistantMessage",
                    "completed",
                    &now,
                    Some("Codex".to_string()),
                    None,
                    Some(text),
                    None,
                    false,
                    None,
                ),
            );
        }
        for cell in &mut cells {
            if cell.get("turnId").and_then(Value::as_str) == Some(turn_id.as_str())
                && cell.get("isStreaming").and_then(Value::as_bool) == Some(true)
            {
                if let Some(map) = cell.as_object_mut() {
                    map.insert("status".to_string(), Value::String("completed".to_string()));
                    map.insert("isStreaming".to_string(), Value::Bool(false));
                    map.insert("updatedAt".to_string(), Value::String(now.clone()));
                }
            }
        }
        update_turn_separator_metrics(&mut cells, &turn_id, &params, &now);
    } else if matches!(method, "turn/started" | "turn/created") && !turn_id.is_empty() {
        let turn = params.get("turn").unwrap_or(&Value::Null);
        upsert_cell(
            &mut cells,
            new_cell(
                &format!("turn-{turn_id}"),
                &turn_id,
                "turnSeparator",
                "info",
                &now,
                Some("Turn started".to_string()),
                None,
                None,
                None,
                false,
                Some(json!({
                    "startedAt": turn.get("startedAt"),
                    "completedAt": turn.get("completedAt"),
                    "computedDurationMs": turn.get("durationMs"),
                })),
            ),
        );
    } else if matches!(
        method,
        "turn/completed" | "turn/failed" | "turn/aborted" | "turn/interrupted"
    ) {
        let status = if method == "turn/failed" {
            "failed"
        } else {
            "completed"
        };
        for cell in &mut cells {
            if cell.get("turnId").and_then(Value::as_str) == Some(turn_id.as_str())
                && cell.get("isStreaming").and_then(Value::as_bool) == Some(true)
            {
                if let Some(map) = cell.as_object_mut() {
                    map.insert("status".to_string(), Value::String(status.to_string()));
                    map.insert("isStreaming".to_string(), Value::Bool(false));
                    map.insert("updatedAt".to_string(), Value::String(now.clone()));
                }
            }
        }
        update_turn_separator_metrics(&mut cells, &turn_id, &params, &now);
    } else if method == "turn/diff/updated" && !turn_id.is_empty() {
        let has_snapshot = params.get("diff").is_some()
            || params.get("delta").is_some()
            || params.get("text").is_some();
        let diff = first_delta(&[params.get("diff"), params.get("delta"), params.get("text")]);
        if has_snapshot {
            let id = format!("diff-{turn_id}");
            if cell_by_id(&cells, &id)
                .and_then(|cell| cell.pointer("/metadata/lastDelta"))
                .and_then(Value::as_str)
                == Some(diff.as_str())
            {
                trim_cells(&mut cells);
                object.insert("timelineCells".to_string(), Value::Array(cells));
                return;
            }
            upsert_cell(
                &mut cells,
                new_cell(
                    &id,
                    &turn_id,
                    "diff",
                    "inProgress",
                    &now,
                    Some("File changes".to_string()),
                    None,
                    None,
                    Some(diff.clone()),
                    true,
                    Some(json!({"lastDelta": diff})),
                ),
            );
        }
    } else if is_agent_delta(method) {
        append_delta(
            &mut cells,
            &turn_id,
            &item_id,
            &now,
            &first_delta(&[
                params.get("delta"),
                params.get("text"),
                legacy_msg.get("delta"),
                legacy_msg.get("text"),
                legacy_msg.get("message"),
            ]),
            &item,
            "agent",
        );
    } else if is_reasoning_delta(method) {
        append_delta(
            &mut cells,
            &turn_id,
            &item_id,
            &now,
            &first_delta(&[
                params.get("delta"),
                params.get("text"),
                legacy_msg.get("delta"),
                legacy_msg.get("text"),
            ]),
            &item,
            "reasoning",
        );
    } else if is_output_delta(method) {
        let mut output_item = if item.is_object() {
            item.clone()
        } else {
            json!({})
        };
        if let Some(map) = output_item.as_object_mut() {
            if !map.contains_key("type") {
                map.insert("type".to_string(), Value::String(lower.clone()));
            }
        }
        append_delta(
            &mut cells,
            &turn_id,
            &item_id,
            &now,
            &first_delta(&[
                params.get("delta"),
                params.get("text"),
                params.get("output"),
                params.get("interaction"),
                legacy_msg.get("delta"),
                legacy_msg.get("text"),
            ]),
            &output_item,
            "output",
        );
    } else if (lower.contains("subagent") || lower.contains("collab")) && !turn_id.is_empty() {
        let text = first_delta(&[
            params.get("delta"),
            params.get("text"),
            params.get("summary"),
            params.get("message"),
            legacy_msg.get("summary"),
            legacy_msg.get("message"),
        ]);
        let id = if item_id.is_empty() {
            format!("subAgent-{turn_id}")
        } else {
            format!("item-{item_id}")
        };
        if cell_by_id(&cells, &id)
            .and_then(|cell| cell.pointer("/metadata/lastDelta"))
            .and_then(Value::as_str)
            == Some(text.as_str())
        {
            trim_cells(&mut cells);
            object.insert("timelineCells".to_string(), Value::Array(cells));
            return;
        }
        let previous = cell_by_id(&cells, &id)
            .and_then(|cell| cell.get("markdownText"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        upsert_cell(
            &mut cells,
            new_cell(
                &id,
                &turn_id,
                "subAgent",
                if lower.contains("completed") || lower.contains("end") {
                    "completed"
                } else {
                    "inProgress"
                },
                &now,
                Some("Sub-agent".to_string()),
                None,
                if text.is_empty() {
                    None
                } else {
                    Some(format!("{previous}{text}"))
                },
                None,
                !lower.contains("completed") && !lower.contains("end"),
                Some(json!({"lastDelta": text})),
            ),
        );
    } else if matches!(method, "item/started" | "item/completed" | "item/updated")
        && !turn_id.is_empty()
    {
        let base_kind = kind_for(&item_type, &lower);
        let id = if base_kind == "userMessage" {
            let client_id = first_string(&[item.get("clientId"), item.get("client_id")]);
            if client_id.is_empty() {
                format!("user-{turn_id}")
            } else {
                format!("user-{client_id}")
            }
        } else if item_id.is_empty() {
            format!("{}-{turn_id}", base_kind)
        } else {
            format!("item-{item_id}")
        };
        let existing = cell_by_id(&cells, &id);
        let phase = first_string(&[
            item.get("phase"),
            params.get("phase"),
            existing.and_then(|cell| cell.pointer("/metadata/streamPhase")),
        ]);
        let is_agent_message =
            item_type.contains("agentmessage") || item_type.contains("assistant");
        let kind = if is_agent_message && phase == "commentary" {
            "progressText"
        } else {
            base_kind
        };
        let status_raw = first_string(&[item.get("status"), params.get("status")]).to_lowercase();
        let status = if status_raw.contains("fail") {
            "failed"
        } else if status_raw.contains("declin") {
            "declined"
        } else if method == "item/completed" {
            "completed"
        } else {
            "inProgress"
        };
        let presentation_owned_text = base_kind == "userMessage"
            && existing.is_some_and(|cell| {
                cell.pointer("/metadata/clientUserMessageId").is_some()
                    || cell
                        .pointer("/metadata/attachments")
                        .and_then(Value::as_array)
                        .is_some()
            });
        let text = if presentation_owned_text {
            existing
                .and_then(|cell| cell.get("markdownText"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string()
        } else {
            item_markdown(&item)
        };
        let details = item_details(&item);
        let title = if item_type.contains("contextcompaction") {
            match status {
                "failed" => "Compaction failed".to_string(),
                "completed" => "Compacted".to_string(),
                _ => "Compacting".to_string(),
            }
        } else {
            first_string(&[
                item.get("title"),
                item.get("name"),
                item.get("tool"),
                item.get("command"),
            ])
        };
        upsert_cell(
            &mut cells,
            new_cell(
                &id,
                &turn_id,
                kind,
                status,
                &now,
                if title.is_empty() {
                    Some(title_for(&item_type, &lower))
                } else {
                    Some(title)
                },
                Some(first_string(&[
                    item.get("command"),
                    item.get("path"),
                    item.get("cwd"),
                    item.get("server"),
                ])),
                if text.is_empty() { None } else { Some(text) },
                if details.is_empty() {
                    None
                } else {
                    Some(details)
                },
                method != "item/completed",
                Some(json!({
                    "itemType": item.get("type"),
                    "type": item.get("type"),
                    "query": item.get("query"),
                    "url": item.get("url"),
                    "action": item.get("action"),
                    "changes": item.get("changes"),
                    "arguments": item.get("arguments"),
                    "result": item.get("result"),
                    "commandActions": item.get("commandActions"),
                    "durationMs": item.get("durationMs"),
                    "status": item.get("status"),
                    "streamPhase": if is_agent_message && !phase.is_empty() {
                        Value::String(phase)
                    } else {
                        Value::Null
                    }
                })),
            ),
        );
    } else if method == "error" || method == "stream/error" || method == "stream_error" {
        let text = first_string(&[
            params.get("message"),
            params.get("error"),
            message.get("error"),
        ]);
        if !text.is_empty() {
            cells.push(new_cell(
                &format!(
                    "error-{}",
                    Utc::now().timestamp_nanos_opt().unwrap_or_default()
                ),
                &turn_id,
                "systemNotice",
                "failed",
                &now,
                Some("Codex error".to_string()),
                None,
                Some(text),
                None,
                false,
                None,
            ));
        }
    } else if lower.contains("review") && !turn_id.is_empty() {
        let review = first_string(&[params.get("review"), params.get("text")]);
        let id = if item_id.is_empty() {
            format!("review-{turn_id}")
        } else {
            format!("item-{item_id}")
        };
        upsert_cell(
            &mut cells,
            new_cell(
                &id,
                &turn_id,
                "toolCall",
                "completed",
                &now,
                Some(if lower.contains("enter") {
                    "Preparing review".to_string()
                } else {
                    "Review finished".to_string()
                }),
                None,
                None,
                if review.is_empty() {
                    None
                } else {
                    Some(review.clone())
                },
                false,
                None,
            ),
        );
        if !review.is_empty() {
            let mut body = new_cell(
                &format!("review-body-{turn_id}"),
                &turn_id,
                "progressText",
                "completed",
                &now,
                None,
                None,
                Some(review),
                None,
                false,
                None,
            );
            if let Some(map) = body.as_object_mut() {
                map.insert(
                    "metadata".to_string(),
                    json!({"uiPlacement": "outside_worked"}),
                );
            }
            upsert_cell(&mut cells, body);
        }
    }

    trim_cells(&mut cells);
    object.insert("timelineCells".to_string(), Value::Array(cells));
}
