//! Dispatches, decision gates a coordinator opens, and orchestration
//! administration. Run plans, gates of runs, and run control live in `runs`.
//!
//! An MCP client is not a terminal, so commands that check coordinator
//! ownership run as audited administrative actions (`--force`) with the
//! reason marked `[mcp]`, as `cancel_task` does.

use serde_json::{json, Value};

use super::{admin, execute, read};
use crate::mcp_tools::schema::{object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

fn reason(arguments: &ToolArguments) -> Result<String, ToolInputError> {
    Ok(format!("[mcp] {}", arguments.required("reason")?))
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
    let mut tools = dispatches();
    tools.extend(administration());
    tools
}

fn dispatches() -> Vec<ToolSpec> {
    vec![
        read(
            "show_dispatch",
            "Show Dispatch",
            "Show the dispatch state and preamble of a task.",
            || object(&[("taskId", string("Task id."))], &["taskId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["dispatch", "show"])
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
                Ok(Invocation::new("orchestration", &["dispatch", "interrupt"])
                    .option("--id", arguments.required("dispatchId")?)
                    .option("--reason", reason(arguments)?)
                    .flag("--force"))
            },
        ),
        execute(
            "create_gate",
            "Create Decision Gate",
            "Ask a person to decide before a task continues. The task stays blocked until someone resolves the gate.",
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
                Ok(Invocation::new("orchestration", &["gate", "create"])
                    .option("--task", arguments.required("taskId")?)
                    .option("--question", arguments.required("question")?)
                    .option_if("--options", arguments.list("options").map(|options| json!(options).to_string())))
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
                Ok(Invocation::new("orchestration", &["task", "recover"])
                    .option("--id", arguments.required("taskId")?)
                    .option("--status", arguments.required("status")?)
                    .option("--reason", reason(arguments)?)
                    .flag("--force"))
            },
        ),
        admin(
            "transfer_coordinator",
            "Transfer Coordinator",
            "Hand a task or a whole run to another coordinator terminal through an audited administrative transfer.",
            || {
                object(
                    &[
                        ("taskId", string("Task to transfer.")),
                        ("runId", string("Run to transfer.")),
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
                "Clear orchestration state: tasks with their dispatches, gates, and runs, messages, or both (default all).",
                || object(&[("scope", one_of("What to clear (default all).", &["all", "tasks", "messages"]))], &[]),
                |arguments| {
                    let scope = arguments.string("scope").unwrap_or_else(|| "all".into());
                    Ok(Invocation::new("orchestration", &["reset"]).flag(&format!("--{scope}")))
                },
            )
        },
    ]
}
