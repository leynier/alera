//! Orchestration tasks, dispatch, coordinators, the run board, gates, and run
//! policies. Approving a run policy or resolving a gate stays a decision for
//! a person in the Alera app, so neither is a tool.
//!
//! An MCP client is not a terminal, so commands that check coordinator
//! ownership run as audited administrative actions (`--force`) with the
//! reason marked `[mcp]`, as `cancel_task` does.

use serde_json::{json, Value};

use super::{admin, execute, read, wait_seconds, LAUNCH_TIMEOUT, PROMPT_LIMIT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

const COORDINATOR: &str = "Terminal handle of the coordinating agent, from list_terminals.";
const JSON_LIMIT: u64 = 262_144;

fn reason(arguments: &ToolArguments) -> Result<String, ToolInputError> {
    Ok(format!("[mcp] {}", arguments.required("reason")?))
}

fn number(arguments: &ToolArguments, name: &str) -> Option<String> {
    arguments.integer(name).map(|value| value.to_string())
}

fn texts(description: &str) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 1,
        "description": description,
    })
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = tasks();
    tools.extend(coordinators());
    tools.extend(board());
    tools.extend(administration());
    tools
}

fn tasks() -> Vec<ToolSpec> {
    vec![
        execute(
            "create_task",
            "Create Task",
            "Create an orchestration task without starting an agent. A manual task names its coordinator terminal; a task of a coordinator run names the run and, with an execution policy, its stage. Follow it with dispatch_task or spawn_agent.",
            || {
                object(
                    &[
                        ("spec", text("Task brief the worker receives.", PROMPT_LIMIT)),
                        ("workspaceId", string("Workspace that owns the task.")),
                        ("coordinator", string(COORDINATOR)),
                        ("runId", string("Coordinator run for a coordinated task.")),
                        ("stage", string("Execution policy stage id, for a task of a run with a policy.")),
                        ("title", string("Short title for listings.")),
                        ("dependsOn", texts("Task ids this task waits for.")),
                        ("parentTaskId", string("Parent task id.")),
                        ("resultSchema", text("JSON Schema text that structured completion results must match.", 16_384)),
                    ],
                    &["spec", "workspaceId"],
                )
            },
            |arguments| {
                if arguments.string("coordinator").is_none() && arguments.string("runId").is_none() {
                    return Err(ToolInputError("Pass coordinator, runId, or both.".into()));
                }
                let deps = arguments.list("dependsOn").map(|deps| json!(deps).to_string());
                Ok(Invocation::new("orchestration", &["task-create"])
                    .flag("--spec-stdin")
                    .option("--workspace", arguments.required("workspaceId")?)
                    .option_if("--coordinator", arguments.string("coordinator"))
                    .option_if("--run", arguments.string("runId"))
                    .option_if("--stage", arguments.string("stage"))
                    .option_if("--task-title", arguments.string("title"))
                    .option_if("--deps", deps)
                    .option_if("--parent", arguments.string("parentTaskId"))
                    .option_if("--result-schema", arguments.string("resultSchema"))
                    .stdin(arguments.required("spec")?))
            },
        ),
        execute(
            "dispatch_task",
            "Dispatch Task",
            "Dispatch a ready task to an existing terminal. With inject, the task preamble is pasted into the running agent; dryRun only builds the preamble.",
            || {
                object(
                    &[
                        ("taskId", string("Ready task id.")),
                        ("to", string("Terminal handle of the worker, from list_terminals.")),
                        ("coordinator", string(COORDINATOR)),
                        ("inject", boolean("Paste the preamble into the worker's running agent.")),
                        ("dryRun", boolean("Build the preamble without changing anything.")),
                        ("returnPreamble", boolean("Include the full preamble text in the result.")),
                        ("terminalPolicy", one_of("What happens to the worker terminal after success (default keep-open).", &["keep-open", "close-on-success", "return-to-shell"])),
                    ],
                    &["taskId", "to", "coordinator"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["dispatch"])
                    .option("--task", arguments.required("taskId")?)
                    .option("--to", arguments.required("to")?)
                    .option("--from", arguments.required("coordinator")?)
                    .flag_if("--inject", arguments.flag("inject"))
                    .flag_if("--dry-run", arguments.flag("dryRun"))
                    .flag_if("--return-preamble", arguments.flag("returnPreamble"))
                    .option_if("--terminal-policy", arguments.string("terminalPolicy")))
            },
        ),
        read(
            "show_dispatch",
            "Show Dispatch",
            "Show the dispatch state and preamble of a task.",
            || object(&[("taskId", string("Task id."))], &["taskId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["dispatch-show"])
                    .option("--task", arguments.required("taskId")?))
            },
        ),
        execute(
            "interrupt_dispatch",
            "Interrupt Dispatch",
            "Interrupt the current turn of a dispatched worker without closing its terminal. Runs as an audited administrative interrupt.",
            || {
                object(
                    &[("dispatchId", string("Dispatch id from show_task or show_dispatch.")), ("reason", string("Why it is interrupted."))],
                    &["dispatchId", "reason"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["dispatch-interrupt"])
                    .option("--id", arguments.required("dispatchId")?)
                    .option("--reason", reason(arguments)?)
                    .flag("--force"))
            },
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "spawn_agent",
                "Spawn Agent For Task",
                "Start an agent for an existing ready task, in a new or given terminal of a workspace, and dispatch the task once the agent is ready. Returns when the agent accepts or the wait ends.",
                || {
                    object(
                        &[
                            ("taskId", string("Ready task id.")),
                            ("workspaceId", string("Workspace for the worker terminal.")),
                            ("coordinator", string(COORDINATOR)),
                            ("profile", string("Agent profile name from list_agent_profiles.")),
                            ("agent", string("Agent type (claude, codex, ...) when no profile is given.")),
                            ("terminal", string("Existing terminal handle to reuse.")),
                            ("title", string("Title of the worker tab.")),
                            ("timeoutSeconds", integer("Seconds to wait for the agent to accept.", 1, MAX_WAIT_SECONDS)),
                        ],
                        &["taskId", "workspaceId", "coordinator"],
                    )
                },
                |arguments| {
                    let (profile, agent) = (arguments.string("profile"), arguments.string("agent"));
                    if profile.is_some() == agent.is_some() {
                        return Err(ToolInputError("Pass profile or agent.".into()));
                    }
                    Ok(Invocation::new("orchestration", &["agent-spawn"])
                        .option("--task", arguments.required("taskId")?)
                        .option("--workspace", arguments.required("workspaceId")?)
                        .option("--from", arguments.required("coordinator")?)
                        .option_if("--profile", profile)
                        .option_if("--agent", agent)
                        .option_if("--terminal", arguments.string("terminal"))
                        .option_if("--title", arguments.string("title"))
                        .flag("--keep-on-failure")
                        .option("--timeout-ms", (wait_seconds(arguments, MAX_WAIT_SECONDS) * 1000).to_string()))
                },
            )
        },
    ]
}

fn coordinators() -> Vec<ToolSpec> {
    vec![
        execute(
            "start_coordinator",
            "Start Coordinator Run",
            "Start the background coordinator loop for a running coordinator agent: it records the run objective and dispatches the run's ready tasks to worker terminals.",
            || {
                object(
                    &[
                        ("spec", text("Run objective.", PROMPT_LIMIT)),
                        ("coordinator", string(COORDINATOR)),
                        ("workspaceId", string("Workspace that scopes worker terminals.")),
                        ("agent", string("Agent type for worker terminals the loop creates (default codex).")),
                        ("maxConcurrent", integer("Maximum concurrent dispatches (default 4).", 1, 64)),
                    ],
                    &["spec", "coordinator", "workspaceId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run"])
                    .flag("--spec-stdin")
                    .option("--from", arguments.required("coordinator")?)
                    .option("--workspace", arguments.required("workspaceId")?)
                    .option_if("--agent", arguments.string("agent"))
                    .option_if("--max-concurrent", number(arguments, "maxConcurrent"))
                    .stdin(arguments.required("spec")?))
            },
        ),
        ToolSpec {
            destructive: true,
            ..execute(
                "stop_coordinator",
                "Stop Coordinator Run",
                "Stop a coordinator run's loop, optionally cancelling its active tasks. Runs as an audited administrative stop.",
                || {
                    object(
                        &[
                            ("runId", string("Coordinator run id from list_runs.")),
                            ("reason", string("Why it is stopped.")),
                            ("cancelActive", boolean("Also cancel the run's active tasks.")),
                        ],
                        &["runId", "reason"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("orchestration", &["run-stop"])
                        .option("--id", arguments.required("runId")?)
                        .option("--reason", reason(arguments)?)
                        .flag_if("--cancel-active", arguments.flag("cancelActive"))
                        .flag("--force"))
                },
            )
        },
        read(
            "show_run",
            "Show Coordinator Run",
            "Show one coordinator run.",
            || object(&[("runId", string("Coordinator run id."))], &["runId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["run-show"])
                    .option("--id", arguments.required("runId")?))
            },
        ),
        execute(
            "propose_run_policy",
            "Propose Run Policy",
            "Propose an execution policy (a stage plan) for a coordinator run. The run holds scheduling until a person approves or rejects the policy in the Alera app.",
            || {
                object(
                    &[
                        ("runId", string("Coordinator run id.")),
                        ("policy", text("Execution policy as JSON text.", JSON_LIMIT)),
                    ],
                    &["runId", "policy"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run-policy-propose"])
                    .option("--run", arguments.required("runId")?)
                    .option("--policy-file", "-")
                    .stdin(arguments.required("policy")?))
            },
        ),
        read(
            "show_run_policy",
            "Show Run Policy",
            "Show a coordinator run's execution policy and whether it is approved.",
            || object(&[("runId", string("Coordinator run id."))], &["runId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["run-policy-show"])
                    .option("--run", arguments.required("runId")?))
            },
        ),
        read(
            "list_gates",
            "List Decision Gates",
            "List decision gates, optionally for one task or status.",
            || {
                object(
                    &[
                        ("taskId", string("Task id.")),
                        ("status", one_of("Gate status.", &["pending", "resolved", "timeout"])),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["gate-list"])
                    .option_if("--task", arguments.string("taskId"))
                    .option_if("--status", arguments.string("status")))
            },
        ),
        execute(
            "create_gate",
            "Create Decision Gate",
            "Ask a person to decide before a task continues. The task stays blocked until someone resolves the gate in the Alera app.",
            || {
                object(
                    &[
                        ("taskId", string("Task the gate blocks.")),
                        ("question", text("The question for the person.", 4096)),
                        ("options", texts("Answers to offer.")),
                    ],
                    &["taskId", "question"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["gate-create"])
                    .option("--task", arguments.required("taskId")?)
                    .option("--question", arguments.required("question")?)
                    .option_if("--options", arguments.list("options").map(|options| json!(options).to_string())))
            },
        ),
    ]
}

fn board() -> Vec<ToolSpec> {
    vec![
        read(
            "get_orchestration_board",
            "Get Orchestration Board",
            "Read one page of the run board, with coordinator runs grouped as attention, active, or history. Pass nextCursor back as cursor for the next page.",
            || {
                object(
                    &[
                        ("projectId", string("Project id.")),
                        ("workspaceId", string("Workspace id.")),
                        ("search", string("Text to search for.")),
                        ("bucket", one_of("Board column.", &["attention", "active", "history"])),
                        ("cursor", text("The nextCursor JSON object of a previous page, as text.", 1024)),
                        ("limit", integer("Maximum runs.", 1, 100)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["board"])
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--workspace", arguments.string("workspaceId"))
                    .option_if("--search", arguments.string("search"))
                    .option_if("--bucket", arguments.string("bucket"))
                    .option_if("--cursor", arguments.string("cursor"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "get_run_snapshot",
            "Get Run Snapshot",
            "Read a coordinator run with a page of its tasks. Continue with afterTaskId and the returned revision.",
            || {
                object(
                    &[
                        ("runId", string("Coordinator run id.")),
                        ("afterTaskId", string("Continue after this task id.")),
                        ("revision", integer("Board revision of the previous page.", 0, u64::MAX >> 11)),
                        ("limit", integer("Maximum tasks.", 1, 200)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run-snapshot"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--after-task", arguments.string("afterTaskId"))
                    .option_if("--revision", number(arguments, "revision"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "inspect_task",
            "Inspect Task",
            "Read one task of a coordinator run with its dispatches and history.",
            || {
                object(
                    &[
                        ("runId", string("Coordinator run id.")),
                        ("taskId", string("Task id.")),
                        ("cursor", text("The history cursor JSON object of a previous page, as text.", 1024)),
                        ("limit", integer("Maximum history entries.", 1, 200)),
                    ],
                    &["runId", "taskId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["task-inspect"])
                    .option("--run", arguments.required("runId")?)
                    .option("--task", arguments.required("taskId")?)
                    .option_if("--cursor", arguments.string("cursor"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
    ]
}

fn administration() -> Vec<ToolSpec> {
    vec![
        admin(
            "recover_task",
            "Recover Task",
            "Move a stalled task to ready, failed, or cancelled through an audited administrative recovery.",
            || {
                object(
                    &[
                        ("taskId", string("Task id.")),
                        ("status", one_of("New status.", &["ready", "failed", "cancelled"])),
                        ("reason", string("Why it is recovered.")),
                    ],
                    &["taskId", "status", "reason"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["task-recover"])
                    .option("--id", arguments.required("taskId")?)
                    .option("--status", arguments.required("status")?)
                    .option("--reason", reason(arguments)?)
                    .flag("--force"))
            },
        ),
        admin(
            "transfer_coordinator",
            "Transfer Coordinator",
            "Hand a task or a whole coordinator run to another coordinator terminal through an audited administrative transfer.",
            || {
                object(
                    &[
                        ("taskId", string("Task to transfer.")),
                        ("runId", string("Coordinator run to transfer.")),
                        ("to", string("Terminal handle of the new coordinator.")),
                        ("reason", string("Why it is transferred.")),
                    ],
                    &["to", "reason"],
                )
            },
            |arguments| {
                let (task, run) = (arguments.string("taskId"), arguments.string("runId"));
                if task.is_some() == run.is_some() {
                    return Err(ToolInputError("Pass taskId or runId.".into()));
                }
                Ok(Invocation::new("orchestration", &["transfer-coordinator"])
                    .option_if("--task", task)
                    .option_if("--run", run)
                    .option("--to", arguments.required("to")?)
                    .option("--reason", reason(arguments)?)
                    .flag("--force"))
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..admin(
                "reset_orchestration",
                "Reset Orchestration",
                "Clear orchestration state: tasks with their dispatches, gates, and coordinator runs, messages, or both (default all).",
                || object(&[("scope", one_of("What to clear (default all).", &["all", "tasks", "messages"]))], &[]),
                |arguments| {
                    let scope = arguments.string("scope").unwrap_or_else(|| "all".into());
                    Ok(Invocation::new("orchestration", &["reset"]).flag(&format!("--{scope}")))
                },
            )
        },
    ]
}
