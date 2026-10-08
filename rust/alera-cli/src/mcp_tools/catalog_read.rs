//! Tools that only read runtime state, plus bounded waits.

use super::schema::{integer, object, one_of, string, string_list};
use super::{Invocation, ToolAccess, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

/// Inbox used for questions an MCP client asks, kept apart from the user's own.
pub(super) const MCP_INBOX: &str = "ext:mcp";
const LIST_TIMEOUT: u64 = 30;
const WAIT_TIMEOUT: u64 = MAX_WAIT_SECONDS + 8;
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

fn read(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> serde_json::Value,
    build: fn(&ToolArguments) -> Result<Invocation, ToolInputError>,
) -> ToolSpec {
    ToolSpec {
        name,
        title,
        description,
        access: ToolAccess::Read,
        timeout_seconds: LIST_TIMEOUT,
        destructive: false,
        omit_fields: &[],
        input_schema,
        build,
    }
}

fn no_arguments() -> serde_json::Value {
    object(&[], &[])
}

pub(super) fn wait_seconds(arguments: &ToolArguments, default: u64) -> u64 {
    arguments
        .integer("timeoutSeconds")
        .unwrap_or(default)
        .clamp(1, MAX_WAIT_SECONDS)
}

fn wait_schema() -> serde_json::Value {
    integer(
        "Seconds to wait before returning the current state. Call again to keep waiting.",
        1,
        MAX_WAIT_SECONDS,
    )
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = vec![
        read(
            "runtime_status",
            "Runtime Status",
            "Show whether the Alera runtime host is running, its database, and its active sessions.",
            no_arguments,
            |_| Ok(Invocation::new("runtime", &["status"])),
        ),
        read(
            "list_projects",
            "List Projects",
            "List the projects registered in this Alera runtime with their ids, names, and the hosts each one is on.",
            no_arguments,
            |_| Ok(Invocation::new("project", &["list"])),
        ),
        read(
            "list_workspaces",
            "List Workspaces",
            "List workspaces (tasks with their branch and worktree) of one project, or of every project when projectId is omitted. Filter by host with hostId.",
            || {
                object(
                    &[
                        ("projectId", string("Project id from list_projects.")),
                        ("hostId", string("SSH target id, or `local`.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                let project = arguments.string("projectId");
                let all = project.is_none();
                Ok(Invocation::new("workspace", &["list"])
                    .option_if("--project-id", project)
                    .option_if("--host-id", arguments.string("hostId"))
                    .flag_if("--all", all))
            },
        ),
        read(
            "list_tabs",
            "List Tabs",
            "List the tabs of a workspace, including terminal and agent tabs.",
            || object(&[("workspaceId", string("Workspace id."))], &["workspaceId"]),
            |arguments| {
                Ok(Invocation::new("tab", &["list"])
                    .option("--workspace-id", arguments.required("workspaceId")?))
            },
        ),
        read(
            "list_agent_profiles",
            "List Agent Profiles",
            "List the agent profiles (Claude, Codex, and others) that can be launched or delegated to, with their ids and names.",
            no_arguments,
            |_| Ok(Invocation::new("agent-profile", &["list"])),
        ),
        read(
            "list_terminals",
            "List Terminals",
            "List live terminal sessions with their handles, optionally for one workspace.",
            || object(&[("workspaceId", string("Workspace id."))], &[]),
            |arguments| {
                Ok(Invocation::new("terminal", &["list"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "show_terminal",
            "Show Terminal",
            "Show one terminal session by handle, including its agent and lifecycle state.",
            || object(&[("handle", string("Terminal handle from list_terminals."))], &["handle"]),
            |arguments| {
                Ok(Invocation::new("terminal", &["show"])
                    .option("--handle", arguments.required("handle")?))
            },
        ),
        ToolSpec {
            omit_fields: &["dataBase64"],
            ..read(
            "read_terminal",
            "Read Terminal",
            "Read retained terminal output. Pass the returned cursor on the next call to read only new output.",
            || {
                object(
                    &[
                        ("handle", string("Terminal handle from list_terminals.")),
                        ("cursor", integer("Cursor returned by a previous read.", 0, u64::MAX >> 11)),
                        ("maxBytes", integer("Maximum bytes to return (default 32768).", 1, 262_144)),
                    ],
                    &["handle"],
                )
            },
            |arguments| {
                Ok(Invocation::new("terminal", &["read"])
                    .option("--handle", arguments.required("handle")?)
                    .option_if("--cursor", arguments.integer("cursor").map(|value| value.to_string()))
                    .option(
                        "--max-bytes",
                        arguments.integer("maxBytes").unwrap_or(32_768).to_string(),
                    ))
            },
        )
        },
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
        read(
            "list_inbox_targets",
            "List Askable Agents",
            "List running agents that ask_agent can reach, optionally for one workspace.",
            || object(&[("workspaceId", string("Workspace id."))], &[]),
            |arguments| {
                Ok(Invocation::new("inbox", &["targets"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "list_inbox_threads",
            "List Question Threads",
            "List question threads started through ask_agent, newest first.",
            || {
                object(
                    &[
                        ("status", one_of("Thread status.", &["pending", "received", "delivered", "expired", "answered", "cancelled"])),
                        ("workspaceId", string("Workspace id.")),
                        ("limit", integer("Maximum threads (default 50).", 1, 200)),
                        ("before", integer("Continue from the nextBefore value of a previous listing.", 0, u64::MAX >> 11)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("inbox", &["threads"])
                    .option("--inbox", MCP_INBOX)
                    .option_if("--status", arguments.string("status"))
                    .option_if("--workspace", arguments.string("workspaceId"))
                    .option_if("--limit", arguments.integer("limit").map(|value| value.to_string()))
                    .option_if("--before", arguments.integer("before").map(|value| value.to_string())))
            },
        ),
        read(
            "show_inbox_thread",
            "Show Question Thread",
            "Show a question thread with every question and reply.",
            || object(&[("questionId", string("Any question id in the thread."))], &["questionId"]),
            |arguments| {
                Ok(Invocation::new("inbox", &["show"])
                    .option("--question", arguments.required("questionId")?))
            },
        ),
        read(
            "list_automations",
            "List Automations",
            "List runtime automations, optionally filtered by state, project, or search text.",
            || {
                object(
                    &[
                        ("state", string("Automation state.")),
                        ("projectId", string("Project id.")),
                        ("search", string("Text to search for.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["list"])
                    .option_if("--state", arguments.string("state"))
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--search", arguments.string("search")))
            },
        ),
        read(
            "list_automation_runs",
            "List Automation Runs",
            "List automation runs, newest first, optionally for one automation.",
            || {
                object(
                    &[
                        ("automationId", string("Automation id.")),
                        ("limit", integer("Maximum runs (default 20).", 1, 100)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["runs"])
                    .option_if("--automation-id", arguments.string("automationId"))
                    .option("--limit", arguments.integer("limit").unwrap_or(20).to_string()))
            },
        ),
    ];
    tools.extend(wait_tools());
    tools
}

fn wait_tools() -> Vec<ToolSpec> {
    vec![
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
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_terminal",
                "Wait For Terminal",
                "Wait up to timeoutSeconds for a terminal to reach a lifecycle state, such as an agent becoming ready.",
                || {
                    object(
                        &[
                            ("handle", string("Terminal handle.")),
                            ("state", one_of("Lifecycle state.", &["process-started", "agent-detected", "agent-ready", "dispatch-accepted"])),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &["handle", "state"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("terminal", &["wait"])
                        .option("--terminal", arguments.required("handle")?)
                        .option("--for", arguments.required("state")?)
                        .option("--timeout-ms", (wait_seconds(arguments, 30) * 1000).to_string()))
                },
            )
        },
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "wait_for_reply",
                "Wait For Reply",
                "Wait up to timeoutSeconds for news about a question asked with ask_agent. Pass the returned cursor as after to skip what was already seen.",
                || {
                    object(
                        &[
                            ("questionId", string("Question id returned by ask_agent.")),
                            ("after", integer("Cursor from a previous result.", 0, u64::MAX >> 11)),
                            ("timeoutSeconds", wait_schema()),
                        ],
                        &["questionId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("inbox", &["wait"])
                        .option("--inbox", MCP_INBOX)
                        .option("--question", arguments.required("questionId")?)
                        .option_if("--after", arguments.integer("after").map(|value| value.to_string()))
                        .option("--timeout", format!("{}s", wait_seconds(arguments, 30))))
                },
            )
        },
    ]
}
