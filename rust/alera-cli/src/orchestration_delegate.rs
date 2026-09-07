use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::agent_profile_commands::{list_profiles, print_json, select_profile};
use crate::cli::RuntimeDirArgs;
use crate::cli_orchestration::OrchestrationDelegateArgs;
use crate::orchestration_commands::{
    request_value, request_value_with_capability, terminal_handle_env, usage_error,
    workspace_id_env, WAIT_CLIENT_GRACE_MS,
};
use crate::orchestration_terminal_commands::{
    reconcile_agent_spawn_failure, terminal_wait_outcome,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_ORCHESTRATION_CAPABILITY, RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
};
use crate::workspace_context::resolve_workspace_context;
use crate::workspace_start::{create_inferred_workspace, InferredWorkspaceCreate};

pub async fn run(
    runtime: &RuntimeDirArgs,
    args: OrchestrationDelegateArgs,
    json_output: bool,
) -> i32 {
    match run_inner(runtime, args, json_output).await {
        Ok(code) => code,
        Err(error) => crate::print_error(error),
    }
}

async fn run_inner(
    runtime: &RuntimeDirArgs,
    args: OrchestrationDelegateArgs,
    json_output: bool,
) -> Result<i32> {
    let spec = args.spec.read()?;
    let task_title = args
        .task_title
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| crate::cli::task_title_from_spec(&spec));
    let Some(from) = args.from.clone().or_else(terminal_handle_env) else {
        return Ok(usage_error(
            "--from is required (or set ALERA_TERMINAL_HANDLE).",
        ));
    };
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    )
    .await?;
    let (_, profiles) = list_profiles(&mut client).await?;
    let profile = select_profile(&profiles, &args.selector)?.clone();
    let created_workspace = if args.new_workspace {
        Some(
            create_inferred_workspace(
                runtime,
                &mut client,
                InferredWorkspaceCreate {
                    id: args.id,
                    project_id: args.project_id,
                    branch: args.branch,
                    source_branch: args.source_branch,
                    name: args.name,
                    workspace_root: args.workspace_root,
                    path: args.path,
                    parent_workspace_id: args.parent_workspace_id,
                    no_parent: args.no_parent,
                    from_workspace: args.from_workspace,
                },
                &spec,
            )
            .await?,
        )
    } else {
        None
    };
    let workspace_id = if let Some(created) = created_workspace.as_ref() {
        created
            .get("workspace")
            .and_then(|workspace| workspace.get("id"))
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("workspace create returned no workspace id"))?
            .to_string()
    } else if let Some(workspace) = args
        .workspace
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        workspace.to_string()
    } else if let Some(workspace) = workspace_id_env() {
        workspace
    } else {
        return Ok(usage_error(
            "--workspace is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).",
        ));
    };
    if created_workspace.is_none() {
        let _ = resolve_workspace_context(runtime, Some(&workspace_id)).await?;
    }
    let task = request_value(
        runtime,
        "orchestration.taskCreate",
        json!({
            "spec": spec,
            "taskTitle": task_title,
            "deps": Value::Array(Vec::new()),
            "createdBy": from,
            "coordinator": from,
            "workspace": workspace_id,
        }),
        None,
    )
    .await?;
    let task_id = task
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("task create returned no task id"))?
        .to_string();
    let mut envelope = json!({
        "workspaceId": workspace_id,
        "profileId": profile.id,
        "profileName": profile.name,
        "taskId": task_id,
        "taskTitle": task_title,
        "task": task,
    });
    if let Some(created) = created_workspace {
        if let Some(workspace) = created.get("workspace") {
            envelope["projectId"] = workspace.get("projectId").cloned().unwrap_or(Value::Null);
            envelope["branch"] = workspace.get("branch").cloned().unwrap_or(Value::Null);
            envelope["path"] = workspace.get("path").cloned().unwrap_or(Value::Null);
            envelope["name"] = workspace.get("name").cloned().unwrap_or(Value::Null);
            envelope["workspace"] = workspace.clone();
        }
    }
    let spawn = match request_value_with_capability(
        runtime,
        RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
        "orchestration.agentSpawn",
        json!({
            "workspace": workspace_id,
            "profile": profile.name,
            "task": task_id,
            "title": task_title,
            "from": from,
            "keepOnFailure": args.keep_on_failure,
        }),
        None,
    )
    .await
    {
        Ok(spawn) => spawn,
        Err(error) => {
            let message = error.to_string();
            envelope["spawnError"] = json!(message);
            print_delegate_result(&envelope, json_output, None, Some(&message))?;
            return Ok(1);
        }
    };
    envelope["spawn"] = spawn.clone();
    let handle = spawn
        .get("terminalHandle")
        .or_else(|| spawn.get("assigneeHandle"))
        .and_then(Value::as_str)
        .map(ToString::to_string);
    let wait = if let Some(handle) = handle.as_deref() {
        envelope["terminalHandle"] = json!(handle);
        let value = request_value_with_capability(
            runtime,
            RUNTIME_HOST_ORCHESTRATION_WAIT_CAPABILITY,
            "orchestration.terminalWait",
            json!({
                "terminal": handle,
                "target": "dispatch-accepted",
                "timeoutMs": args.timeout_ms,
            }),
            Some(args.timeout_ms.saturating_add(WAIT_CLIENT_GRACE_MS)),
        )
        .await?;
        if matches!(terminal_wait_outcome(&value), "timeout" | "failed") {
            reconcile_agent_spawn_failure(runtime, handle).await;
        }
        envelope["wait"] = value.clone();
        Some(value)
    } else {
        None
    };
    let outcome = wait.as_ref().map(terminal_wait_outcome);
    let failure = match outcome {
        Some("reached") => None,
        Some("timeout") => Some("dispatch acceptance timed out".to_string()),
        Some(other) => Some(
            wait.as_ref()
                .and_then(|value| value.get("error").and_then(Value::as_str))
                .unwrap_or(other)
                .to_string(),
        ),
        None => Some("agent spawn returned no terminal handle".to_string()),
    };
    print_delegate_result(
        &envelope,
        json_output,
        Some((&task_id, &profile.name, &workspace_id)),
        failure.as_deref(),
    )?;
    Ok(if failure.is_some() { 1 } else { 0 })
}

fn print_delegate_result(
    envelope: &Value,
    json_output: bool,
    accepted: Option<(&str, &str, &str)>,
    failure: Option<&str>,
) -> Result<()> {
    if json_output {
        print_json(envelope)?;
    } else if let Some(message) = failure {
        if let Some((task_id, profile_name, workspace_id)) = accepted {
            eprintln!(
                "task {task_id} was not accepted by {profile_name} in workspace {workspace_id}: {message}"
            );
        } else {
            eprintln!(
                "task {} was created but the agent did not spawn: {message}",
                envelope["taskId"].as_str().unwrap_or("unknown")
            );
        }
    } else if let Some((task_id, profile_name, workspace_id)) = accepted {
        println!("task {task_id} delegated to {profile_name} in workspace {workspace_id}");
    }
    Ok(())
}
