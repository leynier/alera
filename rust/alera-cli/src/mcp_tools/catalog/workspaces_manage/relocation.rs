//! Hand Off and Hand On, worktree setup and its recovery, and the low-level
//! workspace record repair kept for administrators.

use serde_json::Value;

use super::{by_id, workspace_id, workspace_schema};
use crate::mcp_tools::catalog::{admin, execute, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{boolean, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

fn location(
    invocation: Invocation,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    let path = arguments.string("path");
    let root = arguments.string("workspaceRoot");
    if path.is_some() && root.is_some() {
        return Err(ToolInputError(
            "Pass path or workspaceRoot, not both.".into(),
        ));
    }
    Ok(invocation
        .option_if("--path", path)
        .option_if("--workspace-root", root))
}

fn location_properties() -> [(&'static str, Value); 2] {
    [
        ("path", string("Exact folder for the new worktree.")),
        (
            "workspaceRoot",
            string("Folder under which Alera names the new worktree. Defaults to the runtime's workspace folder."),
        ),
    ]
}

fn relocation_schema() -> Value {
    object(
        &[
            ("workspaceId", workspace_id()),
            (
                "relocationId",
                string("Relocation id from get_workspace_recovery."),
            ),
            (
                "attemptId",
                string("Setup attempt id from get_workspace_recovery."),
            ),
        ],
        &["workspaceId", "relocationId", "attemptId"],
    )
}

fn setup_attempt(arguments: &ToolArguments, flag: &str) -> Result<Invocation, ToolInputError> {
    Ok(by_id("setup", arguments)?
        .option("--relocation-id", arguments.required("relocationId")?)
        .option("--attempt-id", arguments.required("attemptId")?)
        .flag(flag))
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "hand_off_workspace",
                "Hand Off Workspace",
                "Move a task from its project folder to its own Git worktree on a new or existing branch, as Hand Off in the app does. Choose whether the uncommitted changes move with it or stay in the project folder.",
                || {
                    let mut properties = vec![
                        ("workspaceId", workspace_id()),
                        ("branch", string("Branch for the new worktree.")),
                        ("name", string("Display name of the moved task.")),
                        (
                            "changes",
                            one_of(
                                "move takes the uncommitted changes to the worktree; leave keeps them in the project folder.",
                                &["move", "leave"],
                            ),
                        ),
                        (
                            "reuseExistingBranch",
                            boolean("Use an existing branch instead of creating one. Needs replacementBranch and changes move."),
                        ),
                        (
                            "replacementBranch",
                            string("Branch the project folder switches to when the worktree takes its current branch."),
                        ),
                    ];
                    properties.extend(location_properties());
                    object(&properties, &["workspaceId", "branch", "changes"])
                },
                |arguments| {
                    let changes = arguments.required("changes")?;
                    let invocation = by_id("hand-off", arguments)?
                        .option("--branch", arguments.required("branch")?)
                        .option_if("--name", arguments.string("name"))
                        .flag_if("--move-changes", changes == "move")
                        .flag_if("--leave-changes", changes == "leave")
                        .flag_if("--reuse-existing-branch", arguments.flag("reuseExistingBranch"))
                        .flag("--confirm-shared-impact");
                    let replacement = arguments.string("replacementBranch");
                    if replacement.is_some() && !arguments.flag("reuseExistingBranch") {
                        return Err(ToolInputError(
                            "replacementBranch needs reuseExistingBranch.".into(),
                        ));
                    }
                    location(
                        invocation.option_if("--replacement-branch", replacement),
                        arguments,
                    )
                },
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "hand_on_workspace",
                "Hand On Workspace",
                "Bring a task from its own worktree back to its project folder on the same host, as Hand On in the app does. Every task on the project folder then shares that branch and its files.",
                workspace_schema,
                |arguments| Ok(by_id("hand-on", arguments)?.flag("--confirm-shared-impact")),
            )
        },
        read(
            "get_workspace_recovery",
            "Get Workspace Recovery",
            "Show a workspace's relocation phases and setup attempts, with the ids recover_workspace_setup and cancel_workspace_setup need. Runs nothing.",
            workspace_schema,
            |arguments| by_id("recovery", arguments),
        ),
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "run_workspace_setup",
                "Run Workspace Setup",
                "Run the project's worktree setup (copies and setup commands) in a workspace, or with relocationId the saved setup of that relocation once.",
                || {
                    object(
                        &[
                            ("workspaceId", workspace_id()),
                            ("copiesOnly", boolean("Only copy files; skip the setup commands.")),
                            ("relocationId", string("Relocation whose saved setup runs, from get_workspace_recovery.")),
                        ],
                        &["workspaceId"],
                    )
                },
                |arguments| {
                    let relocation = arguments.string("relocationId");
                    if relocation.is_some() && arguments.flag("copiesOnly") {
                        return Err(ToolInputError(
                            "A relocation runs its whole saved setup; copiesOnly does not apply.".into(),
                        ));
                    }
                    Ok(by_id("setup", arguments)?
                        .flag_if("--copies-only", arguments.flag("copiesOnly"))
                        .option_if("--relocation-id", relocation))
                },
            )
        },
        execute(
            "recover_workspace_setup",
            "Recover Workspace Setup",
            "Close an interrupted relocation setup attempt once its processes are verified gone, without running its commands again.",
            relocation_schema,
            |arguments| setup_attempt(arguments, "--recover"),
        ),
        execute(
            "cancel_workspace_setup",
            "Cancel Workspace Setup",
            "Ask a running relocation setup attempt to stop.",
            relocation_schema,
            |arguments| setup_attempt(arguments, "--cancel"),
        ),
        admin(
            "register_workspace_record",
            "Register Workspace Record",
            "Repair tool: write a workspace record for an existing folder without creating or touching any Git worktree.",
            || {
                object(
                    &[
                        ("projectId", string("Project id from list_projects.")),
                        ("name", string("Display name.")),
                        ("path", string("Existing workspace folder.")),
                        ("workspaceId", string("Workspace id to use or replace.")),
                        ("hostId", string("SSH target id the record names. Metadata only.")),
                        ("branch", string("Branch checked out in the folder.")),
                        ("sourceBranch", string("Branch it started from.")),
                        ("kind", one_of("main for the project folder, linked for a worktree (default).", &["linked", "main"])),
                        ("reuseExistingBranch", boolean("The branch existed before the workspace.")),
                    ],
                    &["projectId", "name", "path"],
                )
            },
            |arguments| {
                Ok(Invocation::new("workspace", &["register"])
                    .option("--project-id", arguments.required("projectId")?)
                    .option("--name", arguments.required("name")?)
                    .option("--path", arguments.required("path")?)
                    .option_if("--id", arguments.string("workspaceId"))
                    .option_if("--host-id", arguments.string("hostId"))
                    .option_if("--branch", arguments.string("branch"))
                    .option_if("--source-branch", arguments.string("sourceBranch"))
                    .option_if("--kind", arguments.string("kind"))
                    .flag_if("--reuse-existing-branch", arguments.flag("reuseExistingBranch")))
            },
        ),
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..admin(
                "unregister_workspace_record",
                "Unregister Workspace Record",
                "Repair tool: delete a workspace record and its tabs without touching any Git worktree or file.",
                workspace_schema,
                |arguments| by_id("unregister", arguments),
            )
        },
    ]
}
