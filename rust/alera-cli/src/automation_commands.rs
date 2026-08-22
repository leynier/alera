use std::collections::BTreeMap;
use std::fs;
use std::io::Read;

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::{json, Value};

use crate::cli::{
    AutomationAction, AutomationCatalogFileArgs, AutomationCommand, AutomationCompleteArgs,
    AutomationDefinitionFileArgs, AutomationExportArgs, AutomationExtendArgs, AutomationImportArgs,
    AutomationListArgs, AutomationPolicyArgs, AutomationRevisionArgs, AutomationRunIdArgs,
    AutomationRunNowArgs, AutomationRunsArgs, AutomationStateArgs, AutomationTargetArgs,
    AutomationWaitArgs, RuntimeDirArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATIONS_CAPABILITY;

pub(crate) async fn run(command: AutomationCommand) -> i32 {
    let AutomationCommand {
        runtime,
        output,
        action,
    } = command;
    let json_output = output.json;
    let result = match action {
        AutomationAction::List(args) => list(&runtime, args).await,
        AutomationAction::Show(args) => {
            request(&runtime, "automation.show", json!({"id": args.id})).await
        }
        AutomationAction::Create(args) => upsert(&runtime, args).await,
        AutomationAction::Edit(args) => upsert(&runtime, args).await,
        AutomationAction::Approve(args) => approve(&runtime, args).await,
        AutomationAction::Pause(args) => state(&runtime, "automation.pause", args).await,
        AutomationAction::Resume(args) => state(&runtime, "automation.resume", args).await,
        AutomationAction::Trash(args) => state(&runtime, "automation.trash", args).await,
        AutomationAction::Restore(args) => state(&runtime, "automation.restore", args).await,
        AutomationAction::Purge => request(&runtime, "automation.purge", json!({})).await,
        AutomationAction::RunNow(args) => run_now(&runtime, args).await,
        AutomationAction::Runs(args) => runs(&runtime, args).await,
        AutomationAction::RunShow(args) => {
            request(&runtime, "automation.runShow", json!({"id": args.id})).await
        }
        AutomationAction::Cancel(args) => lifecycle(&runtime, "automation.cancel", &args).await,
        AutomationAction::Context(args) => lifecycle(&runtime, "automation.context", &args).await,
        AutomationAction::Heartbeat(args) => {
            lifecycle(&runtime, "automation.heartbeat", &args).await
        }
        AutomationAction::Wait(args) => wait(&runtime, args).await,
        AutomationAction::Extend(args) => extend(&runtime, args).await,
        AutomationAction::Complete(args) => complete(&runtime, args).await,
        AutomationAction::Templates(args) => catalog(&runtime, "template", args).await,
        AutomationAction::Tags(args) => catalog(&runtime, "tag", args).await,
        AutomationAction::Import(args) => import_catalog(&runtime, args).await,
        AutomationAction::Export(args) => export_catalog(&runtime, args, json_output).await,
        AutomationAction::Policy(args) => policy(&runtime, args).await,
    };
    match result {
        Ok(value) => {
            crate::print_value(&value, json_output, "automation request completed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn request(runtime: &RuntimeDirArgs, request_type: &str, payload: Value) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    )
    .await?;
    client.request_value(request_type, &payload).await
}

async fn list(runtime: &RuntimeDirArgs, args: AutomationListArgs) -> Result<Value> {
    request(
        runtime,
        "automation.list",
        json!({
            "includeTrashed": args.include_trashed,
            "state": args.state,
            "projectId": args.project_id,
            "profileId": args.profile_id,
            "tag": args.tag,
            "search": args.search,
        }),
    )
    .await
}

async fn upsert(runtime: &RuntimeDirArgs, args: AutomationDefinitionFileArgs) -> Result<Value> {
    let definition = read_json(&args.file)?;
    let mut payload = json!({"automation": definition});
    add_automation_context(&mut payload);
    request(runtime, "automation.upsert", payload).await
}

async fn approve(runtime: &RuntimeDirArgs, args: AutomationRevisionArgs) -> Result<Value> {
    let mut payload = json!({"id": args.id, "revision": args.revision});
    add_automation_context(&mut payload);
    request(runtime, "automation.approve", payload).await
}

async fn state(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    args: AutomationStateArgs,
) -> Result<Value> {
    let mut payload = json!({
        "id": args.id,
        "reason": args.reason,
        "activeRuns": args.active_runs,
    });
    add_automation_context(&mut payload);
    request(runtime, request_type, payload).await
}

async fn run_now(runtime: &RuntimeDirArgs, args: AutomationRunNowArgs) -> Result<Value> {
    let precheck = match (args.precheck, args.skip_precheck) {
        (true, false) => true,
        (false, true) => false,
        _ => anyhow::bail!("Run Now requires exactly one of --precheck or --skip-precheck"),
    };
    let overlap = args
        .overlap
        .ok_or_else(|| anyhow::anyhow!("Run Now requires --overlap"))?;
    let mut payload = json!({
        "id": args.id,
        "precheck": precheck,
        "overlap": overlap,
        "draftTest": args.draft_test,
        "revision": args.revision,
        "targetIdentity": target_identity(&args.target),
    });
    add_automation_context(&mut payload);
    request(runtime, "automation.runNow", payload).await
}

async fn runs(runtime: &RuntimeDirArgs, args: AutomationRunsArgs) -> Result<Value> {
    request(
        runtime,
        "automation.runs",
        json!({"automationId": args.automation_id, "limit": args.limit}),
    )
    .await
}

async fn lifecycle(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    args: &AutomationRunIdArgs,
) -> Result<Value> {
    request(
        runtime,
        request_type,
        json!({"run": args.run_id, "targetIdentity": target_identity(&args.target)}),
    )
    .await
}

async fn wait(runtime: &RuntimeDirArgs, args: AutomationWaitArgs) -> Result<Value> {
    request(
        runtime,
        "automation.wait",
        json!({
            "run": args.run_id,
            "waiting": !args.resume,
            "targetIdentity": target_identity(&args.target),
        }),
    )
    .await
}

async fn extend(runtime: &RuntimeDirArgs, args: AutomationExtendArgs) -> Result<Value> {
    if args.until.is_none() && args.seconds.is_none() {
        anyhow::bail!("waiting extension requires --until or --seconds");
    }
    request(
        runtime,
        "automation.extend",
        json!({
            "run": args.run_id,
            "until": args.until,
            "seconds": args.seconds,
            "targetIdentity": target_identity(&args.target),
        }),
    )
    .await
}

async fn complete(runtime: &RuntimeDirArgs, args: AutomationCompleteArgs) -> Result<Value> {
    request(
        runtime,
        "automation.complete",
        json!({
            "run": args.run_id,
            "status": args.status,
            "summary": args.summary,
            "error": args.error,
            "targetIdentity": target_identity(&args.target),
        }),
    )
    .await
}

async fn catalog(
    runtime: &RuntimeDirArgs,
    kind: &str,
    args: AutomationCatalogFileArgs,
) -> Result<Value> {
    let mut payload = match args.file {
        Some(file) => json!({kind: read_json(&file)?}),
        None => json!({}),
    };
    add_automation_context(&mut payload);
    request(
        runtime,
        if kind == "template" {
            "automation.templates"
        } else {
            "automation.tags"
        },
        payload,
    )
    .await
}

async fn import_catalog(runtime: &RuntimeDirArgs, args: AutomationImportArgs) -> Result<Value> {
    let remap: BTreeMap<String, String> = args.remap.into_iter().collect();
    let mut payload = json!({"bundle": read_json(&args.file)?, "remap": remap});
    add_automation_context(&mut payload);
    request(runtime, "automation.import", payload).await
}

async fn export_catalog(
    runtime: &RuntimeDirArgs,
    args: AutomationExportArgs,
    json_output: bool,
) -> Result<Value> {
    let mut payload = json!({});
    add_automation_context(&mut payload);
    let value = request(runtime, "automation.export", payload).await?;
    if let Some(path) = args.file {
        fs::write(&path, serde_json::to_string_pretty(&value)?)
            .with_context(|| format!("could not write automation catalog to {path}"))?;
        return Ok(json!({"file": path}));
    }
    if !json_output {
        println!("{}", serde_json::to_string_pretty(&value)?);
        return Ok(json!({}));
    }
    Ok(value)
}

async fn policy(runtime: &RuntimeDirArgs, args: AutomationPolicyArgs) -> Result<Value> {
    let mut payload = json!({
        "kind": args.kind,
        "profileId": args.profile_id,
        "projectId": args.project_id,
    });
    if let Some(file) = args.file {
        payload["policy"] = read_json(&file)?;
    }
    if let Some(run_id) = std::env::var("ALERA_AUTOMATION_RUN_ID")
        .ok()
        .filter(|value| !value.trim().is_empty())
    {
        payload["run"] = Value::String(run_id);
        payload["targetIdentity"] = target_identity(&AutomationTargetArgs::default());
    }
    request(runtime, "automation.policy", payload).await
}

fn read_json(path: &str) -> Result<Value> {
    let mut contents = String::new();
    if path == "-" {
        std::io::stdin().read_to_string(&mut contents)?;
    } else {
        contents =
            fs::read_to_string(path).with_context(|| format!("could not read JSON file {path}"))?;
    }
    serde_json::from_str(&contents).with_context(|| format!("JSON file {path} is invalid"))
}

fn target_identity(args: &AutomationTargetArgs) -> Value {
    target_identity_with(args, |name| std::env::var(name).ok())
}

fn target_identity_with(
    args: &AutomationTargetArgs,
    environment: impl Fn(&str) -> Option<String>,
) -> Value {
    let field = |explicit: &Option<String>, environment_name: &str| {
        explicit
            .clone()
            .or_else(|| environment(environment_name))
            .filter(|value| !value.trim().is_empty())
    };
    let terminal_handle = field(&args.terminal_handle, "ALERA_TERMINAL_HANDLE");
    let session_id =
        field(&args.session_id, "ALERA_TERMINAL_SESSION_ID").or_else(|| terminal_handle.clone());
    json!({
        "workspaceId": field(&args.workspace_id, "ALERA_WORKSPACE_ID"),
        "tabId": field(&args.tab_id, "ALERA_TAB_ID"),
        "sessionId": session_id.clone(),
        "profileId": field(&args.profile_id, "ALERA_AGENT_PROFILE_ID"),
        "conversationId": field(&args.conversation_id, "ALERA_AGENT_CONVERSATION_ID"),
        "terminalHandle": terminal_handle.or_else(|| session_id.clone()),
    })
}

fn add_automation_context(payload: &mut Value) {
    let Some(run_id) = std::env::var("ALERA_AUTOMATION_RUN_ID")
        .ok()
        .filter(|value| !value.trim().is_empty())
    else {
        return;
    };
    payload["run"] = Value::String(run_id);
    payload["targetIdentity"] = target_identity(&AutomationTargetArgs::default());
}

#[allow(dead_code)]
fn _serialize<T: Serialize>(value: &T) -> Result<Value> {
    Ok(serde_json::to_value(value)?)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{target_identity_with, AutomationTargetArgs};

    #[test]
    fn explicit_terminal_handle_infers_the_session_identity() {
        let value = target_identity_with(
            &AutomationTargetArgs {
                terminal_handle: Some("handle".to_string()),
                ..AutomationTargetArgs::default()
            },
            |_| None,
        );
        assert_eq!(value["sessionId"], "handle");
        assert_eq!(value["terminalHandle"], "handle");
    }

    #[test]
    fn environment_inference_populates_the_complete_target_identity() {
        let environment = BTreeMap::from([
            ("ALERA_WORKSPACE_ID", "workspace"),
            ("ALERA_TAB_ID", "tab"),
            ("ALERA_TERMINAL_SESSION_ID", "session"),
            ("ALERA_AGENT_PROFILE_ID", "profile"),
            ("ALERA_AGENT_CONVERSATION_ID", "conversation"),
            ("ALERA_TERMINAL_HANDLE", "handle"),
        ]);
        let value = target_identity_with(&AutomationTargetArgs::default(), |name| {
            environment.get(name).map(|value| (*value).to_string())
        });
        assert_eq!(value["workspaceId"], "workspace");
        assert_eq!(value["tabId"], "tab");
        assert_eq!(value["sessionId"], "session");
        assert_eq!(value["profileId"], "profile");
        assert_eq!(value["conversationId"], "conversation");
        assert_eq!(value["terminalHandle"], "handle");
    }

    #[test]
    fn explicit_target_selectors_override_environment_values() {
        let value = target_identity_with(
            &AutomationTargetArgs {
                workspace_id: Some("explicit-workspace".into()),
                ..AutomationTargetArgs::default()
            },
            |_| Some("environment-value".into()),
        );
        assert_eq!(value["workspaceId"], "explicit-workspace");
        assert_eq!(value["tabId"], "environment-value");
    }
}
