//! Running an approved workflow: execution control, corrections, isolated
//! attempts, local integration, and the cleanup of retained workspaces.

use super::super::{admin, execute, read, LAUNCH_TIMEOUT};
use super::{string_items, with_request_id, REQUEST_FLAG};
use crate::mcp_tools::schema::{integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const REASON_LIMIT: u64 = 4_096;
const ROW_MAX: u64 = u64::MAX >> 11;

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = execution();
    tools.extend(attempts());
    tools.extend(cleanup());
    tools
}

fn run_revision() -> [(&'static str, serde_json::Value); 2] {
    [
        ("runId", string("Workflow run id.")),
        ("revision", integer("Approved plan revision.", 1, ROW_MAX)),
    ]
}

fn with_run_revision(
    invocation: Invocation,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    Ok(invocation
        .option("--run", arguments.required("runId")?)
        .option("--revision", revision(arguments)?))
}

fn revision(arguments: &ToolArguments) -> Result<String, ToolInputError> {
    arguments
        .integer("revision")
        .map(|value| value.to_string())
        .ok_or_else(|| ToolInputError("Missing required argument `revision`.".into()))
}

fn execution() -> Vec<ToolSpec> {
    vec![
        read(
            "get_workflow_execution",
            "Get Workflow Execution",
            "Show whether a workflow run is scheduling, paused, or cancelled, with the command sequence control_workflow_execution needs.",
            || {
                object(
                    &[("runId", string("Workflow run id.")), ("revision", integer("Plan revision (default current).", 1, ROW_MAX))],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["execution", "show"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--revision", arguments.integer("revision").map(|value| value.to_string())))
            },
        ),
        ToolSpec {
            destructive: true,
            client_request_flag: Some(REQUEST_FLAG),
            ..execute(
                "control_workflow_execution",
                "Control Workflow Execution",
                "Start, pause, or cancel the scheduling of an approved workflow run revision. Fails if expectedSequence is stale.",
                || {
                    let mut properties = run_revision().to_vec();
                    properties.push(("expectedSequence", integer("Sequence from get_workflow_execution.", 0, ROW_MAX)));
                    properties.push(("action", one_of("What to do.", &["start", "pause", "cancel"])));
                    object(&properties, &["runId", "revision", "expectedSequence", "action"])
                },
                |arguments| {
                    let sequence = arguments
                        .integer("expectedSequence")
                        .ok_or_else(|| ToolInputError("Missing required argument `expectedSequence`.".into()))?;
                    let invocation = with_run_revision(Invocation::new("orchestration", &["execution", "control"]), arguments)?
                        .option("--expected-sequence", sequence.to_string())
                        .option("--action", arguments.required("action")?);
                    Ok(with_request_id(invocation, arguments))
                },
            )
        },
        ToolSpec {
            client_request_flag: Some(REQUEST_FLAG),
            ..execute(
                "create_workflow_correction",
                "Create Workflow Correction",
                "Open a correction proposal for a workflow run revision, with the reason the coordinator receives. A person still approves the corrected plan.",
                || {
                    let mut properties = run_revision().to_vec();
                    properties.push(("planDigest", string("Plan digest from show_workflow_plan.")));
                    properties.push(("reason", text("Why the run needs a correction.", REASON_LIMIT)));
                    object(&properties, &["runId", "revision", "planDigest", "reason"])
                },
                |arguments| {
                    let invocation = with_run_revision(Invocation::new("orchestration", &["execution", "correct", "--reason-stdin"]), arguments)?
                        .option("--plan-digest", arguments.required("planDigest")?);
                    Ok(with_request_id(invocation, arguments).stdin(arguments.required("reason")?))
                },
            )
        },
    ]
}

fn attempts() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            client_request_flag: Some(REQUEST_FLAG),
            ..execute(
                "prepare_workflow_attempt",
                "Prepare Workflow Attempt",
                "Prepare the integration workspace of an approved run, or a task's isolated attempt. retryOf names the latest failed attempt; a retry always gets a new worktree. Dispatches no worker.",
                || {
                    let mut properties = run_revision().to_vec();
                    properties.push(("taskId", string("Task to prepare an attempt for. Omit to prepare the integration workspace.")));
                    properties.push(("retryOf", string("Workspace id of the task's latest failed attempt.")));
                    object(&properties, &["runId", "revision"])
                },
                |arguments| {
                    if arguments.string("retryOf").is_some() && arguments.string("taskId").is_none() {
                        return Err(ToolInputError("retryOf needs taskId.".into()));
                    }
                    let invocation = with_run_revision(Invocation::new("orchestration", &["workspaces", "prepare"]), arguments)?
                        .option_if("--task", arguments.string("taskId"))
                        .option_if("--retry-of", arguments.string("retryOf"));
                    Ok(with_request_id(invocation, arguments))
                },
            )
        },
        task_workspace_tool(
            "launch_workflow_task",
            "Launch Workflow Task",
            "Launch one approved task in its ready isolated attempt, at most once per clientRequestId.",
            "launch",
        ),
        task_workspace_tool(
            "integrate_workflow_result",
            "Integrate Workflow Result",
            "Squash a completed task's result into its run's local integration workspace. Use a new clientRequestId to retry a failed integration.",
            "integrate",
        ),
        read(
            "list_workflow_integrations",
            "List Workflow Integrations",
            "List a run's local integration outcomes, or show one integration receipt with any conflict paths.",
            || {
                object(
                    &[
                        ("runId", string("Workflow run id.")),
                        ("integrationId", string("Show this integration instead of listing.")),
                        ("afterRow", integer("Continue after this row of a previous page.", 0, ROW_MAX)),
                    ],
                    &[],
                )
            },
            |arguments| match (arguments.string("integrationId"), arguments.string("runId")) {
                (Some(id), _) => Ok(Invocation::new("orchestration", &["workspaces", "integration"]).option("--id", id)),
                (None, Some(run)) => Ok(Invocation::new("orchestration", &["workspaces", "integrations"])
                    .option("--run", run)
                    .option_if("--after-row", arguments.integer("afterRow").map(|value| value.to_string()))),
                (None, None) => Err(ToolInputError("Pass runId or integrationId.".into())),
            },
        ),
        read(
            "list_workflow_workspaces",
            "List Workflow Workspaces",
            "List the workspaces a workflow run retains (integration and attempts) with their setup outcome.",
            || {
                object(
                    &[
                        ("runId", string("Workflow run id.")),
                        ("beforeRow", integer("Continue before this row of a previous page.", 0, ROW_MAX)),
                        ("limit", integer("Maximum entries.", 1, 200)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["workspaces", "list"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--before-row", arguments.integer("beforeRow").map(|value| value.to_string()))
                    .option_if("--limit", arguments.integer("limit").map(|value| value.to_string())))
            },
        ),
    ]
}

/// `orchestration workspaces launch|integrate`, which share their arguments.
fn task_workspace_tool(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    action: &'static str,
) -> ToolSpec {
    let build: fn(&ToolArguments) -> Result<Invocation, ToolInputError> = if action == "launch" {
        |arguments| task_workspace(arguments, "launch")
    } else {
        |arguments| task_workspace(arguments, "integrate")
    };
    ToolSpec {
        timeout_seconds: LAUNCH_TIMEOUT,
        client_request_flag: Some(REQUEST_FLAG),
        ..execute(
            name,
            title,
            description,
            || {
                let mut properties = run_revision().to_vec();
                properties.push(("taskId", string("Task id.")));
                properties.push(("workspaceId", string("The task attempt's workspace id.")));
                object(&properties, &["runId", "revision", "taskId", "workspaceId"])
            },
            build,
        )
    }
}

fn task_workspace(
    arguments: &ToolArguments,
    action: &'static str,
) -> Result<Invocation, ToolInputError> {
    let invocation = with_run_revision(
        Invocation::new("orchestration", &["workspaces", action]),
        arguments,
    )?
    .option("--task", arguments.required("taskId")?)
    .option("--workspace-id", arguments.required("workspaceId")?);
    Ok(with_request_id(invocation, arguments))
}

fn cleanup() -> Vec<ToolSpec> {
    vec![
        read(
            "list_workflow_cleanups",
            "List Workflow Cleanups",
            "List a workflow run's retained resources with their cleanup state, or its cleanup operations.",
            || {
                object(
                    &[
                        ("runId", string("Workflow run id.")),
                        ("view", one_of("resources (default) or operations.", &["resources", "operations"])),
                        ("beforeRow", integer("Continue before this row of a previous page.", 0, ROW_MAX)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                let action = match arguments.string("view").as_deref() {
                    Some("operations") => "list",
                    _ => "resources",
                };
                Ok(Invocation::new("orchestration", &["cleanup", action])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--before-row", arguments.integer("beforeRow").map(|value| value.to_string())))
            },
        ),
        read(
            "preview_workflow_cleanup",
            "Preview Workflow Cleanup",
            "Preview removing up to 25 retained workspaces of a workflow run, optionally with their branches. Changes nothing; returns the id and digest the cleanup tools need.",
            || {
                object(
                    &[
                        ("runId", string("Workflow run id.")),
                        ("workspaceIds", string_items("Retained workspaces to remove.")),
                        ("removeBranchFor", string_items("Selected workspaces whose branch is deleted too.")),
                    ],
                    &["runId", "workspaceIds"],
                )
            },
            |arguments| {
                let workspaces = arguments.list("workspaceIds").unwrap_or_default();
                let branches = arguments.list("removeBranchFor").unwrap_or_default();
                if let Some(stray) = branches.iter().find(|id| !workspaces.contains(id)) {
                    return Err(ToolInputError(format!("removeBranchFor names {stray}, which is not in workspaceIds.")));
                }
                let invocation = Invocation::new("orchestration", &["cleanup", "preview"]).option("--run", arguments.required("runId")?);
                let invocation = workspaces.into_iter().fold(invocation, |invocation, id| invocation.option("--workspace", id));
                Ok(branches.into_iter().fold(invocation, |invocation, id| invocation.option("--remove-branch", id)))
            },
        ),
        read(
            "get_workflow_cleanup",
            "Get Workflow Cleanup",
            "Show a workflow cleanup operation, its reviewed preview, and the outcome of each resource.",
            || object(&[("cleanupId", string("Cleanup (preview) id."))], &["cleanupId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["cleanup", "status"]).option("--id", arguments.required("cleanupId")?))
            },
        ),
        cleanup_tool(
            "apply_workflow_cleanup",
            "Apply Workflow Cleanup",
            "Remove the workspaces (and branches) of a previewed workflow cleanup. Fails if they changed since the preview.",
            true,
            |arguments| confirmation(arguments, "apply"),
        ),
        cleanup_tool(
            "retry_workflow_cleanup",
            "Retry Workflow Cleanup",
            "Retry a workflow cleanup that did not finish, for the same reviewed preview.",
            true,
            |arguments| confirmation(arguments, "retry"),
        ),
        cleanup_tool(
            "abandon_workflow_cleanup",
            "Abandon Workflow Cleanup",
            "Abandon an unfinished workflow cleanup and keep the resources it did not remove.",
            false,
            |arguments| confirmation(arguments, "abandon"),
        ),
    ]
}

fn cleanup_tool(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    destructive: bool,
    build: fn(&ToolArguments) -> Result<Invocation, ToolInputError>,
) -> ToolSpec {
    ToolSpec {
        timeout_seconds: LAUNCH_TIMEOUT,
        destructive,
        ..admin(
            name,
            title,
            description,
            || {
                object(
                    &[
                        (
                            "cleanupId",
                            string("Cleanup id from preview_workflow_cleanup."),
                        ),
                        ("digest", string("Digest from preview_workflow_cleanup.")),
                    ],
                    &["cleanupId", "digest"],
                )
            },
            build,
        )
    }
}

fn confirmation(
    arguments: &ToolArguments,
    action: &'static str,
) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("orchestration", &["cleanup", action])
        .option("--id", arguments.required("cleanupId")?)
        .option("--digest", arguments.required("digest")?))
}
