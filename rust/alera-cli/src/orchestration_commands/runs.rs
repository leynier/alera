//! `run`, `plan`, and `gate` over the `runs.*` verbs, plus the coordinator's
//! `orchestration.planContext`, `planPropose`, and `gateCreate`. Every `runs.*`
//! command needs a host that advertises `runsV1`.

use std::io::Read;

use alera_core::runtime::AgentProfile;
use serde_json::{json, Map, Value};

use crate::agent_profile_commands::{list_profiles, select_profile};
use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    GateAction, PlanAction, RunAction, RunControlArgs, RunNewArgs, RunRetryArgs,
};
use crate::mcp_tools::CallOrigin;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_RUNS_CAPABILITY;

use super::{
    insert_opt, print_result, request, request_value_with_capability, terminal_handle_env,
    usage_error,
};

pub(super) async fn run(runtime: &RuntimeDirArgs, action: RunAction, json: bool) -> i32 {
    let (verb, payload) = match action {
        RunAction::New(args) => return run_new(runtime, args, json).await,
        RunAction::List(args) => {
            let cursor = match parse_cursor(args.cursor.as_deref()) {
                Ok(cursor) => cursor,
                Err(message) => return usage_error(&message),
            };
            let mut payload = Map::new();
            insert_opt(&mut payload, "projectId", args.project_id);
            insert_opt(&mut payload, "workspaceId", args.workspace);
            insert_opt(&mut payload, "search", args.search);
            insert_opt(&mut payload, "bucket", args.bucket);
            insert_opt(&mut payload, "cursor", cursor);
            insert_opt(&mut payload, "limit", args.limit);
            ("runs.board", payload)
        }
        RunAction::Show(args) => {
            let mut payload = run_payload(&args.run);
            insert_opt(&mut payload, "afterTaskId", args.after_task);
            insert_opt(&mut payload, "revision", args.revision);
            insert_opt(&mut payload, "limit", args.limit);
            ("runs.snapshot", payload)
        }
        RunAction::Timeline(args) => {
            let mut payload = run_payload(&args.run);
            insert_opt(&mut payload, "taskId", args.task);
            insert_opt(&mut payload, "cursor", args.cursor);
            insert_opt(&mut payload, "limit", args.limit);
            if !args.kinds.is_empty() {
                payload.insert("kinds".into(), json!(args.kinds));
            }
            ("runs.timeline", payload)
        }
        RunAction::Cancel(args) => return control(runtime, "cancel", args, json).await,
        RunAction::Pause(args) => return control(runtime, "pause", args, json).await,
        RunAction::Resume(args) => return control(runtime, "resume", args, json).await,
        RunAction::Replan(args) => {
            let control_args = RunControlArgs {
                run: args.run,
                reason: Some(args.reason),
                expected_sequence: args.expected_sequence,
            };
            return control_with_tasks(runtime, "replan", control_args, args.tasks, json).await;
        }
        RunAction::Retry(args) => return retry(runtime, args, json).await,
        RunAction::Resources(args) => {
            let mut payload = run_payload(&args.run);
            insert_opt(&mut payload, "beforeRow", args.before_row);
            ("runs.resources", payload)
        }
        RunAction::Integrations(args) => {
            let mut payload = run_payload(&args.run);
            insert_opt(&mut payload, "afterRow", args.after_row);
            ("runs.integrations", payload)
        }
        RunAction::Cleanup(action) => match super::run_cleanup::cleanup_request(action) {
            Ok(request) => request,
            Err(message) => return usage_error(&message),
        },
    };
    runs_request(runtime, verb, Value::Object(payload), json).await
}

pub(super) async fn plan(runtime: &RuntimeDirArgs, action: PlanAction, json: bool) -> i32 {
    match action {
        PlanAction::Context(args) => {
            request(
                runtime,
                "orchestration.planContext",
                json!({ "run": args.run }),
                json,
                None,
            )
            .await
        }
        PlanAction::Propose(args) => {
            let path = match (args.plan_file.as_deref(), args.stdin) {
                (Some(path), false) => path.to_string(),
                (None, true) => "-".to_string(),
                _ => return usage_error("pass --plan-file <path|-> or --stdin"),
            };
            let plan = match read_plan_document(&path) {
                Ok(plan) => plan,
                Err(message) => return usage_error(&message),
            };
            request(
                runtime,
                "orchestration.planPropose",
                json!({ "run": args.run, "plan": plan, "from": terminal_handle_env() }),
                json,
                None,
            )
            .await
        }
        PlanAction::Show(args) => {
            let mut payload = run_payload(&args.run);
            insert_opt(&mut payload, "revision", args.revision);
            runs_request(runtime, "runs.plan", Value::Object(payload), json).await
        }
    }
}

pub(super) async fn gate(runtime: &RuntimeDirArgs, action: GateAction, json: bool) -> i32 {
    match action {
        GateAction::List(args) => {
            let mut payload = Map::new();
            insert_opt(&mut payload, "kind", args.kind);
            insert_opt(&mut payload, "status", args.status);
            match args.run {
                Some(run) => {
                    payload.insert("runId".into(), json!(run));
                    insert_opt(&mut payload, "taskId", args.task);
                    runs_request(runtime, "runs.gates", Value::Object(payload), json).await
                }
                // Decision gates of tasks delegated outside any run.
                None => {
                    insert_opt(&mut payload, "task", args.task);
                    let payload = Value::Object(payload);
                    request(runtime, "orchestration.gateList", payload, json, None).await
                }
            }
        }
        GateAction::Show(args) => {
            runs_request(runtime, "runs.gate", json!({ "gateId": args.id }), json).await
        }
        GateAction::Resolve(args) => {
            let mut payload = mutation_payload();
            payload.insert("gateId".into(), json!(args.id));
            payload.insert("decision".into(), json!(args.decision));
            insert_opt(&mut payload, "reason", args.reason);
            insert_opt(&mut payload, "expectedEvidenceDigest", args.expected_digest);
            insert_opt(&mut payload, "callerTerminal", terminal_handle_env());
            if !args.tasks.is_empty() {
                payload.insert("taskIds".into(), json!(args.tasks));
            }
            runs_request(runtime, "runs.resolveGate", Value::Object(payload), json).await
        }
        GateAction::Create(args) => {
            let options: Vec<String> = match args.options.as_deref() {
                None => Vec::new(),
                Some(raw) => match serde_json::from_str(raw) {
                    Ok(options) => options,
                    Err(_) => return usage_error("--options must be a JSON array of strings."),
                },
            };
            request(
                runtime,
                "orchestration.gateCreate",
                json!({ "task": args.task, "question": args.question, "options": options }),
                json,
                None,
            )
            .await
        }
    }
}

async fn run_new(runtime: &RuntimeDirArgs, args: RunNewArgs, json: bool) -> i32 {
    match run_new_payload(runtime, args).await {
        Ok(payload) => runs_request(runtime, "runs.create", payload, json).await,
        Err(error) => crate::print_error(error),
    }
}

async fn run_new_payload(runtime: &RuntimeDirArgs, args: RunNewArgs) -> anyhow::Result<Value> {
    let objective = args.spec.read()?;
    let Some(workspace) = crate::workspace_context::resolve_requested_workspace_id(
        runtime,
        args.workspace.as_deref(),
    )
    .await?
    else {
        anyhow::bail!(
            "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
        );
    };
    let recipe = args
        .template
        .as_deref()
        .map(|template| recipe_source(template, &workspace))
        .transpose()
        .map_err(anyhow::Error::msg)?;
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_RUNS_CAPABILITY,
    )
    .await?;
    let (_, profiles) = list_profiles(&mut client).await?;
    let coordinator = select_profile(&profiles, &args.coordinator)?;
    let mut payload = mutation_payload();
    if let Some(key) = args.request_id {
        payload.insert("requestId".into(), json!(key));
    }
    payload.insert("workspaceId".into(), json!(workspace));
    payload.insert("objective".into(), json!(objective));
    payload.insert("isolation".into(), json!(args.isolation));
    payload.insert("coordinatorProfileId".into(), json!(coordinator.id));
    payload.insert("approvalRequired".into(), json!(args.approval));
    insert_opt(&mut payload, "recipeSource", recipe);
    if let Some(worker) = args.worker_profile.as_deref() {
        payload.insert(
            "workerProfileId".into(),
            json!(profile_id(&profiles, worker)?),
        );
    }
    let mut roles = Map::new();
    for binding in &args.role_profiles {
        let Some((role, profile)) = binding.split_once('=') else {
            anyhow::bail!("--role-profile takes role=profile, got {binding}");
        };
        roles.insert(
            role.trim().to_string(),
            json!(profile_id(&profiles, profile)?),
        );
    }
    if !roles.is_empty() {
        payload.insert("roleProfiles".into(), Value::Object(roles));
    }
    insert_opt(&mut payload, "maxConcurrent", args.max_concurrent);
    insert_opt(&mut payload, "stallPolicy", args.stall_policy);
    Ok(Value::Object(payload))
}

/// A profile by stable id or by unique name, matched case-insensitively.
fn profile_id(profiles: &[AgentProfile], wanted: &str) -> anyhow::Result<String> {
    let wanted = wanted.trim();
    profiles
        .iter()
        .find(|profile| profile.id == wanted)
        .or_else(|| {
            profiles
                .iter()
                .find(|profile| profile.name.eq_ignore_ascii_case(wanted))
        })
        .map(|profile| profile.id.clone())
        .ok_or_else(|| anyhow::anyhow!("agent profile not found: {wanted}"))
}

/// `builtIn:<id>`, `personal:<id>`, `project:<path>` (in the run's
/// workspace), or the source JSON `recipe list` prints.
pub(super) fn recipe_source(template: &str, workspace: &str) -> Result<Value, String> {
    let template = template.trim();
    if template.starts_with('{') {
        return serde_json::from_str(template)
            .map_err(|_| "--template is not a valid recipe source JSON.".to_string());
    }
    match template.split_once(':') {
        Some((origin @ ("builtIn" | "personal"), id)) if !id.is_empty() => {
            Ok(json!({ "origin": origin, "id": id }))
        }
        Some(("project", path)) if !path.is_empty() => {
            Ok(json!({ "origin": "project", "workspaceId": workspace, "path": path }))
        }
        _ => Err(
            "--template takes builtIn:<id>, personal:<id>, project:<path>, or a source JSON."
                .to_string(),
        ),
    }
}

async fn control(runtime: &RuntimeDirArgs, action: &str, args: RunControlArgs, json: bool) -> i32 {
    control_with_tasks(runtime, action, args, Vec::new(), json).await
}

async fn control_with_tasks(
    runtime: &RuntimeDirArgs,
    action: &str,
    args: RunControlArgs,
    tasks: Vec<String>,
    json: bool,
) -> i32 {
    let sequence = match expected_sequence(runtime, &args.run, args.expected_sequence).await {
        Ok(sequence) => sequence,
        Err(error) => return crate::print_error(error),
    };
    let mut payload = mutation_payload();
    payload.insert("runId".into(), json!(args.run));
    payload.insert("expectedSequence".into(), json!(sequence));
    payload.insert("action".into(), json!(action));
    insert_opt(&mut payload, "reason", args.reason);
    if !tasks.is_empty() {
        payload.insert("taskIds".into(), json!(tasks));
    }
    runs_request(runtime, "runs.control", Value::Object(payload), json).await
}

async fn retry(runtime: &RuntimeDirArgs, args: RunRetryArgs, json: bool) -> i32 {
    let mut payload = mutation_payload();
    payload.insert("runId".into(), json!(args.run));
    let verb = if let Some(task) = args.task {
        payload.insert("taskId".into(), json!(task));
        "runs.retryTask"
    } else if let Some(task) = args.integration {
        payload.insert("taskId".into(), json!(task));
        "runs.retryIntegration"
    } else {
        let sequence = match expected_sequence(runtime, &args.run, args.expected_sequence).await {
            Ok(sequence) => sequence,
            Err(error) => return crate::print_error(error),
        };
        payload.insert("expectedSequence".into(), json!(sequence));
        "runs.retryCancellation"
    };
    runs_request(runtime, verb, Value::Object(payload), json).await
}

/// Control commands name the run state they act on. A caller that did not
/// pass one acts on the run as it is now.
async fn expected_sequence(
    runtime: &RuntimeDirArgs,
    run: &str,
    explicit: Option<i64>,
) -> anyhow::Result<i64> {
    if let Some(sequence) = explicit {
        return Ok(sequence);
    }
    let snapshot = request_value_with_capability(
        runtime,
        RUNTIME_HOST_RUNS_CAPABILITY,
        "runs.snapshot",
        json!({ "runId": run, "limit": 1 }),
        None,
    )
    .await?;
    snapshot
        .get("controlSequence")
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow::anyhow!("run {run} reported no controlSequence"))
}

fn run_payload(run: &str) -> Map<String, Value> {
    let mut payload = Map::new();
    payload.insert("runId".into(), json!(run));
    payload
}

/// A fresh request id, plus the MCP client behind the command when an MCP
/// tool runs it, so the host records that client as the actor.
fn mutation_payload() -> Map<String, Value> {
    let mut payload = Map::new();
    payload.insert(
        "requestId".into(),
        json!(format!("cli-{}", uuid::Uuid::new_v4())),
    );
    if let Some(origin) = CallOrigin::from_env() {
        payload.insert(
            "externalOrigin".into(),
            crate::inbox_commands::external_origin(&origin),
        );
    }
    payload
}

async fn runs_request(runtime: &RuntimeDirArgs, verb: &str, payload: Value, json: bool) -> i32 {
    let result =
        request_value_with_capability(runtime, RUNTIME_HOST_RUNS_CAPABILITY, verb, payload, None)
            .await;
    print_result(verb, result, json)
}

/// Reads and parses a plan document from a path, or from stdin when the path
/// is `-`. Parsed here so a malformed file is a usage error instead of a round
/// trip to the host.
fn read_plan_document(path: &str) -> Result<Value, String> {
    let raw = if path == "-" {
        let mut buffer = String::new();
        std::io::stdin()
            .read_to_string(&mut buffer)
            .map_err(|error| format!("could not read the plan from stdin: {error}"))?;
        buffer
    } else {
        std::fs::read_to_string(path)
            .map_err(|error| format!("could not read the plan file: {error}"))?
    };
    serde_json::from_str(&raw).map_err(|error| format!("the plan is not valid JSON: {error}"))
}

/// A page cursor is the JSON object a previous page returned.
pub(super) fn parse_cursor(raw: Option<&str>) -> Result<Option<Value>, String> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    match serde_json::from_str::<Value>(raw) {
        Ok(cursor @ Value::Object(_)) => Ok(Some(cursor)),
        _ => Err("--cursor must be the JSON object a previous page returned.".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursors_must_be_json_objects() {
        assert_eq!(parse_cursor(None), Ok(None));
        let cursor = parse_cursor(Some(r#"{"id":"run_1","createdAt":"t","revision":3}"#)).unwrap();
        assert_eq!(cursor.unwrap()["revision"], 3);
        assert!(parse_cursor(Some("run_1")).is_err());
        assert!(parse_cursor(Some("[1]")).is_err());
    }

    #[test]
    fn templates_name_a_recipe_source() {
        assert_eq!(
            recipe_source("builtIn:feature-delivery", "ws").unwrap(),
            json!({"origin": "builtIn", "id": "feature-delivery"})
        );
        assert_eq!(
            recipe_source("personal:quick-fix", "ws").unwrap(),
            json!({"origin": "personal", "id": "quick-fix"})
        );
        assert_eq!(
            recipe_source("project:.alera/workflows/release.yaml", "ws").unwrap(),
            json!({"origin": "project", "workspaceId": "ws", "path": ".alera/workflows/release.yaml"})
        );
        assert_eq!(
            recipe_source(r#"{"origin":"builtIn","id":"freeform"}"#, "ws").unwrap()["id"],
            "freeform"
        );
        assert!(recipe_source("feature-delivery", "ws").is_err());
        assert!(recipe_source("builtIn:", "ws").is_err());
    }
}
