//! Human-readable one-line summaries for orchestration CLI output.
//!
//! Split out of `orchestration_commands.rs` so the command dispatcher stays
//! focused on building request payloads.

use serde_json::Value;

pub(crate) fn human_summary(request_type: &str, value: &Value) -> String {
    match request_type {
        "orchestration.send" => {
            let recipients = value
                .get("recipients")
                .and_then(Value::as_array)
                .map(|entries| entries.len())
                .unwrap_or(0);
            format!("message sent to {recipients} recipient(s)")
        }
        "orchestration.check" => {
            if let Some(formatted) = value.get("formatted").and_then(Value::as_str) {
                if !formatted.is_empty() {
                    return formatted.to_string();
                }
            }
            check_message_summary(value)
        }
        "orchestration.reply" => "reply sent".to_string(),
        "orchestration.inbox" => {
            let count = value
                .get("items")
                .and_then(Value::as_array)
                .map(|messages| messages.len())
                .unwrap_or(0);
            format!("{count} message(s)")
        }
        "orchestration.taskCreate" => value
            .get("id")
            .and_then(Value::as_str)
            .map(|id| format!("task created: {id}"))
            .unwrap_or_else(|| "task created".to_string()),
        "orchestration.taskList" => {
            let count = value
                .get("items")
                .and_then(Value::as_array)
                .map(|tasks| tasks.len())
                .unwrap_or(0);
            format!("{count} task(s)")
        }
        "agentProfile.list" => {
            let items = value.get("items").and_then(Value::as_array);
            let count = items.map(Vec::len).unwrap_or(0);
            if count == 0 {
                return "no agent profiles declared".to_string();
            }
            let mut lines = vec![format!("{count} agent profile(s)")];
            for item in items.into_iter().flatten() {
                let name = item.get("name").and_then(Value::as_str).unwrap_or("");
                let agent_type = item.get("agentType").and_then(Value::as_str).unwrap_or("");
                let quota_group = item
                    .get("quotaGroup")
                    .and_then(Value::as_str)
                    .map(|group| format!(" [{group}]"))
                    .unwrap_or_default();
                lines.push(format!("  {name} ({agent_type}){quota_group}"));
            }
            lines.join("\n")
        }
        "orchestration.runPolicyPropose"
        | "orchestration.runPolicyShow"
        | "orchestration.runPolicyApprove"
        | "orchestration.runPolicyReject" => {
            let status = value
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("none");
            let stages = value
                .get("policy")
                .and_then(|policy| policy.get("stages"))
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0);
            if status == "none" {
                return "run has no execution policy".to_string();
            }
            let blocked = value
                .get("blocksDispatch")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let suffix = if blocked {
                " (scheduling held until it is resolved)"
            } else {
                ""
            };
            format!("execution policy {status}, {stages} stage(s){suffix}")
        }
        "orchestration.taskUpdate" => "task updated".to_string(),
        "orchestration.dispatch" => value
            .get("preamble")
            .or_else(|| {
                (value.get("startupState").and_then(Value::as_str)
                    == Some("awaiting_manual_delivery"))
                .then(|| value.get("bootstrap"))
                .flatten()
            })
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| {
                if value
                    .get("dryRun")
                    .and_then(Value::as_bool)
                    .unwrap_or(false)
                {
                    "dispatch dry run".to_string()
                } else {
                    "task dispatched".to_string()
                }
            }),
        "orchestration.dispatchShow" => {
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "dispatch context".to_string())
        }
        "orchestration.gateCreate" => value
            .get("id")
            .and_then(Value::as_str)
            .map(|id| format!("gate created: {id}"))
            .unwrap_or_else(|| "gate created".to_string()),
        "orchestration.gateResolve" => "gate resolved".to_string(),
        "orchestration.gateList" => {
            let count = value
                .get("items")
                .and_then(Value::as_array)
                .map(|gates| gates.len())
                .unwrap_or(0);
            format!("{count} gate(s)")
        }
        "orchestration.run" => value
            .get("runId")
            .and_then(Value::as_str)
            .map(|id| format!("coordinator run started: {id}"))
            .unwrap_or_else(|| "coordinator run started".to_string()),
        "orchestration.runStop" => "coordinator run stopped".to_string(),
        "orchestration.terminals" => {
            let count = value
                .get("items")
                .and_then(Value::as_array)
                .map(|terminals| terminals.len())
                .unwrap_or(0);
            format!("{count} terminal(s)")
        }
        "orchestration.reset" => "orchestration state reset".to_string(),
        _ => serde_json::to_string_pretty(value).unwrap_or_else(|_| "ok".to_string()),
    }
}

fn check_message_summary(value: &Value) -> String {
    let Some(messages) = value.get("messages").and_then(Value::as_array) else {
        return "0 message(s)".to_string();
    };
    if messages.is_empty() {
        return "0 message(s)".to_string();
    }
    messages
        .iter()
        .map(check_message_item_summary)
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn check_message_item_summary(message: &Value) -> String {
    let id = message.get("id").and_then(Value::as_str).unwrap_or("");
    let from = message
        .get("from_handle")
        .and_then(Value::as_str)
        .unwrap_or("<unknown>");
    let message_type = message
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("status");
    let subject = message
        .get("subject")
        .and_then(Value::as_str)
        .unwrap_or("<no subject>");
    let mut lines = vec![
        format!("From: {from} ({message_type})"),
        format!("Subject: {subject}"),
    ];
    if let Some(body) = message
        .get("body")
        .and_then(Value::as_str)
        .filter(|body| !body.is_empty())
    {
        lines.push(body.to_string());
    }
    if let Some(payload) = message
        .get("payload")
        .and_then(Value::as_str)
        .filter(|payload| !payload.is_empty())
    {
        lines.push(format!("[Payload: {payload}]"));
    }
    if !id.is_empty() {
        lines.push(format!(
            "[Reply: alera orchestration reply --id {id} --body \"...\"]"
        ));
    }
    lines.join("\n")
}
