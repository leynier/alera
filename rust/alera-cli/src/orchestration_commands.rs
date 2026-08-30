use serde_json::{json, Map, Value};
use std::io::Read;

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    OrchestrationAction, OrchestrationAskArgs, OrchestrationCheckArgs, OrchestrationCommand,
    OrchestrationSendArgs,
};
use crate::orchestration_command_summaries::human_summary;
#[cfg(test)]
use crate::orchestration_terminal_commands::terminal_startup_error;
use crate::orchestration_terminal_commands::{run_agent_spawn, run_terminal_wait};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_AGENT_PROFILES_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_RUN_POLICY_CAPABILITY;

const USAGE_EXIT_CODE: i32 = 64;
/// Grace added to the server-side wait deadline so the client outlives it.
pub(crate) const WAIT_CLIENT_GRACE_MS: u64 = 5_000;
const DEFAULT_WAIT_TIMEOUT_MS: u64 = 120_000;

const LIFECYCLE_TYPES: &[&str] = &["worker_done", "heartbeat"];

pub async fn run_orchestration_command(command: OrchestrationCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    match command.action {
        OrchestrationAction::Recipes(args) => {
            crate::workflow_recipe_commands::run_workflow_recipes(&runtime, args, json_output).await
        }
        OrchestrationAction::AgentSpawn(args) => run_agent_spawn(&runtime, args, json_output).await,
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
            payload.insert("direction".to_string(), json!(args.direction));
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
            let contract_fields = match crate::orchestration_contract_commands::contract_fields(
                args.role_contract.as_deref(),
                args.contract_inputs.as_deref(),
            ) {
                Ok(fields) => fields,
                Err(error) => return usage_error(&error.to_string()),
            };
            let deps: Vec<String> = match args.deps.as_deref() {
                None => Vec::new(),
                Some(raw) => match serde_json::from_str(raw) {
                    Ok(deps) => deps,
                    Err(_) => return usage_error("--deps must be a JSON array of task ids."),
                },
            };
            let created_by = terminal_handle_env();
            let coordinator = args.coordinator.or_else(|| created_by.clone());
            let Some(workspace) = args.workspace.or_else(workspace_id_env) else {
                return usage_error(
                    "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).",
                );
            };
            request(
                &runtime,
                if contract_fields.is_some() {
                    "orchestration.taskCreateContracted"
                } else {
                    "orchestration.taskCreate"
                },
                crate::orchestration_contract_commands::with_contract_fields(
                    json!({
                        "spec": args.spec,
                        "taskTitle": args.task_title,
                        "deps": deps,
                        "parent": args.parent,
                        "createdBy": created_by,
                        "coordinator": coordinator,
                        "workspace": workspace,
                        "run": args.run,
                        "stage": args.stage,
                        "resultSchema": args.result_schema,
                    }),
                    contract_fields,
                ),
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
            insert_opt(&mut payload, "run", args.run);
            insert_opt(&mut payload, "workspace", args.workspace);
            request(
                &runtime,
                "orchestration.taskList",
                Value::Object(payload),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TaskShow(args) => {
            request(
                &runtime,
                "orchestration.taskShow",
                json!({ "id": args.id }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TaskWait(args) => {
            let targets = comma_separated_values(&args.targets);
            request_with_capability(
                &runtime,
                RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
                "orchestration.taskWait",
                json!({
                    "task": args.task,
                    "targets": targets,
                    "timeoutMs": args.timeout_ms,
                }),
                json_output,
                Some(args.timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
            )
            .await
        }
        OrchestrationAction::TaskCancel(args) => {
            request(
                &runtime,
                "orchestration.taskCancel",
                json!({
                    "id": args.id,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TaskRecover(args) => {
            request(
                &runtime,
                "orchestration.taskRecover",
                json!({
                    "id": args.id,
                    "status": args.status,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TransferCoordinator(args) => {
            request(
                &runtime,
                "orchestration.transferCoordinator",
                json!({
                    "task": args.task,
                    "run": args.run,
                    "to": args.to,
                    "reason": args.reason,
                    "force": args.force,
                    "actor": terminal_handle_env(),
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Dispatch(args) => {
            let required_capability = dispatch_required_capability(args.assume_agent.as_deref());
            let Some(from) = args.from.or_else(terminal_handle_env) else {
                return usage_error(
                    "--from is required (or set ALERA_TERMINAL_HANDLE) so the preamble can name the coordinator.",
                );
            };
            request_with_capability(
                &runtime,
                required_capability,
                "orchestration.dispatch",
                json!({
                    "task": args.task,
                    "to": args.to,
                    "from": from,
                    "inject": args.inject,
                    "assumeAgent": args.assume_agent,
                    "dryRun": args.dry_run,
                    "returnPreamble": args.return_preamble,
                    "allowSelfDispatch": args.allow_self_dispatch,
                    "completionPolicy": args.completion_policy,
                    "terminalPolicy": args.terminal_policy,
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
        OrchestrationAction::DispatchAccept => {
            let terminal = terminal_handle_env();
            let context_token = terminal
                .as_deref()
                .and_then(|handle| dispatch_context_token(&runtime, handle));
            request(
                &runtime,
                "orchestration.dispatchAccept",
                json!({ "terminal": terminal, "contextToken": context_token }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::DispatchInterrupt(args) => {
            request(
                &runtime,
                "orchestration.dispatchInterrupt",
                json!({
                    "id": args.id,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Context => {
            let terminal = terminal_handle_env();
            let context_token = terminal
                .as_deref()
                .and_then(|handle| dispatch_context_token(&runtime, handle));
            request(
                &runtime,
                "orchestration.context",
                json!({ "terminal": terminal, "contextToken": context_token }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Heartbeat(args) => {
            let terminal = terminal_handle_env();
            let context_token = terminal
                .as_deref()
                .and_then(|handle| dispatch_context_token(&runtime, handle));
            request(
                &runtime,
                "orchestration.heartbeat",
                json!({ "terminal": terminal, "contextToken": context_token, "phase": args.phase }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Escalate(args) => {
            let body = match read_body(args.body, args.body_file, args.body_stdin) {
                Ok(body) => body,
                Err(error) => return usage_error(&error),
            };
            let terminal = terminal_handle_env();
            let context_token = terminal
                .as_deref()
                .and_then(|handle| dispatch_context_token(&runtime, handle));
            request(
                &runtime,
                "orchestration.escalate",
                json!({ "terminal": terminal, "contextToken": context_token, "subject": args.subject, "body": body }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Complete(args) => {
            let artifacts: Value = match args.artifacts {
                Some(raw) => match serde_json::from_str(&raw) {
                    Ok(value) => value,
                    Err(_) => return usage_error("--artifacts must be valid JSON."),
                },
                None => json!([]),
            };
            let validation: Value = match args.validation {
                Some(raw) => match serde_json::from_str(&raw) {
                    Ok(value) => value,
                    Err(_) => return usage_error("--validation must be valid JSON."),
                },
                None => json!([]),
            };
            let files_modified: Vec<String> = args
                .files_modified
                .as_deref()
                .map(|raw| {
                    raw.split(',')
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default();
            let mut result = json!({
                "summary": args.summary,
                "completionKind": args.completion_kind,
                "artifacts": artifacts,
                "filesModified": files_modified,
                "validation": validation,
            });
            if let Err(error) = merge_result_extra(&mut result, args.result_extra.as_deref()) {
                return usage_error(&error);
            }
            let terminal = terminal_handle_env();
            let context_token = terminal
                .as_deref()
                .and_then(|handle| dispatch_context_token(&runtime, handle));
            request(
                &runtime,
                "orchestration.complete",
                json!({
                    "terminal": terminal,
                    "contextToken": context_token,
                    "result": result
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::WorkerDone(args) => {
            let mut result = json!({
                "summary": args.summary,
                "completionKind": "success",
                "artifacts": [],
                "filesModified": [],
                "validation": [],
            });
            if let Err(error) = merge_result_extra(&mut result, args.result_extra.as_deref()) {
                return usage_error(&error);
            }
            request(
                &runtime,
                "orchestration.workerDone",
                json!({
                    "terminal": terminal_handle_env(),
                    "task": args.task,
                    "dispatch": args.dispatch,
                    "result": result
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::WorkerHelp => {
            request(
                &runtime,
                "orchestration.workerHelp",
                json!({}),
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
        // Read-only on purpose: a coordinator discovers what it may dispatch
        // to, but only the user adds or edits profiles, so the orchestrator
        // picks from a closed list instead of inventing launch commands.
        OrchestrationAction::AgentProfiles => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
                "agentProfile.list",
                json!({}),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunPolicyPropose(args) => {
            let policy = match read_policy_document(&args.policy_file) {
                Ok(policy) => policy,
                Err(message) => return usage_error(&message),
            };
            request_with_capability(
                &runtime,
                RUNTIME_HOST_RUN_POLICY_CAPABILITY,
                "orchestration.runPolicyPropose",
                json!({ "run": args.run, "policy": policy }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunPolicyShow(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_RUN_POLICY_CAPABILITY,
                "orchestration.runPolicyShow",
                json!({ "run": args.run }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunPolicyApprove(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_RUN_POLICY_CAPABILITY,
                "orchestration.runPolicyApprove",
                json!({ "run": args.run, "actor": terminal_handle_env() }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunPolicyReject(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_RUN_POLICY_CAPABILITY,
                "orchestration.runPolicyReject",
                json!({
                    "run": args.run,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                }),
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
            let Some(workspace) = args.workspace.or_else(workspace_id_env) else {
                return usage_error(
                    "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).",
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
                    "workspace": workspace,
                    "agent": args.agent,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunList(args) => {
            request(
                &runtime,
                "orchestration.runList",
                json!({ "workspace": args.workspace }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunShow(args) => {
            request(
                &runtime,
                "orchestration.runShow",
                json!({ "id": args.id }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Status(args) => {
            request(
                &runtime,
                "orchestration.status",
                json!({ "id": args.id }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::RunStop(args) => {
            request(
                &runtime,
                "orchestration.runStop",
                json!({
                    "id": args.id,
                    "cancelActive": args.cancel_active,
                    "reason": args.reason,
                    "actor": terminal_handle_env(),
                    "force": args.force,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TerminalList(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
                "orchestration.terminals",
                json!({ "workspace": args.workspace.or_else(workspace_id_env) }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TerminalShow(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
                "orchestration.terminalShow",
                json!({ "handle": args.handle }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::TerminalWait(args) => {
            run_terminal_wait(
                &runtime,
                &args.terminal,
                &args.target,
                args.timeout_ms,
                json_output,
                false,
            )
            .await
        }
        OrchestrationAction::TerminalPrune(args) => {
            request_with_capability(
                &runtime,
                RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
                "orchestration.terminalPrune",
                json!({
                    "workspace": args.workspace.or_else(workspace_id_env),
                    "apply": args.apply,
                }),
                json_output,
                None,
            )
            .await
        }
        OrchestrationAction::Current => {
            let value = json!({
                "workspaceId": workspace_id_env(),
                "terminalHandle": terminal_handle_env(),
            });
            if json_output {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string())
                );
            } else {
                println!(
                    "workspace={} terminal={}",
                    value["workspaceId"].as_str().unwrap_or("unavailable"),
                    value["terminalHandle"].as_str().unwrap_or("unavailable")
                );
            }
            0
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

fn dispatch_required_capability(assume_agent: Option<&str>) -> &'static str {
    if assume_agent.is_some() {
        RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY
    } else {
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY
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
    Ok(Value::Object(payload))
}

fn comma_separated_values(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .collect()
}

/// Reads and parses a policy document from a path, or from stdin when the path
/// is `-`. Parsed here so a malformed file is a usage error instead of a round
/// trip to the host.
fn read_policy_document(path: &str) -> Result<Value, String> {
    let raw = if path == "-" {
        let mut buffer = String::new();
        std::io::stdin()
            .read_to_string(&mut buffer)
            .map_err(|error| format!("could not read policy from stdin: {error}"))?;
        buffer
    } else {
        std::fs::read_to_string(path)
            .map_err(|error| format!("could not read policy file: {error}"))?
    };
    serde_json::from_str(&raw).map_err(|error| format!("policy file is not valid JSON: {error}"))
}

fn read_body(
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
    } else if !json_output {
        println!("timeout");
    }
    0
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

pub(crate) async fn request_value(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: Value,
    deadline_ms: Option<u64>,
) -> anyhow::Result<Value> {
    request_value_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
        request_type,
        payload,
        deadline_ms,
    )
    .await
}

pub(crate) async fn request_value_with_capability(
    runtime: &RuntimeDirArgs,
    required_capability: &str,
    request_type: &str,
    payload: Value,
    deadline_ms: Option<u64>,
) -> anyhow::Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        required_capability,
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

async fn request_with_capability(
    runtime: &RuntimeDirArgs,
    required_capability: &str,
    request_type: &str,
    payload: Value,
    json_output: bool,
    deadline_ms: Option<u64>,
) -> i32 {
    match request_value_with_capability(
        runtime,
        required_capability,
        request_type,
        payload,
        deadline_ms,
    )
    .await
    {
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

fn insert_opt(payload: &mut Map<String, Value>, key: &str, value: Option<String>) {
    if let Some(value) = value {
        payload.insert(key.to_string(), json!(value));
    }
}

fn merge_result_extra(result: &mut Value, raw: Option<&str>) -> Result<(), String> {
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

pub(crate) fn terminal_handle_env() -> Option<String> {
    std::env::var("ALERA_TERMINAL_HANDLE")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

pub(crate) fn workspace_id_env() -> Option<String> {
    std::env::var("ALERA_WORKSPACE_ID")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

pub(crate) fn usage_error(message: &str) -> i32 {
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
    fn dispatch_requires_override_capability_only_when_assuming_an_agent() {
        assert_eq!(
            dispatch_required_capability(None),
            RUNTIME_HOST_ORCHESTRATION_CAPABILITY
        );
        assert_eq!(
            dispatch_required_capability(Some("codex")),
            RUNTIME_HOST_ORCHESTRATION_ASSUME_AGENT_CAPABILITY
        );
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

    #[test]
    fn terminal_startup_failure_is_detected_without_waiting_for_timeout() {
        assert_eq!(
            terminal_startup_error(&json!({
                "startupState": "failed",
                "startupError": "agent exited"
            })),
            Some("agent exited")
        );
        assert_eq!(
            terminal_startup_error(&json!({"startupState": "process_started"})),
            None
        );
    }

    #[test]
    fn result_extra_adds_schema_defined_completion_fields() {
        let mut result = json!({
            "summary": "done",
            "completionKind": "success",
            "artifacts": [],
            "filesModified": [],
            "validation": []
        });
        merge_result_extra(&mut result, Some(r#"{"ticket":42}"#)).unwrap();
        assert_eq!(result["ticket"], json!(42));
        assert!(merge_result_extra(&mut result, Some("[]")).is_err());
    }
}
