//! Workspace organization, lifecycle, removal, and recovery.

mod organize;
mod relocation;

use serde_json::Value;

use super::{execute, read, LAUNCH_TIMEOUT};
use crate::mcp_tools::schema::{boolean, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const NAME_LIMIT: u64 = 200;

pub(super) fn workspace_id() -> Value {
    string("Workspace id from list_workspaces.")
}

fn workspace_schema() -> Value {
    object(&[("workspaceId", workspace_id())], &["workspaceId"])
}

/// `alera workspace <action> --id <workspaceId>`.
fn by_id(action: &'static str, arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("workspace", &[action]).option("--id", arguments.required("workspaceId")?))
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = vec![
        read(
            "show_workspace",
            "Show Workspace",
            "Show one workspace with its project, section, tags, linked issue, linked pull request, Watch and Fix state, parent, children, and whether it is asleep.",
            workspace_schema,
            |arguments| by_id("show", arguments),
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "rename_workspace",
                "Rename Workspace",
                "Change a workspace's display name. Its branch and folder are not touched.",
                || {
                    object(
                        &[
                            ("workspaceId", workspace_id()),
                            ("name", text("New display name.", NAME_LIMIT)),
                        ],
                        &["workspaceId", "name"],
                    )
                },
                |arguments| {
                    Ok(by_id("rename", arguments)?.option("--name", arguments.required("name")?))
                },
            )
        },
        ToolSpec {
            idempotent: true,
            ..execute(
                "set_workspace_pinned",
                "Pin Or Unpin Workspace",
                "Pin a workspace to the top of the sidebar, or unpin it. With tree, the same applies to every workspace below it.",
                || {
                    object(
                        &[
                            ("workspaceId", workspace_id()),
                            ("pinned", boolean("True to pin, false to unpin.")),
                            ("tree", boolean("Also apply to every descendant workspace.")),
                        ],
                        &["workspaceId", "pinned"],
                    )
                },
                |arguments| {
                    let action = if arguments.flag("pinned") { "pin" } else { "unpin" };
                    Ok(by_id(action, arguments)?.flag_if("--tree", arguments.flag("tree")))
                },
            )
        },
        ToolSpec {
            destructive: true,
            idempotent: true,
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "archive_workspace",
                "Archive Workspace",
                "Archive a workspace: its terminal sessions stop and it leaves the sidebar, while its tabs, branch, and files are kept for unarchive_workspace.",
                workspace_schema,
                |arguments| by_id("archive", arguments),
            )
        },
        ToolSpec {
            idempotent: true,
            ..execute(
                "unarchive_workspace",
                "Unarchive Workspace",
                "Return an archived workspace to the sidebar.",
                workspace_schema,
                |arguments| by_id("unarchive", arguments),
            )
        },
        ToolSpec {
            idempotent: true,
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "wake_workspace",
                "Wake Workspace",
                "Wake a workspace put to sleep with sleep_workspace: its stopped terminals start again and agent tabs resume their sessions, as opening it in the Alera app does.",
                workspace_schema,
                |arguments| by_id("wake", arguments),
            )
        },
        ToolSpec {
            idempotent: true,
            ..execute(
                "focus_workspace",
                "Focus Workspace",
                "Select and show a workspace in the running Alera desktop app.",
                workspace_schema,
                |arguments| by_id("focus", arguments),
            )
        },
        ToolSpec {
            timeout_seconds: LAUNCH_TIMEOUT,
            ..read(
                "preview_workspace_removal",
                "Preview Workspace Removal",
                "Show what remove_workspace would do without changing anything: measured storage and what blocks cleanup, the automations it would pause, the linked workspaces it would unlink, live sessions, and what happens to the branch.",
                workspace_schema,
                |arguments| by_id("remove-preview", arguments),
            )
        },
        ToolSpec {
            destructive: true,
            timeout_seconds: LAUNCH_TIMEOUT,
            ..execute(
                "remove_workspace",
                "Remove Workspace",
                "Remove a workspace, active or archived, with the Remove flow of the Alera app: its sessions close, dependent automations are paused and their runs cancelled, editors open on it in the app are saved (or discarded), and its worktree is deleted. Uncommitted changes in the worktree are lost, as when removing from the Alera app. A project folder workspace keeps its files. The branch is deleted when the workspace created it, unless branch is keep; Git still keeps a branch with unmerged work. Fails with blocked, removing nothing, when cleanup is unavailable or an editor cannot be saved.",
                || {
                    object(
                        &[
                            ("workspaceId", workspace_id()),
                            (
                                "branch",
                                one_of(
                                    "delete removes the branch, keep preserves it. Default: delete when the workspace created the branch, as the Remove button does.",
                                    &["delete", "keep"],
                                ),
                            ),
                            (
                                "editorBuffers",
                                one_of(
                                    "What to do with unsaved editors on this workspace in the Alera app: save them (default) or discard them.",
                                    &["save", "discard"],
                                ),
                            ),
                        ],
                        &["workspaceId"],
                    )
                },
                remove_workspace,
            )
        },
    ];
    tools.extend(relocation::tools());
    tools.extend(organize::tools());
    tools
}

fn remove_workspace(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let editor_buffers = arguments
        .string("editorBuffers")
        .unwrap_or_else(|| "save".into());
    let branch = arguments.string("branch");
    Ok(by_id("remove", arguments)?
        .option("--editor-buffers", editor_buffers)
        .flag_if("--delete-branch", branch.as_deref() == Some("delete"))
        .flag_if("--keep-branch", branch.as_deref() == Some("keep")))
}
