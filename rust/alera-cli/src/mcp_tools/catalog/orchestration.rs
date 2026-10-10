//! Orchestration tasks, coordinator runs, and messages between agents.

use super::{
    execute, profile_schema, read, wait_schema, wait_seconds, with_profile, LAUNCH_TIMEOUT,
    PROMPT_LIMIT, WAIT_TIMEOUT,
};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, string_list, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

const TASK_STATES: &[&str] = &[
    "pending",
    "ready",
    "dispatched",
    "completed",
    "failed",
    "blocked",
    "stalled",
    "cancelled",
];

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = vec![
        read(
            "list_tasks",
            "List Tasks",
            "List orchestration tasks, optionally filtered by status, coordinator run, or workspace.",
            || {
                object(
                    &[
                        ("status", one_of("Task status.", TASK_STATES)),
                        ("runId", string("Coordinator run id.")),
                        ("workspaceId", string("Workspace id.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["task-list"])
                    .option_if("--status", arguments.string("status"))
                    .option_if("--run", arguments.string("runId"))
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "show_task",
            "Show Task",
            "Show one orchestration task with its active dispatch.",
            || object(&[("taskId", string("Task id."))], &["taskId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["task-show"])
                    .option("--id", arguments.required("taskId")?))
            },
        ),
        read(
            "list_runs",
            "List Coordinator Runs",
            "List durable orchestration coordinator runs, optionally for one workspace.",
            || object(&[("workspaceId", string("Workspace id."))], &[]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["run-list"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "orchestration_status",
            "Orchestration Status",
            "Aggregate the run, task, worker, and escalation state of one coordinator run.",
            || object(&[("runId", string("Coordinator run id from list_runs."))], &["runId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["status"])
                    .option("--id", arguments.required("runId")?))
            },
        ),
        read(
            "list_messages",
            "List Orchestration Messages",
            "List recent orchestration messages across all recipients, or the inbox or outbox of one terminal.",
            || {
                object(
                    &[
                        ("terminal", string("Terminal handle.")),
                        ("direction", one_of("Direction relative to terminal.", &["inbox", "outbox"])),
                        ("limit", integer("Maximum messages (default 50).", 1, 200)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["inbox"])
                    .option_if("--terminal", arguments.string("terminal"))
                    .option_if("--direction", arguments.string("direction"))
                    .option_if("--limit", arguments.integer("limit").map(|value| value.to_string())))
            },
        ),
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_task",
                "Wait For Task",
                "Wait up to timeoutSeconds for an orchestration task to reach one of the given states, then return it. Returns the current state when the wait ends first.",
                || {
                    object(
                        &[
                            ("taskId", string("Task id.")),
                            ("states", string_list("States to wait for (default completed, failed, stalled, cancelled).", TASK_STATES)),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &["taskId"],
                    )
                },
                |arguments| {
                    let states = arguments
                        .list("states")
                        .unwrap_or_else(|| ["completed", "failed", "stalled", "cancelled"].map(String::from).to_vec());
                    Ok(Invocation::new("orchestration", &["task-wait"])
                        .option("--task", arguments.required("taskId")?)
                        .option("--for", states.join(","))
                        .option("--timeout-ms", (wait_seconds(arguments, 30) * 1000).to_string()))
                },
            )
        },
    ];
    tools.extend(mutations());
    tools
}

fn mutations() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "delegate_task",
                "Delegate Task",
                "Create an orchestration task and start an agent profile that accepts it, in an existing workspace or a new child worktree. The coordinator is a running agent terminal (from list_terminals) that receives the worker's messages. Returns the task; follow it with wait_for_task. Without a coordinator terminal, use start_agent_workspace or ask_agent instead.",
                || {
                    object(
                        &[
                            ("profile", profile_schema()),
                            ("spec", text("Task brief the worker receives.", PROMPT_LIMIT)),
                            ("coordinator", string("Terminal handle of the coordinating agent, from list_terminals.")),
                            ("title", string("Short title for listings.")),
                            ("workspaceId", string("Workspace that owns the task, or the source workspace with newWorkspace.")),
                            ("newWorkspace", boolean("Create a child worktree and delegate into it.")),
                            ("projectId", string("Project for the new workspace.")),
                            ("name", string("Name for the new workspace.")),
                            ("branch", string("Branch for the new workspace.")),
                            ("sourceBranch", string("Branch the new workspace starts from.")),
                            ("timeoutSeconds", integer("Seconds to wait for the agent to accept.", 1, MAX_WAIT_SECONDS)),
                        ],
                        &["profile", "spec", "coordinator"],
                    )
                },
                delegate_task,
            )
        },
        execute(
            "send_message",
            "Send Orchestration Message",
            "Send an orchestration message from one agent terminal to a terminal handle or a group such as @all, @idle, or @workspace:<id>. To ask an agent a question from outside, use ask_agent.",
            || {
                object(
                    &[
                        ("from", string("Sender terminal handle, from list_terminals.")),
                        ("to", string("Terminal handle or @group.")),
                        ("subject", string("Message subject.")),
                        ("body", text("Message body.", PROMPT_LIMIT)),
                        ("type", one_of("Message type.", &["status", "dispatch", "merge_ready", "escalation", "handoff", "decision_gate"])),
                        ("priority", one_of("Priority.", &["normal", "high", "urgent"])),
                        ("threadId", string("Thread to attach the message to.")),
                        ("taskId", string("Task the message is about, recorded in its payload.")),
                        ("payload", text("Raw JSON payload text, instead of taskId.", 16_384)),
                    ],
                    &["from", "to", "subject"],
                )
            },
            |arguments| {
                if arguments.string("taskId").is_some() && arguments.string("payload").is_some() {
                    return Err(ToolInputError("Pass taskId or payload, not both.".into()));
                }
                let invocation = Invocation::new("orchestration", &["send"])
                    .option("--from", arguments.required("from")?)
                    .option("--to", arguments.required("to")?)
                    .option("--subject", arguments.required("subject")?)
                    .option_if("--type", arguments.string("type"))
                    .option_if("--priority", arguments.string("priority"))
                    .option_if("--thread-id", arguments.string("threadId"))
                    .option_if("--task-id", arguments.string("taskId"))
                    .option_if("--payload", arguments.string("payload"));
                Ok(match arguments.string("body") {
                    Some(body) => invocation.flag("--body-stdin").stdin(body),
                    None => invocation,
                })
            },
        ),
        ToolSpec {
            destructive: true,
            ..execute(
                "cancel_task",
                "Cancel Task",
                "Cancel an orchestration task and its not-yet-started descendants. Runs as an audited administrative cancellation, because an MCP client is not the task's coordinator terminal.",
                || {
                    object(
                        &[("taskId", string("Task id.")), ("reason", string("Why it is cancelled."))],
                        &["taskId", "reason"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("orchestration", &["task-cancel"])
                        .option("--id", arguments.required("taskId")?)
                        .option("--reason", format!("[mcp] {}", arguments.required("reason")?))
                        .flag("--force"))
                },
            )
        },
    ]
}

fn delegate_task(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let new_workspace = arguments.flag("newWorkspace");
    let workspace = arguments.string("workspaceId");
    if workspace.is_none() && !(new_workspace && arguments.string("projectId").is_some()) {
        return Err(ToolInputError(
            "Pass workspaceId, or newWorkspace with projectId.".into(),
        ));
    }
    let workspace_flag = if new_workspace {
        "--from-workspace"
    } else {
        "--workspace"
    };
    Ok(with_profile(
        Invocation::new("orchestration", &["delegate"]),
        arguments.required("profile")?,
    )
    .flag("--spec-stdin")
    .flag("--keep-on-failure")
    .option("--from", arguments.required("coordinator")?)
    .option_if("--task-title", arguments.string("title"))
    .option_if(workspace_flag, workspace)
    .flag_if("--new-workspace", new_workspace)
    .option_if("--project-id", arguments.string("projectId"))
    .option_if("--name", arguments.string("name"))
    .option_if("--branch", arguments.string("branch"))
    .option_if("--source-branch", arguments.string("sourceBranch"))
    .flag_if(
        "--no-parent",
        new_workspace && arguments.string("workspaceId").is_none(),
    )
    .option(
        "--timeout-ms",
        (wait_seconds(arguments, MAX_WAIT_SECONDS) * 1000).to_string(),
    )
    .stdin(arguments.required("spec")?))
}
