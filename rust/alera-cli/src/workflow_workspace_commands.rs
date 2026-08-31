use serde_json::json;

use crate::cli::RuntimeDirArgs;
use crate::cli_workflow_workspaces::{WorkflowWorkspacesAction, WorkflowWorkspacesArgs};
use crate::orchestration_commands::request_value_with_capability;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_WORKFLOW_INTEGRATIONS_CAPABILITY, RUNTIME_HOST_WORKFLOW_WORKSPACES_CAPABILITY,
};

pub(crate) async fn run(runtime: &RuntimeDirArgs, args: WorkflowWorkspacesArgs) -> i32 {
    let capability = if matches!(
        &args.action,
        WorkflowWorkspacesAction::Integrate { .. }
            | WorkflowWorkspacesAction::Launch { .. }
            | WorkflowWorkspacesAction::Launches { .. }
            | WorkflowWorkspacesAction::Integrations { .. }
            | WorkflowWorkspacesAction::Integration { .. }
    ) {
        RUNTIME_HOST_WORKFLOW_INTEGRATIONS_CAPABILITY
    } else {
        RUNTIME_HOST_WORKFLOW_WORKSPACES_CAPABILITY
    };
    let (verb, payload) = match args.action {
        WorkflowWorkspacesAction::Launches { run, after_row } => (
            "workflows.launches",
            json!({"runId":run,"afterRow":after_row}),
        ),
        WorkflowWorkspacesAction::Launch {
            run,
            revision,
            request_id,
            task,
            workspace_id,
        } => (
            "workflows.launchTask",
            json!({"runId":run,"revision":revision,"requestId":request_id,"taskId":task,"workspaceId":workspace_id}),
        ),
        WorkflowWorkspacesAction::Integrate {
            run,
            revision,
            request_id,
            task,
            workspace_id,
        } => (
            "workflows.integrateResult",
            json!({"runId":run,"revision":revision,"requestId":request_id,"taskId":task,"workspaceId":workspace_id}),
        ),
        WorkflowWorkspacesAction::Integrations { run, after_row } => (
            "workflows.integrations",
            json!({"runId":run,"afterRow":after_row}),
        ),
        WorkflowWorkspacesAction::Integration { id } => ("workflows.integration", json!({"id":id})),
        WorkflowWorkspacesAction::Prepare {
            run,
            revision,
            request_id,
            task,
            retry_of,
        } => (
            "workflows.prepareWorkspace",
            json!({
                "runId":run, "revision":revision, "requestId":request_id, "taskId":task, "retryOf":retry_of
            }),
        ),
        WorkflowWorkspacesAction::List {
            run,
            before_row,
            limit,
        } => (
            "workflows.workspaces",
            json!({"runId":run,"beforeRow":before_row,"limit":limit}),
        ),
    };
    match request_value_with_capability(runtime, capability, verb, payload, Some(30_000)).await {
        Ok(value) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&value).unwrap_or_default()
            );
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}
