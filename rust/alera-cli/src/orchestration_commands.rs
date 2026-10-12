use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::{
    OrchestrationAction, OrchestrationCommand, OrchestrationTerminalAction,
};
use crate::orchestration_command_summaries::human_summary;
use crate::orchestration_terminal_commands::run_terminal_wait;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
};

pub(crate) use worker::{read_body, wire_delivery};

const USAGE_EXIT_CODE: i32 = 64;
/// Grace added to the server-side wait deadline so the client outlives it.
pub(crate) const WAIT_CLIENT_GRACE_MS: u64 = 5_000;

pub async fn run_orchestration_command(command: OrchestrationCommand) -> i32 {
    let runtime = command.runtime;
    let json_output = command.output.json;
    let mut action = command.action;
    let workspace = match &mut action {
        OrchestrationAction::Terminal(OrchestrationTerminalAction::List(args)) => {
            Some(&mut args.workspace)
        }
        OrchestrationAction::Terminal(OrchestrationTerminalAction::Prune(args)) => {
            Some(&mut args.workspace)
        }
        _ => None,
    };
    if let Some(workspace) = workspace {
        match crate::workspace_context::resolve_requested_workspace_id(
            &runtime,
            workspace.as_deref(),
        )
        .await
        {
            Ok(resolved) => *workspace = resolved,
            Err(error) => return crate::print_error(error),
        }
    }
    match action {
        OrchestrationAction::Delegate(args) => {
            crate::orchestration_delegate::run(&runtime, *args, json_output).await
        }
        OrchestrationAction::Run(action) => runs::run(&runtime, action, json_output).await,
        OrchestrationAction::Plan(action) => runs::plan(&runtime, action, json_output).await,
        OrchestrationAction::Gate(action) => runs::gate(&runtime, action, json_output).await,
        OrchestrationAction::Recipe(action) => {
            crate::run_recipe_commands::run_recipes(&runtime, action, json_output).await
        }
        OrchestrationAction::Context => worker::context(&runtime, json_output).await,
        OrchestrationAction::Complete(args) => worker::complete(&runtime, args, json_output).await,
        OrchestrationAction::Escalate(args) => worker::escalate(&runtime, args, json_output).await,
        OrchestrationAction::Ask(args) => worker::ask(&runtime, args, json_output).await,
        OrchestrationAction::Reply(args) => worker::reply(&runtime, args, json_output).await,
        OrchestrationAction::Send(args) => worker::send(&runtime, args, json_output).await,
        OrchestrationAction::Check(args) => worker::check(&runtime, args, json_output).await,
        OrchestrationAction::Messages(args) => worker::messages(&runtime, args, json_output).await,
        OrchestrationAction::Task(action) => tasks::task(&runtime, action, json_output).await,
        OrchestrationAction::Dispatch(action) => {
            tasks::dispatch(&runtime, action, json_output).await
        }
        OrchestrationAction::TransferCoordinator(args) => {
            tasks::transfer_coordinator(&runtime, args, json_output).await
        }
        OrchestrationAction::Terminal(action) => terminal(&runtime, action, json_output).await,
        // Read-only on purpose: a coordinator discovers what it may delegate
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
        OrchestrationAction::Current => current(&runtime, json_output).await,
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

async fn terminal(
    runtime: &RuntimeDirArgs,
    action: OrchestrationTerminalAction,
    json_output: bool,
) -> i32 {
    let (verb, payload) = match action {
        OrchestrationTerminalAction::Wait(args) => {
            return run_terminal_wait(
                runtime,
                &args.terminal,
                &args.target,
                args.timeout_ms,
                json_output,
                false,
            )
            .await;
        }
        OrchestrationTerminalAction::List(args) => (
            "orchestration.terminals",
            json!({ "workspace": args.workspace.or_else(workspace_id_env) }),
        ),
        OrchestrationTerminalAction::Show(args) => (
            "orchestration.terminalShow",
            json!({ "handle": args.handle }),
        ),
        OrchestrationTerminalAction::Prune(args) => (
            "orchestration.terminalPrune",
            json!({
                "workspace": args.workspace.or_else(workspace_id_env),
                "apply": args.apply,
            }),
        ),
    };
    request_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
        verb,
        payload,
        json_output,
        None,
    )
    .await
}

async fn current(runtime: &RuntimeDirArgs, json_output: bool) -> i32 {
    let workspace =
        match crate::workspace_context::resolve_requested_workspace_id(runtime, None).await {
            Ok(workspace) => workspace,
            Err(error) => return crate::print_error(error),
        };
    let value = json!({
        "workspaceId": workspace,
        "terminalHandle": terminal_handle_env(),
    });
    if json_output {
        print_pretty(&value);
    } else {
        println!(
            "workspace={} terminal={}",
            value["workspaceId"].as_str().unwrap_or("unavailable"),
            value["terminalHandle"].as_str().unwrap_or("unavailable")
        );
    }
    0
}

fn print_pretty(value: &Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
    );
}

/// Prints a host answer as JSON or as its one-line summary.
fn print_result(request_type: &str, result: anyhow::Result<Value>, json_output: bool) -> i32 {
    match result {
        Ok(value) => {
            if json_output {
                print_pretty(&value);
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

async fn request(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    payload: Value,
    json_output: bool,
    deadline_ms: Option<u64>,
) -> i32 {
    let result = request_value(runtime, request_type, payload, deadline_ms).await;
    print_result(request_type, result, json_output)
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

/// Connects to a host that advertises `required_capability`. A live host
/// without it answers with the standard "restart Alera" error.
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
    let result = request_value_with_capability(
        runtime,
        required_capability,
        request_type,
        payload,
        deadline_ms,
    )
    .await;
    print_result(request_type, result, json_output)
}

fn insert_opt<T: Into<Value>>(
    payload: &mut serde_json::Map<String, Value>,
    key: &str,
    value: Option<T>,
) {
    if let Some(value) = value {
        payload.insert(key.to_string(), value.into());
    }
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

mod run_cleanup;
mod runs;
mod tasks;
#[cfg(test)]
mod tests;
mod worker;
