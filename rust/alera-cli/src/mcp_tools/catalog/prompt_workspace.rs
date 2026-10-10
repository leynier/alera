//! New Workspace from Prompt as an asynchronous runtime operation.

use super::{execute, read, wait_schema, wait_seconds, PROMPT_LIMIT, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

/// The start waits this long for the operation before answering, which
/// leaves room for process start-up inside the client's deadline.
const START_WAIT_SECONDS: u64 = 40;
const _: () = assert!(START_WAIT_SECONDS < MAX_WAIT_SECONDS);

fn operation_id() -> serde_json::Value {
    string("Operation id from start_workspace_from_prompt or list_workspace_starts.")
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: START_WAIT_SECONDS + 10,
            client_request_flag: Some("--request-id"),
            ..execute(
                "start_workspace_from_prompt",
                "Start Workspace From Prompt",
                "Create a workspace from a task prompt and launch an agent in it, exactly like the Alera app's New Workspace from Prompt form. Without projectId, AI Assist recognizes the project from the prompt; when it is unclear the operation ends with status needsInput and a list of candidates, so call again with projectId. AI Assist also names the workspace and its branch and picks the best sidebar section, or none (Others) when nothing fits. Mode auto uses a new worktree for Git projects. Returns the operation after up to 40 seconds; if it is still running, follow it with wait_for_workspace_start.",
                || {
                    object(
                        &[
                            ("prompt", text("Task for the agent; it also names the workspace.", PROMPT_LIMIT)),
                            ("projectId", string("Project id from list_projects. Omit to recognize it from the prompt.")),
                            ("profile", string("Agent profile id or unique name. Defaults to the runtime's default profile.")),
                            ("mode", one_of("Where the workspace lives.", &["auto", "worktree", "projectCheckout"])),
                            ("sourceBranch", string("Branch a new worktree starts from. Defaults to the project's preferred branch.")),
                            ("hostId", string("SSH target that owns the worktree. Omit for this machine.")),
                            ("parentWorkspaceId", string("Workspace to set as the parent of the new one.")),
                            ("issueUrl", string("Issue URL to link to the workspace.")),
                            ("section", string("auto (default) lets AI Assist pick a section or none; none skips sections; any other value is a section name.")),
                            ("sectionId", string("Section to join, by id.")),
                        ],
                        &["prompt"],
                    )
                },
                start,
            )
        },
        read(
            "get_workspace_start",
            "Get Workspace Start",
            "Show a New Workspace from Prompt operation: status (running, needsInput, completed, failed, cancelled), phase, workspace, agent tab, setup tab, section, candidates, and error.",
            || object(&[("operationId", operation_id())], &["operationId"]),
            |arguments| {
                Ok(Invocation::new("workspace", &["prompt-start", "show"])
                    .option("--id", arguments.required("operationId")?))
            },
        ),
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_workspace_start",
                "Wait For Workspace Start",
                "Wait up to timeoutSeconds for a New Workspace from Prompt operation to stop running, then return it. Call again while the status is still running.",
                || {
                    object(
                        &[("operationId", operation_id()), ("timeoutSeconds", wait_schema())],
                        &["operationId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("workspace", &["prompt-start", "wait"])
                        .option("--id", arguments.required("operationId")?)
                        .option("--timeout-seconds", wait_seconds(arguments, 30).to_string()))
                },
            )
        },
        read(
            "list_workspace_starts",
            "List Workspace Starts",
            "List recent New Workspace from Prompt operations, newest first.",
            || object(&[("limit", integer("Maximum operations (default 20).", 1, 200))], &[]),
            |arguments| {
                Ok(Invocation::new("workspace", &["prompt-start", "list"]).option(
                    "--limit",
                    arguments.integer("limit").unwrap_or(20).to_string(),
                ))
            },
        ),
        execute(
            "cancel_workspace_start",
            "Cancel Workspace Start",
            "Cancel a running New Workspace from Prompt operation. A workspace it already created is kept.",
            || object(&[("operationId", operation_id())], &["operationId"]),
            |arguments| {
                Ok(Invocation::new("workspace", &["prompt-start", "cancel"])
                    .option("--id", arguments.required("operationId")?))
            },
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "retry_workspace_start_launch",
                "Retry Workspace Start Launch",
                "Launch the agent again for an operation whose workspace was created but whose agent did not start. It never creates another workspace and reuses the first launch's retry key.",
                || object(&[("operationId", operation_id())], &["operationId"]),
                |arguments| {
                    Ok(Invocation::new("workspace", &["prompt-start", "retry-launch"])
                        .option("--id", arguments.required("operationId")?))
                },
            )
        },
    ]
}

fn start(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    if arguments.string("section").is_some() && arguments.string("sectionId").is_some() {
        return Err(ToolInputError(
            "Pass section or sectionId, not both.".into(),
        ));
    }
    let mode = match arguments.string("mode").as_deref() {
        Some("projectCheckout") => "project-checkout",
        Some("worktree") => "worktree",
        _ => "auto",
    };
    Ok(Invocation::new("workspace", &["prompt-start", "run"])
        .flag("--prompt-stdin")
        .option("--mode", mode)
        .option_if("--project-id", arguments.string("projectId"))
        .option_if("--profile", arguments.string("profile"))
        .option_if("--source-branch", arguments.string("sourceBranch"))
        .option_if("--host-id", arguments.string("hostId"))
        .option_if(
            "--parent-workspace-id",
            arguments.string("parentWorkspaceId"),
        )
        .option_if("--issue", arguments.string("issueUrl"))
        .option_if("--section", arguments.string("section"))
        .option_if("--section-id", arguments.string("sectionId"))
        .option("--wait", START_WAIT_SECONDS.to_string())
        .stdin(arguments.required("prompt")?))
}
