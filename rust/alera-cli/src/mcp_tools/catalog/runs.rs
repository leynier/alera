//! Reading runs: the run list, one run, its timeline, tasks, plan, gates,
//! retained resources, and integrations, over `alera orchestration run|plan|
//! gate|task`. Changing a run lives in `runs_manage`.

#[cfg(test)]
mod tests;

use super::read;
use crate::mcp_tools::schema::{integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolSpec};

const GATE_KINDS: &[&str] = &["decision", "stall", "plan", "stage"];
const GATE_STATES: &[&str] = &["pending", "resolved", "timeout", "invalidated"];

pub(super) fn number(arguments: &ToolArguments, name: &str) -> Option<String> {
    arguments.integer(name).map(|value| value.to_string())
}

pub(super) fn run_id() -> serde_json::Value {
    string("Run id from list_runs.")
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_runs",
            "List Runs",
            "List one page of runs, grouped as attention, active, or history, with their status, progress, and pending gates. Pass nextCursor back as cursor for the next page.",
            || {
                object(
                    &[
                        ("projectId", string("Project id.")),
                        ("workspaceId", string("Workspace id.")),
                        ("search", string("Text to search for in run objectives.")),
                        ("bucket", one_of("Group.", &["attention", "active", "history"])),
                        ("cursor", text("The nextCursor JSON object of a previous page, as text.", 1024)),
                        ("limit", integer("Maximum runs.", 1, 100)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "list"])
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--workspace", arguments.string("workspaceId"))
                    .option_if("--search", arguments.string("search"))
                    .option_if("--bucket", arguments.string("bucket"))
                    .option_if("--cursor", arguments.string("cursor"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "show_run",
            "Show Run",
            "Show one run: status, plan state, coordinator, pending gates, cleanup, controlSequence, and a page of its tasks. Continue with afterTaskId and the returned revision.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("afterTaskId", string("Continue after this task id.")),
                        ("revision", integer("Revision of the previous page.", 0, u64::MAX >> 11)),
                        ("limit", integer("Maximum tasks.", 1, 200)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "show"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--after-task", arguments.string("afterTaskId"))
                    .option_if("--revision", number(arguments, "revision"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "get_run_timeline",
            "Get Run Timeline",
            "Read a run's timeline of events and messages between its agents, newest first. Pass nextCursor back as cursor for older entries.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("taskId", string("Only entries about this task.")),
                        ("kinds", serde_json::json!({"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1, "description": "Event kinds to keep; message keeps messages."})),
                        ("cursor", text("nextCursor of a previous page.", 1024)),
                        ("limit", integer("Maximum entries (default 50).", 1, 200)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "timeline"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--task", arguments.string("taskId"))
                    .option_if("--kinds", arguments.list("kinds").map(|kinds| kinds.join(",")))
                    .option_if("--cursor", arguments.string("cursor"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "inspect_task",
            "Inspect Task",
            "Read one task of a run with its result, attempt, gates, and dispatch history.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("taskId", string("Task id.")),
                        ("cursor", text("The history cursor JSON object of a previous page, as text.", 1024)),
                        ("limit", integer("Maximum history entries.", 1, 100)),
                    ],
                    &["runId", "taskId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["task", "show"])
                    .option("--id", arguments.required("taskId")?)
                    .option("--run", arguments.required("runId")?)
                    .option_if("--cursor", arguments.string("cursor"))
                    .option_if("--limit", number(arguments, "limit")))
            },
        ),
        read(
            "show_run_plan",
            "Show Run Plan",
            "Show a run's current plan, or one revision: stages, tasks, recipe, and its plan gate.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("revision", integer("Plan revision (default the current one).", 1, u64::MAX >> 11)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["plan", "show"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--revision", number(arguments, "revision")))
            },
        ),
        read(
            "show_run_plan_context",
            "Show Run Plan Context",
            "Show what a run's coordinator plans against: objective, source, recipe, profiles, the current plan and any change request. Read it before propose_run_plan.",
            || object(&[("runId", run_id())], &["runId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["plan", "context"])
                    .option("--run", arguments.required("runId")?))
            },
        ),
        read(
            "list_run_gates",
            "List Run Gates",
            "List a run's gates, newest first: plan approval, stage gates, and the decision and stall gates of its tasks.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("taskId", string("Only gates of this task.")),
                        ("kind", one_of("Gate kind.", GATE_KINDS)),
                        ("status", one_of("Gate status.", GATE_STATES)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["gate", "list"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--task", arguments.string("taskId"))
                    .option_if("--kind", arguments.string("kind"))
                    .option_if("--status", arguments.string("status")))
            },
        ),
        read(
            "show_run_gate",
            "Show Run Gate",
            "Show one gate with its options, evidenceDigest, and what it decides on: the plan of a plan gate, the tasks and evidence of a stage gate, or the task of a decision or stall gate.",
            || object(&[("gateId", string("Gate id from list_run_gates or show_run."))], &["gateId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["gate", "show"])
                    .option("--id", arguments.required("gateId")?))
            },
        ),
        read(
            "list_run_resources",
            "List Run Resources",
            "List the worktrees and branches a run retains, which preview_run_cleanup can select.",
            page_schema,
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "resources"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--before-row", number(arguments, "beforeRow")))
            },
        ),
        read(
            "list_run_cleanups",
            "List Run Cleanups",
            "List a run's cleanups with their state and digest.",
            page_schema,
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "cleanup", "list"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--before-row", number(arguments, "beforeRow")))
            },
        ),
        read(
            "list_run_integrations",
            "List Run Integrations",
            "List the integrations of an isolated run: each task result squashed onto the run's integration branch, in order.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("afterRow", integer("Continue after this row from a previous page.", 0, u64::MAX >> 11)),
                    ],
                    &["runId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "integrations"])
                    .option("--run", arguments.required("runId")?)
                    .option_if("--after-row", number(arguments, "afterRow")))
            },
        ),
    ]
}

fn page_schema() -> serde_json::Value {
    object(
        &[
            ("runId", run_id()),
            (
                "beforeRow",
                integer(
                    "Continue before this row from a previous page.",
                    0,
                    u64::MAX >> 11,
                ),
            ),
        ],
        &["runId"],
    )
}
