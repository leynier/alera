use alera_core::runtime::{
    RuntimeAgentStatusHookSettings, RuntimeStore, RUNTIME_DATABASE_FILE_NAME,
};
use serde_json::{json, Value};

use crate::agent_status::reconcile_agent_integrations;
use crate::cli::{
    RuntimeAction, RuntimeAgentsAction, RuntimeAgentsChangeArgs, RuntimeCommand, RuntimeDirArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;

use super::{open_store, print_error, print_value, runtime_dir};

pub(crate) async fn run_runtime_command(command: RuntimeCommand) -> i32 {
    match command.action {
        RuntimeAction::Status => {
            let runtime_dir = runtime_dir(&command.runtime);
            let store = match open_store(&command.runtime).await {
                Ok(store) => store,
                Err(error) => return print_error(error),
            };
            let host = match RuntimeHostRpcClient::connect(&runtime_dir).await {
                Ok(Some(mut client)) => client.request_value("status.get", &json!({})).await.ok(),
                Ok(None) | Err(_) => None,
            };
            let message = match &host {
                Some(status) => {
                    let sessions = status
                        .get("activeSessions")
                        .and_then(Value::as_u64)
                        .unwrap_or(0);
                    format!("runtime host running ({sessions} active session(s))")
                }
                None => "runtime host not running".to_string(),
            };
            let payload = json!({
                "runtimeDir": runtime_dir.display().to_string(),
                "database": runtime_dir.join(RUNTIME_DATABASE_FILE_NAME).display().to_string(),
                "status": "ok",
                "running": host.is_some(),
                "host": host,
                "agentStatusHooks": store.agent_status_hook_settings().await.unwrap_or_default(),
            });
            print_value(&payload, command.output.json, &message);
            0
        }
        RuntimeAction::Start => {
            let runtime_dir = runtime_dir(&command.runtime);
            let mut client =
                match RuntimeHostRpcClient::connect_or_start_persistent(&runtime_dir).await {
                    Ok(client) => client,
                    Err(error) => return print_error(error),
                };
            match client.request_value("status.get", &json!({})).await {
                Ok(status) => print_value(&status, command.output.json, "runtime host started"),
                Err(error) => return print_error(error),
            }
            0
        }
        RuntimeAction::Stop(args) => {
            let runtime_dir = runtime_dir(&command.runtime);
            let Some(mut client) = (match RuntimeHostRpcClient::connect(&runtime_dir).await {
                Ok(client) => client,
                Err(error) => return print_error(error),
            }) else {
                print_value(
                    &json!({ "running": false, "stopped": false }),
                    command.output.json,
                    "no runtime host is running",
                );
                return 0;
            };
            match client
                .request_value("host.shutdown", &json!({ "force": args.force }))
                .await
            {
                Ok(value) => print_value(&value, command.output.json, "runtime host stopped"),
                Err(error) => return print_error(error),
            }
            0
        }
        RuntimeAction::Agents(agents) => {
            run_runtime_agents_command(&command.runtime, command.output.json, agents.action).await
        }
    }
}

async fn run_runtime_agents_command(
    runtime: &RuntimeDirArgs,
    json_output: bool,
    action: RuntimeAgentsAction,
) -> i32 {
    let store = match open_store(runtime).await {
        Ok(store) => store,
        Err(error) => return print_error(error),
    };
    let mut settings = match store.agent_status_hook_settings().await {
        Ok(settings) => settings,
        Err(error) => return print_error(error),
    };
    match action {
        RuntimeAgentsAction::Status => {
            print_value(&settings, json_output, "runtime agent integrations ready");
            0
        }
        RuntimeAgentsAction::Enable(args) => {
            update_runtime_agents(runtime, json_output, &store, &mut settings, args, true).await
        }
        RuntimeAgentsAction::Disable(args) => {
            update_runtime_agents(runtime, json_output, &store, &mut settings, args, false).await
        }
    }
}

async fn update_runtime_agents(
    runtime: &RuntimeDirArgs,
    json_output: bool,
    store: &RuntimeStore,
    settings: &mut RuntimeAgentStatusHookSettings,
    args: RuntimeAgentsChangeArgs,
    enabled: bool,
) -> i32 {
    const SUPPORTED_AGENTS: [&str; 10] = [
        "codex", "claude", "copilot", "cursor", "agy", "opencode", "opencode2", "pi", "amp", "grok",
    ];
    let agents = if args.all {
        SUPPORTED_AGENTS
            .iter()
            .map(|agent| (*agent).to_string())
            .collect()
    } else {
        args.agents
    };
    for agent in &agents {
        if !settings.set_enabled(agent, enabled) {
            return print_error(format!(
                "Unsupported agent: {agent}. Expected one of: {}.",
                SUPPORTED_AGENTS.join(", ")
            ));
        }
    }
    let runtime_dir = runtime_dir(runtime);
    let integration_warnings = reconcile_agent_integrations(&runtime_dir, settings);
    let value = match RuntimeHostRpcClient::connect(&runtime_dir).await {
        Ok(Some(mut client)) => {
            client
                .request_value(
                    "runtimeSettings.update",
                    &json!({ "agentStatusHooks": settings }),
                )
                .await
        }
        Ok(None) => store
            .set_agent_status_hook_settings(settings)
            .await
            .map(|settings| serde_json::to_value(settings).unwrap_or(Value::Null)),
        Err(error) => Err(error),
    };
    match value {
        Ok(value) => {
            print_value(&value, json_output, "runtime agent integrations updated");
            if integration_warnings.is_empty() {
                0
            } else {
                for warning in integration_warnings {
                    eprintln!("{warning}");
                }
                1
            }
        }
        Err(error) => print_error(error),
    }
}
