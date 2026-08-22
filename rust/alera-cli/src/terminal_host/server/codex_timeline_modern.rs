//! Reduction for app-server notifications that do not use the item lifecycle.

use serde_json::{json, Value};

use super::codex_timeline_cells::{complete_context_compaction, new_cell, upsert_cell};

pub(super) fn reduce_modern_notification(
    cells: &mut Vec<Value>,
    method: &str,
    params: &Value,
    turn_id: &str,
    item_id: &str,
    now: &str,
) -> bool {
    match method {
        "turn/plan/updated" if !turn_id.is_empty() => {
            reduce_plan(cells, params, turn_id, now);
            true
        }
        "item/fileChange/patchUpdated" if !turn_id.is_empty() => {
            reduce_patch(cells, params, turn_id, item_id, now);
            true
        }
        "thread/compacted" if !turn_id.is_empty() => {
            complete_context_compaction(cells, turn_id, now);
            true
        }
        "model/rerouted" if !turn_id.is_empty() => {
            reduce_model_reroute(cells, params, turn_id, now);
            true
        }
        "model/verification" if !turn_id.is_empty() => {
            reduce_model_verification(cells, params, turn_id, now);
            true
        }
        "model/safetyBuffering/updated" if !turn_id.is_empty() => {
            reduce_safety_buffering(cells, params, turn_id, now);
            true
        }
        "mcpServer/startupStatus/updated" => {
            reduce_mcp_startup(cells, params, turn_id, now);
            true
        }
        "warning" | "guardianWarning" | "configWarning" | "deprecationNotice" => {
            reduce_notice(cells, method, params, turn_id, now);
            true
        }
        _ => false,
    }
}

fn reduce_plan(cells: &mut Vec<Value>, params: &Value, turn_id: &str, now: &str) {
    let plan = params
        .get("plan")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let complete = !plan.is_empty()
        && plan.iter().all(|step| {
            step.get("status")
                .and_then(Value::as_str)
                .is_some_and(|status| status.eq_ignore_ascii_case("completed"))
        });
    let markdown = plan_markdown(params.get("explanation"), &plan);
    upsert_cell(
        cells,
        new_cell(
            &format!("plan-{turn_id}"),
            turn_id,
            "plan",
            if complete { "completed" } else { "inProgress" },
            now,
            Some("Plan".to_string()),
            None,
            (!markdown.is_empty()).then_some(markdown),
            None,
            !complete,
            Some(json!({
                "explanation": params.get("explanation"),
                "plan": plan,
            })),
        ),
    );
}

fn plan_markdown(explanation: Option<&Value>, plan: &[Value]) -> String {
    let mut sections = Vec::new();
    if let Some(explanation) = explanation.and_then(Value::as_str) {
        let explanation = explanation.trim();
        if !explanation.is_empty() {
            sections.push(explanation.to_string());
        }
    }
    let steps = plan
        .iter()
        .filter_map(|entry| {
            let step = entry.get("step")?.as_str()?.trim();
            if step.is_empty() {
                return None;
            }
            let status = entry
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("pending");
            let marker = if status.eq_ignore_ascii_case("completed") {
                "x"
            } else {
                " "
            };
            let suffix = if status.eq_ignore_ascii_case("inProgress") {
                " *(In progress)*"
            } else {
                ""
            };
            Some(format!("- [{marker}] {step}{suffix}"))
        })
        .collect::<Vec<_>>()
        .join("\n");
    if !steps.is_empty() {
        sections.push(steps);
    }
    sections.join("\n\n")
}

fn reduce_patch(cells: &mut Vec<Value>, params: &Value, turn_id: &str, item_id: &str, now: &str) {
    let id = if item_id.is_empty() {
        format!("diff-{turn_id}")
    } else {
        format!("item-{item_id}")
    };
    let changes = params.get("changes").cloned().unwrap_or_else(|| json!([]));
    upsert_cell(
        cells,
        new_cell(
            &id,
            turn_id,
            "diff",
            "inProgress",
            now,
            Some("File changes".to_string()),
            None,
            None,
            None,
            true,
            Some(json!({
                "itemType": "fileChange",
                "changes": changes,
            })),
        ),
    );
}

fn reduce_model_reroute(cells: &mut Vec<Value>, params: &Value, turn_id: &str, now: &str) {
    let from = params
        .get("fromModel")
        .and_then(Value::as_str)
        .unwrap_or("the selected model");
    let to = params
        .get("toModel")
        .and_then(Value::as_str)
        .unwrap_or("another model");
    let reason = params
        .get("reason")
        .map(value_text)
        .filter(|value| !value.is_empty());
    let markdown = format!(
        "Codex switched from `{from}` to `{to}`{}.",
        reason
            .map(|value| format!(" because {value}"))
            .unwrap_or_default()
    );
    upsert_cell(
        cells,
        new_cell(
            &format!("model-reroute-{turn_id}"),
            turn_id,
            "systemNotice",
            "info",
            now,
            Some("Model changed".to_string()),
            None,
            Some(markdown),
            None,
            false,
            Some(json!({
                "fromModel": params.get("fromModel"),
                "toModel": params.get("toModel"),
                "reason": params.get("reason"),
            })),
        ),
    );
}

fn reduce_model_verification(cells: &mut Vec<Value>, params: &Value, turn_id: &str, now: &str) {
    let verifications = params
        .get("verifications")
        .cloned()
        .unwrap_or_else(|| json!([]));
    let details = value_text(&verifications);
    upsert_cell(
        cells,
        new_cell(
            &format!("model-verification-{turn_id}"),
            turn_id,
            "systemNotice",
            "info",
            now,
            Some("Account verification".to_string()),
            None,
            Some(if details == "[]" {
                "Codex requires additional account verification.".to_string()
            } else {
                format!("Codex requires additional account verification: `{details}`.")
            }),
            None,
            false,
            Some(json!({"verifications": verifications})),
        ),
    );
}

fn reduce_safety_buffering(cells: &mut Vec<Value>, params: &Value, turn_id: &str, now: &str) {
    let visible = params
        .get("showBufferingUi")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let faster_model = params.get("fasterModel").and_then(Value::as_str);
    let mut markdown = "Codex is checking this request before continuing.".to_string();
    if let Some(faster_model) = faster_model.filter(|value| !value.is_empty()) {
        markdown.push_str(&format!(
            "\n\nA faster model is available: `{faster_model}`."
        ));
    }
    upsert_cell(
        cells,
        new_cell(
            &format!("safety-buffering-{turn_id}"),
            turn_id,
            "systemNotice",
            if visible { "inProgress" } else { "completed" },
            now,
            Some("Safety review".to_string()),
            None,
            Some(markdown),
            None,
            visible,
            Some(json!({
                "model": params.get("model"),
                "useCases": params.get("useCases"),
                "reasons": params.get("reasons"),
                "showBufferingUi": visible,
                "fasterModel": params.get("fasterModel"),
            })),
        ),
    );
}

fn reduce_mcp_startup(cells: &mut Vec<Value>, params: &Value, turn_id: &str, now: &str) {
    let name = params
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .unwrap_or("MCP");
    let status = params
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("starting");
    let failed = status.eq_ignore_ascii_case("failed");
    let starting = status.eq_ignore_ascii_case("starting");
    let details = ["error", "failureReason"]
        .into_iter()
        .find_map(|key| params.get(key).and_then(Value::as_str))
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    upsert_cell(
        cells,
        new_cell(
            &format!("mcp-startup-{name}"),
            turn_id,
            "toolCall",
            if failed {
                "failed"
            } else if starting {
                "inProgress"
            } else {
                "completed"
            },
            now,
            Some(format!("{name} MCP server")),
            Some(status.to_string()),
            None,
            details,
            starting,
            Some(json!({
                "itemType": "mcpServerStartup",
                "status": status,
                "failureReason": params.get("failureReason"),
            })),
        ),
    );
}

fn reduce_notice(cells: &mut Vec<Value>, method: &str, params: &Value, turn_id: &str, now: &str) {
    let summary = ["message", "summary"]
        .into_iter()
        .find_map(|key| params.get(key).and_then(Value::as_str))
        .unwrap_or_default()
        .trim();
    let details = params
        .get("details")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim();
    if summary.is_empty() && details.is_empty() {
        return;
    }
    let markdown = [summary, details]
        .into_iter()
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n");
    let title = match method {
        "deprecationNotice" => "Codex deprecation",
        "configWarning" => "Configuration warning",
        "guardianWarning" => "Safety warning",
        _ => "Codex warning",
    };
    cells.push(new_cell(
        &format!(
            "notice-{}",
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
        ),
        turn_id,
        "systemNotice",
        "info",
        now,
        Some(title.to_string()),
        params
            .get("path")
            .and_then(Value::as_str)
            .map(str::to_string),
        Some(markdown),
        None,
        false,
        Some(json!({"noticeType": method})),
    ));
}

fn value_text(value: &Value) -> String {
    value
        .as_str()
        .map(str::to_string)
        .unwrap_or_else(|| value.to_string())
}

#[cfg(test)]
mod tests {
    use super::{plan_markdown, reduce_modern_notification};
    use serde_json::json;

    #[test]
    fn plan_markdown_preserves_explanation_and_statuses() {
        let plan = json!([
            {"step": "Inspect", "status": "completed"},
            {"step": "Implement", "status": "inProgress"},
            {"step": "Verify", "status": "pending"}
        ]);
        let markdown = plan_markdown(Some(&json!("Approach")), plan.as_array().unwrap());
        assert_eq!(
            markdown,
            "Approach\n\n- [x] Inspect\n- [ ] Implement *(In progress)*\n- [ ] Verify"
        );
    }

    #[test]
    fn modern_notifications_create_stable_timeline_cells() {
        let mut cells = Vec::new();
        assert!(reduce_modern_notification(
            &mut cells,
            "turn/plan/updated",
            &json!({
                "explanation": "Approach",
                "plan": [{"step": "Implement", "status": "inProgress"}]
            }),
            "turn",
            "",
            "2026-08-03T12:00:00Z",
        ));
        assert!(reduce_modern_notification(
            &mut cells,
            "item/fileChange/patchUpdated",
            &json!({"changes": [{"path": "README.md", "kind": "update"}]}),
            "turn",
            "files",
            "2026-08-03T12:00:01Z",
        ));
        assert!(reduce_modern_notification(
            &mut cells,
            "model/rerouted",
            &json!({
                "fromModel": "gpt-a",
                "toModel": "gpt-b",
                "reason": "capacity"
            }),
            "turn",
            "",
            "2026-08-03T12:00:02Z",
        ));
        assert_eq!(cells.len(), 3);
        assert_eq!(cells[0]["kind"], "plan");
        assert_eq!(cells[1]["metadata"]["changes"][0]["path"], "README.md");
        assert_eq!(cells[2]["kind"], "systemNotice");
        assert!(cells[2]["markdownText"].as_str().unwrap().contains("gpt-b"));
    }

    #[test]
    fn safety_verification_and_mcp_updates_reuse_stable_cells() {
        let mut cells = Vec::new();
        assert!(reduce_modern_notification(
            &mut cells,
            "model/verification",
            &json!({"verifications": ["trustedAccessForCyber"]}),
            "turn",
            "",
            "2026-08-03T12:00:00Z",
        ));
        for visible in [true, false] {
            assert!(reduce_modern_notification(
                &mut cells,
                "model/safetyBuffering/updated",
                &json!({"showBufferingUi": visible, "fasterModel": "gpt-fast"}),
                "turn",
                "",
                "2026-08-03T12:00:01Z",
            ));
        }
        for status in ["starting", "failed"] {
            assert!(reduce_modern_notification(
                &mut cells,
                "mcpServer/startupStatus/updated",
                &json!({"name": "filesystem", "status": status}),
                "turn",
                "",
                "2026-08-03T12:00:02Z",
            ));
        }
        assert_eq!(cells.len(), 3);
        assert_eq!(cells[0]["title"], "Account verification");
        assert_eq!(cells[1]["status"], "completed");
        assert_eq!(cells[2]["status"], "failed");
    }
}
