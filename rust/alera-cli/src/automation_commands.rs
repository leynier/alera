use std::fs;
use std::io::Read;

use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::cli::{
    AutomationAction, AutomationCommand, AutomationCompleteArgs, AutomationDefinitionFileArgs,
    AutomationExtendArgs, AutomationListArgs, AutomationRevisionArgs, AutomationRunIdArgs,
    AutomationRunNowArgs, AutomationRunsArgs, AutomationStateArgs, AutomationTargetArgs,
    AutomationWaitArgs, RuntimeDirArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AUTOMATIONS_AUTHORING_CAPABILITY, RUNTIME_HOST_AUTOMATIONS_CAPABILITY,
    RUNTIME_HOST_AUTOMATION_REUSE_CAPABILITY,
};

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
            let shown = request(&runtime, "automation.show", json!({"id": args.id})).await;
            if !json_output {
                if let Ok(value) = &shown {
                    println!("{}", automation_run_commands::show_summary(value));
                    return 0;
                }
            }
            shown
        }
        AutomationAction::Create(args) => author(&runtime, args, "automation.create").await,
        AutomationAction::Readiness(args) => author(&runtime, args, "automation.readiness").await,
        AutomationAction::PreviewSchedule(args) => {
            author(&runtime, args, "automation.previewSchedule").await
        }
        AutomationAction::Edit(args) => author(&runtime, args, "automation.patch").await,
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
        AutomationAction::Clone(args) => automation_run_commands::clone(&runtime, args).await,
        AutomationAction::TakeOver(args) => {
            automation_run_commands::take_over(&runtime, args).await
        }
        AutomationAction::Unbind(args) => {
            let mut payload = json!({"id": args.id, "reason": args.reason});
            add_automation_context(&mut payload);
            request_requiring(
                &runtime,
                "automation.unbind",
                payload,
                RUNTIME_HOST_AUTOMATION_REUSE_CAPABILITY,
            )
            .await
        }
        AutomationAction::Cancel(args) => lifecycle(&runtime, "automation.cancel", &args).await,
        AutomationAction::Context(args) => lifecycle(&runtime, "automation.context", &args).await,
        AutomationAction::Heartbeat(args) => {
            lifecycle(&runtime, "automation.heartbeat", &args).await
        }
        AutomationAction::Wait(args) => wait(&runtime, args).await,
        AutomationAction::Extend(args) => extend(&runtime, args).await,
        AutomationAction::Complete(args) => complete(&runtime, args).await,
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
    let capability = if matches!(
        request_type,
        "automation.create"
            | "automation.patch"
            | "automation.readiness"
            | "automation.previewSchedule"
    ) {
        RUNTIME_HOST_AUTOMATIONS_AUTHORING_CAPABILITY
    } else {
        RUNTIME_HOST_AUTOMATIONS_CAPABILITY
    };
    request_requiring(runtime, request_type, payload, capability).await
}

async fn request_requiring(
    runtime: &RuntimeDirArgs,
    request_type: &str,
    mut payload: Value,
    capability: &str,
) -> Result<Value> {
    if let Ok(handle) = std::env::var("ALERA_TERMINAL_HANDLE") {
        payload["terminalHandle"] = json!(handle);
    }
    if let Some(attempt) =
        effective_attempt_id(&payload, std::env::var("ALERA_AUTOMATION_ATTEMPT_ID").ok())
    {
        payload["attemptId"] = json!(attempt);
    }
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        capability,
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
            "search": args.search,
            "workspaceId":args.workspace_id, "sectionId":args.section_id, "hostId":args.host_id, "bucket":args.bucket,
        }),
    )
    .await
}

async fn approve(runtime: &RuntimeDirArgs, args: AutomationRevisionArgs) -> Result<Value> {
    eprintln!("approve is deprecated; activating with resume. No approval is required.");
    let mut payload = json!({"id": args.id});
    add_automation_context(&mut payload);
    request(runtime, "automation.resume", payload).await
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
        _ => false,
    };
    let overlap = args.overlap;
    let mut payload = json!({
        "id": args.id,
        "precheck": if args.precheck || args.skip_precheck { Some(precheck) } else { None },
        "overlap": overlap,
        "continueFromRunId": args.continue_from_run,
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
    let identity = automation_run_commands::identity(
        runtime,
        &args.run_id,
        &args.target,
        args.use_run_identity,
    )
    .await?;
    request(
        runtime,
        request_type,
        json!({"run": args.run_id, "targetIdentity": identity}),
    )
    .await
}

async fn wait(runtime: &RuntimeDirArgs, args: AutomationWaitArgs) -> Result<Value> {
    let identity = automation_run_commands::identity(
        runtime,
        &args.run_id,
        &args.target,
        args.use_run_identity,
    )
    .await?;
    request(
        runtime,
        "automation.wait",
        json!({
            "run": args.run_id,
            "waiting": !args.resume,
            "targetIdentity": identity,
        }),
    )
    .await
}

async fn extend(runtime: &RuntimeDirArgs, args: AutomationExtendArgs) -> Result<Value> {
    if args.until.is_none() && args.seconds.is_none() {
        anyhow::bail!("waiting extension requires --until or --seconds");
    }
    let identity = automation_run_commands::identity(
        runtime,
        &args.run_id,
        &args.target,
        args.use_run_identity,
    )
    .await?;
    request(
        runtime,
        "automation.extend",
        json!({
            "run": args.run_id,
            "until": args.until,
            "seconds": args.seconds,
            "targetIdentity": identity,
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

/// An attempt id the caller passed wins over the terminal's: a conversation
/// an automation reuses keeps the environment of the run that launched it.
fn effective_attempt_id(payload: &Value, environment: Option<String>) -> Option<String> {
    payload["targetIdentity"]["attemptId"]
        .as_str()
        .filter(|value| !value.trim().is_empty())
        .map(str::to_string)
        .or(environment)
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
        "attemptId": field(&args.attempt_id, "ALERA_AUTOMATION_ATTEMPT_ID"),
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

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    #[test]
    fn an_explicit_attempt_id_wins_over_the_terminal_environment() {
        use super::effective_attempt_id;
        use serde_json::json;
        let environment = Some("launching-attempt".to_string());
        assert_eq!(
            effective_attempt_id(
                &json!({"targetIdentity": {"attemptId": "current-attempt"}}),
                environment.clone()
            )
            .as_deref(),
            Some("current-attempt")
        );
        assert_eq!(
            effective_attempt_id(&json!({"id": "automation"}), environment.clone()).as_deref(),
            Some("launching-attempt")
        );
        assert_eq!(effective_attempt_id(&json!({}), None), None);
    }

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

#[path = "automation_authoring_commands.rs"]
mod automation_authoring_commands;
use automation_authoring_commands::author;
#[path = "automation_run_commands.rs"]
mod automation_run_commands;
