//! Changing runs: create, propose a plan, resolve a gate, pause, resume,
//! cancel, replan, retry, and clean up retained resources. The host records
//! the calling MCP client as the actor of every change.
//!
//! Resolving a gate and removing resources are decisions a person owns, so
//! those tools need the `admin` class.

use serde_json::{json, Value};

use super::runs::{number, run_id};
use super::{admin, execute, read, with_profile, LAUNCH_TIMEOUT, PROMPT_LIMIT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const JSON_LIMIT: u64 = 262_144;

fn ids(description: &str) -> Value {
    json!({
        "type": "array",
        "items": { "type": "string", "minLength": 1 },
        "minItems": 1,
        "description": description,
    })
}

fn sequence() -> Value {
    integer(
        "controlSequence from show_run. Read from the run when omitted.",
        0,
        u64::MAX >> 11,
    )
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = lifecycle();
    tools.extend(control());
    tools.extend(cleanup());
    tools
}

fn lifecycle() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            client_request_flag: Some("--request-id"),
            ..execute(
                "create_run",
                "Create Run",
                "Start a run in a workspace: a coordinator agent profile reads the objective, proposes a plan, and workers carry it out. isolated (default) gives each task its own worktree and integrates results in order; shared lets workers use the run's workspace. With approvalRequired the plan waits for a person. Returns the run id; follow it with show_run.",
                || {
                    object(
                        &[
                            ("workspaceId", string("Workspace the run works in.")),
                            ("objective", text("What the run should achieve.", PROMPT_LIMIT)),
                            ("coordinatorProfile", string("Coordinator agent profile id or unique name from list_agent_profiles.")),
                            ("isolation", one_of("Where workers run (default isolated).", &["isolated", "shared"])),
                            ("recipe", string("Recipe of an isolated run: builtIn:<id>, personal:<id>, or project:<path>, as list_recipes reports them.")),
                            ("workerProfile", string("Profile for workers whose role has no profile of its own.")),
                            ("approvalRequired", boolean("Hold the plan for a person's approval.")),
                            ("maxConcurrent", integer("Maximum workers at once.", 1, 16)),
                            ("stallPolicy", one_of("What happens when a worker stalls.", &["ask", "auto-failover", "wait"])),
                        ],
                        &["workspaceId", "objective", "coordinatorProfile"],
                    )
                },
                |arguments| {
                    Ok(with_profile(
                        Invocation::new("orchestration", &["run", "new"]),
                        arguments.required("coordinatorProfile")?,
                    )
                    .flag("--spec-stdin")
                    .option("--workspace", arguments.required("workspaceId")?)
                    .option_if("--isolation", arguments.string("isolation"))
                    .option_if("--template", arguments.string("recipe"))
                    .option_if("--worker-profile", arguments.string("workerProfile"))
                    .flag_if("--approval", arguments.flag("approvalRequired"))
                    .option_if("--max-concurrent", number(arguments, "maxConcurrent"))
                    .option_if("--stall-policy", arguments.string("stallPolicy"))
                    .stdin(arguments.required("objective")?))
                },
            )
        },
        execute(
            "propose_run_plan",
            "Propose Run Plan",
            "Propose the next plan of a run as JSON ({stages?, tasks?, stallPolicy?, maxConcurrent?}); read show_run_plan_context first. When the run requires approval, the plan waits behind a plan gate until a person resolves it.",
            || {
                object(
                    &[("runId", run_id()), ("plan", text("Plan as JSON text.", JSON_LIMIT))],
                    &["runId", "plan"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["plan", "propose"])
                    .option("--run", arguments.required("runId")?)
                    .flag("--stdin")
                    .stdin(arguments.required("plan")?))
            },
        ),
        admin(
            "resolve_run_gate",
            "Resolve Run Gate",
            "Resolve a pending gate as the person it waits for. Plan and stage gates take approve, requestChanges (with reason), or reject; stall gates take killAndFailover, keepWaiting, or abortStage; decision gates take one of their options. Pass the gate's evidenceDigest from show_run_gate so a gate whose evidence changed is refused as stale.",
            || {
                object(
                    &[
                        ("gateId", string("Gate id from list_run_gates.")),
                        ("decision", string("Option id, or the answer of a decision gate without options.")),
                        ("reason", text("Why. Required with requestChanges.", 4096)),
                        ("taskIds", ids("With requestChanges: the tasks the change is about.")),
                        ("expectedEvidenceDigest", string("evidenceDigest from show_run_gate.")),
                    ],
                    &["gateId", "decision"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["gate", "resolve"])
                    .option("--id", arguments.required("gateId")?)
                    .option("--decision", arguments.required("decision")?)
                    .option_if("--reason", arguments.string("reason"))
                    .option_if("--tasks", arguments.list("taskIds").map(|ids| ids.join(",")))
                    .option_if("--expected-digest", arguments.string("expectedEvidenceDigest")))
            },
        ),
    ]
}

fn control_tool(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    build: fn(&ToolArguments) -> Result<Invocation, ToolInputError>,
) -> ToolSpec {
    execute(
        name,
        title,
        description,
        || {
            object(
                &[
                    ("runId", run_id()),
                    ("reason", text("Why, recorded on the run's timeline.", 4096)),
                    ("expectedSequence", sequence()),
                ],
                &["runId"],
            )
        },
        build,
    )
}

fn control_invocation(
    action: &str,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("orchestration", &["run", action])
        .option("--run", arguments.required("runId")?)
        .option_if("--reason", arguments.string("reason"))
        .option_if("--expected-sequence", number(arguments, "expectedSequence")))
}

fn control() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            destructive: true,
            ..control_tool(
                "cancel_run",
                "Cancel Run",
                "Cancel a run: interrupt its workers and coordinator, cancel unfinished tasks, and invalidate pending gates. Retained worktrees stay until cleanup.",
                |arguments| control_invocation("cancel", arguments),
            )
        },
        control_tool(
            "pause_run",
            "Pause Run",
            "Pause a running run so no new work starts. Dispatched workers keep going.",
            |arguments| control_invocation("pause", arguments),
        ),
        control_tool(
            "resume_run",
            "Resume Run",
            "Resume a paused run. Refused while a plan or stage gate waits for a decision.",
            |arguments| control_invocation("resume", arguments),
        ),
        execute(
            "replan_run",
            "Replan Run",
            "Ask the run's coordinator for a new plan revision, with what should change.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("reason", text("What the coordinator should change.", 4096)),
                        ("taskIds", ids("Tasks the change is about.")),
                        ("expectedSequence", sequence()),
                    ],
                    &["runId", "reason"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "replan"])
                    .option("--run", arguments.required("runId")?)
                    .option("--reason", arguments.required("reason")?)
                    .option_if("--tasks", arguments.list("taskIds").map(|ids| ids.join(",")))
                    .option_if("--expected-sequence", number(arguments, "expectedSequence")))
            },
        ),
        execute(
            "retry_run_task",
            "Retry Run Task",
            "Start a new attempt of a task whose attempt needs attention, in a paused isolated run.",
            retry_schema,
            |arguments| retry(arguments, "--task"),
        ),
        execute(
            "retry_run_integration",
            "Retry Run Integration",
            "Integrate a task's result again after its integration needed attention, in a paused isolated run.",
            retry_schema,
            |arguments| retry(arguments, "--integration"),
        ),
    ]
}

fn retry_schema() -> Value {
    object(
        &[("runId", run_id()), ("taskId", string("Task id."))],
        &["runId", "taskId"],
    )
}

fn retry(arguments: &ToolArguments, flag: &str) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("orchestration", &["run", "retry"])
        .option("--run", arguments.required("runId")?)
        .option(flag, arguments.required("taskId")?))
}

fn confirm_schema() -> Value {
    object(
        &[
            ("cleanupId", string("Cleanup id from preview_run_cleanup.")),
            (
                "digest",
                string("Digest from preview_run_cleanup or show_run_cleanup."),
            ),
        ],
        &["cleanupId", "digest"],
    )
}

fn confirm(arguments: &ToolArguments, action: &str) -> Result<Invocation, ToolInputError> {
    Ok(
        Invocation::new("orchestration", &["run", "cleanup", action])
            .option("--id", arguments.required("cleanupId")?)
            .option("--digest", arguments.required("digest")?),
    )
}

fn cleanup() -> Vec<ToolSpec> {
    vec![
        read(
            "preview_run_cleanup",
            "Preview Run Cleanup",
            "Preview removing up to 25 retained worktrees of a run, from list_run_resources, optionally with their branches. Removes nothing; returns the cleanup id and digest apply_run_cleanup needs.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("workspaceIds", ids("Workspace ids of the resources to remove.")),
                        ("deleteBranchFor", ids("Selected workspace ids whose branch is deleted too.")),
                    ],
                    &["runId", "workspaceIds"],
                )
            },
            |arguments| {
                let selected = arguments.list("workspaceIds").unwrap_or_default();
                let branches = arguments.list("deleteBranchFor").unwrap_or_default();
                if branches.iter().any(|workspace| !selected.contains(workspace)) {
                    return Err(ToolInputError("deleteBranchFor must name selected workspaceIds.".into()));
                }
                let mut invocation = Invocation::new("orchestration", &["run", "cleanup", "preview"])
                    .option("--run", arguments.required("runId")?);
                for workspace in selected {
                    invocation = invocation.option("--resource", workspace);
                }
                for workspace in branches {
                    invocation = invocation.option("--delete-branch", workspace);
                }
                Ok(invocation)
            },
        ),
        read(
            "show_run_cleanup",
            "Show Run Cleanup",
            "Show one cleanup with its state, digest, and per-resource results.",
            || object(&[("cleanupId", string("Cleanup id."))], &["cleanupId"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["run", "cleanup", "status"])
                    .option("--id", arguments.required("cleanupId")?))
            },
        ),
        ToolSpec {
            destructive: true,
            ..admin(
                "apply_run_cleanup",
                "Apply Run Cleanup",
                "Remove the resources of a reviewed preview_run_cleanup. Fails if anything changed since the preview.",
                confirm_schema,
                |arguments| confirm(arguments, "apply"),
            )
        },
        ToolSpec {
            destructive: true,
            ..admin(
                "retry_run_cleanup",
                "Retry Run Cleanup",
                "Retry a cleanup that needs attention.",
                confirm_schema,
                |arguments| confirm(arguments, "retry"),
            )
        },
        admin(
            "abandon_run_cleanup",
            "Abandon Run Cleanup",
            "Give up on a cleanup that needs attention and release its resources without removing them.",
            confirm_schema,
            |arguments| confirm(arguments, "abandon"),
        ),
    ]
}
