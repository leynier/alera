//! The worker protocol (`context`, `complete`, `escalate`) and messages
//! between agents (`ask`, `reply`, `send`, `check`, `messages`).

use std::io::Read;

use serde_json::{json, Map, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    OrchestrationAskArgs, OrchestrationCheckArgs, OrchestrationCompleteArgs,
    OrchestrationEscalateArgs, OrchestrationMessagesArgs, OrchestrationReplyArgs,
    OrchestrationSendArgs,
};

use super::{
    insert_opt, request, request_value, terminal_handle_env, usage_error, WAIT_CLIENT_GRACE_MS,
};

const DEFAULT_WAIT_TIMEOUT_MS: u64 = 120_000;

pub(super) async fn context(runtime: &RuntimeDirArgs, json_output: bool) -> i32 {
    let (terminal, context_token) = worker_identity(runtime);
    request(
        runtime,
        "orchestration.context",
        json!({ "terminal": terminal, "contextToken": context_token }),
        json_output,
        None,
    )
    .await
}

pub(super) async fn complete(
    runtime: &RuntimeDirArgs,
    args: OrchestrationCompleteArgs,
    json_output: bool,
) -> i32 {
    let result = match completion_result(args) {
        Ok(result) => result,
        Err(error) => return usage_error(&error),
    };
    let (terminal, context_token) = worker_identity(runtime);
    request(
        runtime,
        "orchestration.complete",
        json!({ "terminal": terminal, "contextToken": context_token, "result": result }),
        json_output,
        None,
    )
    .await
}

pub(super) async fn escalate(
    runtime: &RuntimeDirArgs,
    args: OrchestrationEscalateArgs,
    json_output: bool,
) -> i32 {
    let body = match read_body(args.body, args.body_file, args.body_stdin) {
        Ok(body) => body,
        Err(error) => return usage_error(&error),
    };
    let (terminal, context_token) = worker_identity(runtime);
    request(
        runtime,
        "orchestration.escalate",
        json!({
            "terminal": terminal,
            "contextToken": context_token,
            "subject": args.subject,
            "body": body,
        }),
        json_output,
        None,
    )
    .await
}

pub(super) async fn reply(
    runtime: &RuntimeDirArgs,
    args: OrchestrationReplyArgs,
    json_output: bool,
) -> i32 {
    match read_body(args.body, args.body_file, args.body_stdin) {
        Ok(Some(body)) if !body.trim().is_empty() => {
            let payload = json!({ "id": args.id, "body": body });
            request(runtime, "orchestration.reply", payload, json_output, None).await
        }
        Ok(_) => usage_error("--body, --body-file or --body-stdin is required."),
        Err(message) => usage_error(&message),
    }
}

pub(super) async fn send(
    runtime: &RuntimeDirArgs,
    args: OrchestrationSendArgs,
    json_output: bool,
) -> i32 {
    match build_send_payload(args) {
        Ok(payload) => request(runtime, "orchestration.send", payload, json_output, None).await,
        Err(message) => usage_error(&message),
    }
}

pub(super) async fn messages(
    runtime: &RuntimeDirArgs,
    args: OrchestrationMessagesArgs,
    json_output: bool,
) -> i32 {
    let mut payload = Map::new();
    insert_opt(&mut payload, "terminal", args.terminal);
    payload.insert("direction".to_string(), json!(args.direction));
    insert_opt(&mut payload, "limit", args.limit);
    request(
        runtime,
        "orchestration.messages",
        Value::Object(payload),
        json_output,
        None,
    )
    .await
}

/// The caller's terminal and the token of its dispatch context, which the
/// host checks before it lets a worker command touch the dispatch.
fn worker_identity(runtime: &RuntimeDirArgs) -> (Option<String>, Option<String>) {
    let terminal = terminal_handle_env();
    let token = terminal
        .as_deref()
        .and_then(|handle| dispatch_context_token(runtime, handle));
    (terminal, token)
}

pub(super) fn build_send_payload(args: OrchestrationSendArgs) -> Result<Value, String> {
    let Some(from) = args.from.or_else(terminal_handle_env) else {
        return Err(
            "--from is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set)."
                .to_string(),
        );
    };
    let body = read_body(args.body, args.body_file, args.body_stdin)?;
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
    insert_opt(&mut payload, "body", body);
    insert_opt(&mut payload, "type", args.message_type);
    insert_opt(&mut payload, "priority", args.priority);
    insert_opt(&mut payload, "threadId", args.thread_id);
    insert_opt(&mut payload, "payload", payload_json);
    insert_opt(
        &mut payload,
        "delivery",
        args.delivery.as_deref().map(wire_delivery),
    );
    Ok(Value::Object(payload))
}

pub(crate) fn read_body(
    inline: Option<String>,
    file: Option<String>,
    stdin: bool,
) -> Result<Option<String>, String> {
    if let Some(inline) = inline {
        return Ok(Some(inline));
    }
    if let Some(path) = file {
        return std::fs::read_to_string(path)
            .map(Some)
            .map_err(|error| format!("could not read body file: {error}"));
    }
    if stdin {
        let mut body = String::new();
        std::io::stdin()
            .read_to_string(&mut body)
            .map_err(|error| format!("could not read body from stdin: {error}"))?;
        return Ok(Some(body));
    }
    Ok(None)
}

fn dispatch_context_token(runtime: &RuntimeDirArgs, handle: &str) -> Option<String> {
    let path = std::env::var_os("ALERA_DISPATCH_CONTEXT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            let safe_handle: String = handle
                .chars()
                .map(|value| {
                    if value.is_ascii_alphanumeric() || value == '-' || value == '_' {
                        value
                    } else {
                        '_'
                    }
                })
                .collect();
            crate::runtime_dir(runtime)
                .join("orchestration-contexts")
                .join(format!("{safe_handle}.json"))
        });
    let value: Value = serde_json::from_slice(&std::fs::read(path).ok()?).ok()?;
    value
        .get("token")
        .and_then(Value::as_str)
        .map(str::to_string)
}

/// Structured payload flags exist because raw JSON in `--payload` is fragile
/// under Windows PowerShell quoting; the CLI assembles the JSON itself.
pub(super) fn build_structured_payload(
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
    insert_opt(&mut payload, "taskId", task_id);
    insert_opt(&mut payload, "dispatchId", dispatch_id);
    if let Some(files) = files_modified {
        payload.insert("filesModified".to_string(), json!(csv(&files)));
    }
    insert_opt(&mut payload, "reportPath", report_path);
    insert_opt(&mut payload, "phase", phase);
    if payload.is_empty() {
        return Ok(None);
    }
    Ok(Some(Value::Object(payload).to_string()))
}

pub(super) fn csv(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .collect()
}

pub(super) async fn check(
    runtime: &RuntimeDirArgs,
    args: OrchestrationCheckArgs,
    json_output: bool,
) -> i32 {
    let Some(terminal) = args.terminal.or_else(terminal_handle_env) else {
        return usage_error(
            "--terminal is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set).",
        );
    };
    let types = args.types.as_deref().map(csv).unwrap_or_default();
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
    insert_opt(&mut payload, "limit", args.limit);
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

pub(super) async fn ask(
    runtime: &RuntimeDirArgs,
    args: OrchestrationAskArgs,
    json_output: bool,
) -> i32 {
    let Some(from) = args.from.or_else(terminal_handle_env) else {
        return usage_error(
            "--from is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set).",
        );
    };
    if args.to.starts_with('@') {
        return usage_error("ask requires a single terminal handle, not a group address.");
    }
    let timeout_ms = args.timeout_ms.unwrap_or(DEFAULT_WAIT_TIMEOUT_MS);
    let context_token = dispatch_context_token(runtime, &from);
    let mut payload = json!({
        "from": from,
        "to": args.to,
        "question": args.question,
        "options": args.options,
        "timeoutMs": timeout_ms,
        "wait": !args.no_wait,
    });
    if let Some(token) = context_token {
        payload["contextToken"] = json!(token);
    }
    if let Some(delivery) = args.delivery.as_deref() {
        payload["delivery"] = json!(wire_delivery(delivery));
    }
    let deadline = (!args.no_wait).then_some(timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS));
    let value = match request_value(runtime, "orchestration.ask", payload, deadline).await {
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
    } else if let Some(question_id) = value.get("questionId").and_then(Value::as_str) {
        println!("{question_id}");
    } else if answered {
        let body = value
            .get("reply")
            .and_then(|reply| reply.get("body"))
            .and_then(Value::as_str)
            .unwrap_or("");
        println!("{body}");
    } else {
        println!("timeout");
    }
    0
}

/// The CLI spells it `turn-end`; the wire value is `turnEnd`.
pub(crate) fn wire_delivery(value: &str) -> String {
    match value {
        "turn-end" => "turnEnd".to_string(),
        other => other.to_string(),
    }
}

/// Only `--summary` is required; flags that were not passed stay out of the
/// result so the host applies its defaults.
pub(super) fn completion_result(args: OrchestrationCompleteArgs) -> Result<Value, String> {
    let mut result = Map::new();
    result.insert("summary".to_string(), json!(args.summary));
    insert_opt(&mut result, "completionKind", args.kind);
    if let Some(raw) = args.artifacts {
        let artifacts: Value = serde_json::from_str(&raw)
            .map_err(|_| "--artifacts must be valid JSON.".to_string())?;
        result.insert("artifacts".to_string(), artifacts);
    }
    if let Some(raw) = args.files {
        result.insert("filesModified".to_string(), json!(csv(&raw)));
    }
    if let Some(raw) = args.validation {
        let validation: Value = serde_json::from_str(&raw)
            .map_err(|_| "--validation must be valid JSON.".to_string())?;
        result.insert("validation".to_string(), validation);
    }
    let mut result = Value::Object(result);
    merge_result_extra(&mut result, args.result_extra.as_deref())?;
    Ok(result)
}

pub(super) fn merge_result_extra(result: &mut Value, raw: Option<&str>) -> Result<(), String> {
    let Some(raw) = raw else {
        return Ok(());
    };
    let extra = serde_json::from_str::<Map<String, Value>>(raw)
        .map_err(|_| "--result-extra must be a valid JSON object.".to_string())?;
    let result = result
        .as_object_mut()
        .ok_or_else(|| "completion result must be a JSON object.".to_string())?;
    result.extend(extra);
    Ok(())
}
