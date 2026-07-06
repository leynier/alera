use serde_json::{json, Map, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    OrchestrationAction, OrchestrationAskArgs, OrchestrationCheckArgs, OrchestrationCommand,
    OrchestrationSendArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_CAPABILITY;

const USAGE_EXIT_CODE: i32 = 64;
/// Grace added to the server-side wait deadline so the client outlives it.
const WAIT_CLIENT_GRACE_MS: u64 = 5_000;
const DEFAULT_WAIT_TIMEOUT_MS: u64 = 120_000;

const LIFECYCLE_TYPES: &[&str] = &["worker_done", "heartbeat"];

pub async fn run_orchestration_command(command: OrchestrationCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        OrchestrationAction::Send(args) => match build_send_payload(args) {
            Ok(payload) => {
                request(&runtime, "orchestration.send", payload, json_output, None).await
            }
            Err(message) => usage_error(&message),
        },
        OrchestrationAction::Check(args) => run_check(&runtime, args, json_output).await,
        OrchestrationAction::Reply(args) => {
            request(
                &runtime,
                "orchestration.reply",
                json!({ "id": args.id, "body": args.body }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Inbox(args) => {
            let mut payload = Map::new();
            insert_opt(&mut payload, "terminal", args.terminal);
            if let Some(limit) = args.limit {
                payload.insert("limit".to_string(), json!(limit));
            }
            request(
                &runtime,
                "orchestration.inbox",
                Value::Object(payload),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Ask(args) => run_ask(&runtime, args, json_output).await,
        OrchestrationAction::TaskCreate(args) => {
            let deps: Vec<String> = match args.deps.as_deref() {
                None => Vec::new(),
                Some(raw) => match serde_json::from_str(raw) {
                    Ok(deps) => deps,
                    Err(_) => return usage_error("--deps must be a JSON array of task ids."),
                },
            };
            request(
                &runtime,
                "orchestration.taskCreate",
                json!({
                    "spec": args.spec,
                    "taskTitle": args.task_title,
                    "deps": deps,
                    "parent": args.parent,
                    "createdBy": terminal_handle_env(),
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TaskList(args) => {
            let status = if args.ready {
                Some("ready".to_string())
            } else {
                args.status
            };
            let mut payload = Map::new();
            insert_opt(&mut payload, "status", status);
            request(
                &runtime,
                "orchestration.taskList",
                Value::Object(payload),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TaskUpdate(args) => {
            request(
                &runtime,
                "orchestration.taskUpdate",
                json!({
                    "id": args.id,
                    "status": args.status,
                    "result": args.result,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Dispatch(args) => {
            let Some(from) = args.from.or_else(terminal_handle_env) else {
                return usage_error(
                    "--from is required (or set ALERA_TERMINAL_HANDLE) so the preamble can name the coordinator.",
                );
            };
            request(
                &runtime,
                "orchestration.dispatch",
                json!({
                    "task": args.task,
                    "to": args.to,
                    "from": from,
                    "inject": args.inject,
                    "dryRun": args.dry_run,
                    "returnPreamble": args.return_preamble,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::DispatchShow(args) => {
            request(
                &runtime,
                "orchestration.dispatchShow",
                json!({ "task": args.task }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::GateCreate(args) => {
            let options: Vec<String> = match args.options.as_deref() {
                None => Vec::new(),
                Some(raw) => match serde_json::from_str(raw) {
                    Ok(options) => options,
                    Err(_) => return usage_error("--options must be a JSON array of strings."),
                },
            };
            request(
                &runtime,
                "orchestration.gateCreate",
                json!({
                    "task": args.task,
                    "question": args.question,
                    "options": options,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::GateResolve(args) => {
            request(
                &runtime,
                "orchestration.gateResolve",
                json!({ "id": args.id, "resolution": args.resolution }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::GateList(args) => {
            let mut payload = Map::new();
            insert_opt(&mut payload, "task", args.task);
            insert_opt(&mut payload, "status", args.status);
            request(
                &runtime,
                "orchestration.gateList",
                Value::Object(payload),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Run(args) => {
            let Some(from) = args.from.or_else(terminal_handle_env) else {
                return usage_error(
                    "--from is required (or set ALERA_TERMINAL_HANDLE) so workers can contact the coordinator.",
                );
            };
            request(
                &runtime,
                "orchestration.run",
                json!({
                    "spec": args.spec,
                    "from": from,
                    "pollIntervalMs": args.poll_interval_ms,
                    "maxConcurrent": args.max_concurrent,
                    "workspace": args.workspace,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunStop => {
            request(
                &runtime,
                "orchestration.runStop",
                json!({}),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TerminalList => {
            request(
                &runtime,
                "orchestration.terminals",
                json!({}),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Reset(args) => {
            request(
                &runtime,
                "orchestration.reset",
                json!({
                    "all": args.all,
                    "tasks": args.tasks,
                    "messages": args.messages,
                }),
                json_output,
                None,
            )
            .await
        }
    }
}

fn build_send_payload(args: OrchestrationSendArgs) -> Result<Value, String> {
    let Some(from) = args.from.or_else(terminal_handle_env) else {
        return Err(
            "--from is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set)."
                .to_string(),
        );
    };
    // Client-side mirror of the server rule so the error is immediate.
    if let Some(message_type) = args.message_type.as_deref() {
        if LIFECYCLE_TYPES.contains(&message_type) && args.to.starts_with('@') {
            return Err(format!(
                "{message_type} messages cannot be sent to a group address."
            ));
        }
    }
    let payload_json = build_structured_payload(
        args.payload,
        args.task_id,
        args.dispatch_id,
        args.files_modified,
        args.report_path,
        args.phase,
    )?;
    let mut payload = Map::new();
    payload.insert("from".to_string(), json!(from));
    payload.insert("to".to_string(), json!(args.to));
    payload.insert("subject".to_string(), json!(args.subject));
    insert_opt(&mut payload, "body", args.body);
    insert_opt(&mut payload, "type", args.message_type);
    insert_opt(&mut payload, "priority", args.priority);
    insert_opt(&mut payload, "threadId", args.thread_id);
    insert_opt(&mut payload, "payload", payload_json);
    Ok(Value::Object(payload))
}

/// Structured payload flags exist because raw JSON in `--payload` is fragile
/// under Windows PowerShell quoting; the CLI assembles the JSON itself.
fn build_structured_payload(
    raw: Option<String>,
    task_id: Option<String>,
    dispatch_id: Option<String>,
    files_modified: Option<String>,
    report_path: Option<String>,
    phase: Option<String>,
) -> Result<Option<String>, String> {
    if let Some(raw) = raw {
        if serde_json::from_str::<Value>(&raw).is_err() {
            return Err("--payload must be valid JSON.".to_string());
        }
        return Ok(Some(raw));
    }
    let mut payload = Map::new();
    if let Some(task_id) = task_id {
        payload.insert("taskId".to_string(), json!(task_id));
    }
    if let Some(dispatch_id) = dispatch_id {
        payload.insert("dispatchId".to_string(), json!(dispatch_id));
    }
    if let Some(files) = files_modified {
        let files: Vec<String> = files
            .split(',')
            .map(str::trim)
            .filter(|entry| !entry.is_empty())
            .map(str::to_string)
            .collect();
        payload.insert("filesModified".to_string(), json!(files));
    }
    if let Some(report_path) = report_path {
        payload.insert("reportPath".to_string(), json!(report_path));
    }
    if let Some(phase) = phase {
        payload.insert("phase".to_string(), json!(phase));
    }
    if payload.is_empty() {
        return Ok(None);
    }
    Ok(Some(Value::Object(payload).to_string()))
}

async fn run_check(
    runtime: &RuntimeDirArgs,
    args: OrchestrationCheckArgs,
    json_output: bool,
) -> i32 {
    let Some(terminal) = args.terminal.or_else(terminal_handle_env) else {
        return usage_error(
            "--terminal is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set).",
        );
    };
    let types: Vec<String> = args
        .types
        .as_deref()
        .map(|raw| {
            raw.split(',')
                .map(str::trim)
                .filter(|entry| !entry.is_empty())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    let timeout_ms = args.timeout_ms.unwrap_or(DEFAULT_WAIT_TIMEOUT_MS);
    let mut payload = Map::new();
    payload.insert("terminal".to_string(), json!(terminal));
    payload.insert("all".to_string(), json!(args.all));
    payload.insert("wait".to_string(), json!(args.wait));
    payload.insert("inject".to_string(), json!(args.inject));
    if !types.is_empty() {
        payload.insert("types".to_string(), json!(types));
    }
    if args.wait {
        payload.insert("timeoutMs".to_string(), json!(timeout_ms));
    }
    if let Some(limit) = args.limit {
        payload.insert("limit".to_string(), json!(limit));
    }
    let deadline = args
        .wait
        .then_some(timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS));
    request(
        runtime,
        "orchestration.check",
        Value::Object(payload),
        json_output,
        deadline,
    )
    .await
}

async fn run_ask(runtime: &RuntimeDirArgs, args: OrchestrationAskArgs, json_output: bool) -> i32 {
    let Some(from) = args.from.or_else(terminal_handle_env) else {
        return usage_error(
            "--from is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set).",
        );
    };
    if args.to.starts_with('@') {
        return usage_error("ask requires a single terminal handle, not a group address.");
    }
    let timeout_ms = args.timeout_ms.unwrap_or(DEFAULT_WAIT_TIMEOUT_MS);
    let payload = json!({
        "from": from,
        "to": args.to,
        "question": args.question,
        "options": args.options,
        "timeoutMs": timeout_ms,
    });
    let value = match request_value(
        runtime,
        "orchestration.ask",
        payload,
        Some(timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
    )
    .await
    {
        Ok(value) => value,
        Err(error) => {
            eprintln!("{error}");
            return 1;
        }
    };
    let answered = value
        .get("answered")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if json_output {
        println!("{value}");
    } else if answered {
        let body = value
            .get("reply")
            .and_then(|reply| reply.get("body"))
            .and_then(Value::as_str)
            .unwrap_or("");
        println!("{body}");
    } else {
        eprintln!("ask timed out with no reply");
    }
    // A timeout is a runtime failure so scripted callers can branch on it.
    if answered {
        0
    } else {
        1
    }
}

async fn request(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: Value,
    json_output: bool,
    deadline_ms: Option<u64>,
) -> i32 {
    match request_value(runtime, request_type, payload, deadline_ms).await {
        Ok(value) => {
            if json_output {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string())
                );
            } else {
                println!("{}", human_summary(request_type, &value));
            }
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

async fn request_value(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: Value,
    deadline_ms: Option<u64>,
) -> anyhow::Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    )
    .await?;
    match deadline_ms {
        Some(deadline_ms) => {
            client
                .request_value_with_deadline(request_type, &payload, deadline_ms)
                .await
        }
        None => client.request_value(request_type, &payload).await,
    }
}

fn human_summary(request_type: &str, value: &Value) -> String {
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
                .get("messages")
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
                .get("tasks")
                .and_then(Value::as_array)
                .map(|tasks| tasks.len())
                .unwrap_or(0);
            format!("{count} task(s)")
        }
        "orchestration.taskUpdate" => "task updated".to_string(),
        "orchestration.dispatch" => value
            .get("preamble")
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
                .get("gates")
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
                .get("terminals")
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

fn insert_opt(payload: &mut Map<String, Value>, key: &str, value: Option<String>) {
    if let Some(value) = value {
        payload.insert(key.to_string(), json!(value));
    }
}

fn terminal_handle_env() -> Option<String> {
    std::env::var("ALERA_TERMINAL_HANDLE")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn usage_error(message: &str) -> i32 {
    eprintln!("{message}");
    USAGE_EXIT_CODE
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn structured_payload_assembles_json() {
        let payload = build_structured_payload(
            None,
            Some("task_1".to_string()),
            Some("ctx_1".to_string()),
            Some("a.rs, b.rs".to_string()),
            Some("/tmp/report.md".to_string()),
            Some("implementing".to_string()),
        )
        .unwrap()
        .unwrap();
        let value: Value = serde_json::from_str(&payload).unwrap();
        assert_eq!(value["taskId"], "task_1");
        assert_eq!(value["dispatchId"], "ctx_1");
        assert_eq!(value["filesModified"], json!(["a.rs", "b.rs"]));
        assert_eq!(value["reportPath"], "/tmp/report.md");
        assert_eq!(value["phase"], "implementing");
    }

    #[test]
    fn raw_payload_must_be_valid_json() {
        assert!(build_structured_payload(
            Some("{not json".to_string()),
            None,
            None,
            None,
            None,
            None
        )
        .is_err());
        let passthrough =
            build_structured_payload(Some("{\"x\":1}".to_string()), None, None, None, None, None)
                .unwrap();
        assert_eq!(passthrough.as_deref(), Some("{\"x\":1}"));
    }

    #[test]
    fn empty_structured_payload_is_none() {
        let payload = build_structured_payload(None, None, None, None, None, None).unwrap();
        assert!(payload.is_none());
    }

    #[test]
    fn dispatch_summary_prints_dry_run_preamble() {
        let summary = human_summary(
            "orchestration.dispatch",
            &json!({
                "dryRun": true,
                "preamble": "handoff text to paste"
            }),
        );
        assert_eq!(summary, "handoff text to paste");
    }

    #[test]
    fn dispatch_summary_prints_returned_preamble() {
        let summary = human_summary(
            "orchestration.dispatch",
            &json!({
                "dispatch": {
                    "id": "ctx_1"
                },
                "preamble": "manual injection text"
            }),
        );
        assert_eq!(summary, "manual injection text");
    }

    #[test]
    fn dispatch_summary_labels_dry_run_without_preamble() {
        let summary = human_summary("orchestration.dispatch", &json!({ "dryRun": true }));
        assert_eq!(summary, "dispatch dry run");
    }

    #[test]
    fn default_check_summary_prints_message_contents() {
        let summary = human_summary(
            "orchestration.check",
            &json!({
                "messages": [{
                    "id": "msg_1",
                    "from_handle": "coord",
                    "to_handle": "worker",
                    "subject": "Follow up",
                    "body": "Please rerun tests.",
                    "type": "status",
                    "priority": "normal",
                    "thread_id": null,
                    "payload": "{\"taskId\":\"task_1\"}",
                    "read": false,
                    "sequence": 1,
                    "created_at": "2026-07-05 19:00:00",
                    "delivered_at": null
                }]
            }),
        );
        assert!(summary.contains("From: coord (status)"));
        assert!(summary.contains("Subject: Follow up"));
        assert!(summary.contains("Please rerun tests."));
        assert!(summary.contains("alera orchestration reply --id msg_1"));
    }
}
