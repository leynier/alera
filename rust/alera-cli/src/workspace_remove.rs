//! `alera workspace remove`.
//!
//! Without `--editor-buffers` it is the low-level removal it always was: the
//! caller chooses the branch, session, and automation policy. With it, the
//! command runs the Remove flow of the Alera app
//! (`workspace_removal_launcher.dart`): the branch is deleted when it can be,
//! dependent automations are paused, storage blockers refuse the removal like
//! Cleanup Unavailable, sessions close, the editors open on the workspace in
//! connected apps are saved or discarded, and uncommitted changes in the
//! worktree are lost with it.

use alera_core::runtime::{Workspace, WorkspaceKind};
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{EditorBuffersArg, RuntimeDirArgs, WorkspaceRemoveArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::workspace_removal_dependencies::{
    prepare_cli_removal_dependencies, WorkspaceRemovalDependency,
};

/// The storage blocker that pausing the dependent automations clears, which
/// is why the app ignores it when it is about to pause them.
const AUTOMATION_OWNER_BLOCKER: &str = "Workspace is owned by an active automation";
/// Measuring a large worktree walks every entry.
const STORAGE_DEADLINE_MS: u64 = 120_000;

pub async fn run(runtime: RuntimeDirArgs, args: WorkspaceRemoveArgs, json_output: bool) -> i32 {
    let result = async {
        let mut client = crate::runtime_host_required(&runtime).await?;
        match args.editor_buffers {
            Some(editor_buffers) => {
                let calling = crate::orchestration_commands::workspace_id_env();
                if calling.as_deref() == Some(args.id.trim()) {
                    bail!(
                        "Refusing to remove workspace {} from one of its own terminals: closing its sessions would stop this terminal too. Run the command from another workspace or use Remove in the app.",
                        args.id.trim()
                    );
                }
                remove_like_app(&mut client, &args, editor_buffers).await
            }
            None => remove(&mut client, &args).await,
        }
    }
    .await;
    match result {
        Ok(value) => {
            crate::print_value(&value, json_output, "workspace removed");
            0
        }
        Err(error) => crate::print_error(error),
    }
}

async fn find(client: &mut RuntimeHostRpcClient, id: &str) -> Result<Workspace> {
    let workspace: Option<Workspace> = client.request("workspace.find", &json!({"id": id})).await?;
    workspace.ok_or_else(|| anyhow!("Workspace not found: {id}"))
}

async fn remove(client: &mut RuntimeHostRpcClient, args: &WorkspaceRemoveArgs) -> Result<Value> {
    let delete_branch = match (args.delete_branch, args.keep_branch) {
        (true, _) => Some(true),
        (_, true) => Some(false),
        _ => None,
    };
    let payload = json!({
        "id": args.id,
        "deleteBranch": delete_branch,
        "closeSessions": args.close_sessions,
    });
    let workspace = find(client, &args.id).await?;
    prepare_cli_removal_dependencies(client, &args.id, args.pause_automations_and_cancel_runs)
        .await?;
    if workspace.kind == WorkspaceKind::Main {
        crate::workspace_buffer_guard_request::request_with_workspace_buffer_guard(
            client,
            "removeShared",
            &payload,
        )
        .await
    } else {
        client
            .request_value("workspace.removeManaged", &payload)
            .await
    }
}

/// The app's Remove button offers to delete the branch only for a workspace
/// that created its own branch.
pub(crate) fn can_delete_branch(workspace: &Workspace) -> bool {
    workspace.kind != WorkspaceKind::Main
        && !workspace.reuses_existing_branch
        && workspace
            .branch
            .as_deref()
            .is_some_and(|branch| !branch.trim().is_empty())
}

pub(crate) async fn remove_like_app(
    client: &mut RuntimeHostRpcClient,
    args: &WorkspaceRemoveArgs,
    editor_buffers: EditorBuffersArg,
) -> Result<Value> {
    let id = args.id.trim();
    let workspace = find(client, id).await?;
    let shared = workspace.kind == WorkspaceKind::Main;
    let deletable = can_delete_branch(&workspace);
    let delete_branch = !shared && !args.keep_branch && (args.delete_branch || deletable);
    let dependencies: Vec<WorkspaceRemovalDependency> = client
        .request("workspace.removalDependencies", &json!({"id": id}))
        .await?;
    let pausing = dependencies
        .iter()
        .any(|dependency| dependency.requires_pause);
    if !shared {
        let impact = client
            .request_value_with_deadline(
                "workspace.storageImpact",
                &json!({"id": id, "closeSessions": true}),
                STORAGE_DEADLINE_MS,
            )
            .await?;
        refuse_blocked_cleanup(&impact, pausing)?;
    }
    let all: Vec<Workspace> = client.request("workspace.listAll", &json!({})).await?;
    let children: Vec<Value> = all
        .iter()
        .filter(|candidate| candidate.parent_workspace_id.as_deref() == Some(id))
        .map(|child| json!({"id": child.id, "name": child.name}))
        .collect();
    let terminals = client
        .request_value("orchestration.terminals", &json!({"workspace": id}))
        .await?;
    let closed_sessions = terminals["items"].as_array().map_or(0, |items| {
        items.iter().filter(|item| item["running"] == true).count()
    });
    let paused: Vec<Value> = prepare_cli_removal_dependencies(client, id, true)
        .await?
        .into_iter()
        .filter(|dependency| dependency.requires_pause)
        .map(|dependency| json!({"id": dependency.id, "name": dependency.name}))
        .collect();
    let payload = json!({
        "id": id,
        "deleteBranch": if shared { Value::Null } else { json!(delete_branch) },
        "closeSessions": true,
    });
    let operation = if shared {
        "removeShared"
    } else {
        "removeManaged"
    };
    crate::workspace_buffer_guard_request::request_with_resolved_buffer_guard(
        client,
        operation,
        &payload,
        Some(editor_buffers.as_str()),
    )
    .await
    .map_err(|error| match paused.is_empty() {
        true => error,
        false => anyhow!(
            "{error} The workspace was kept, but its dependent automations were already paused and their active runs cancelled: {}.",
            paused
                .iter()
                .filter_map(|item| item["name"].as_str())
                .collect::<Vec<_>>()
                .join(", ")
        ),
    })?;
    let branch = branch_outcome(client, &workspace, delete_branch, args.keep_branch).await;
    Ok(json!({
        "removed": true,
        "workspaceId": id,
        "branch": branch,
        "pausedAutomations": paused,
        "unlinkedChildren": children,
        "closedSessions": closed_sessions,
    }))
}

/// Cleanup Unavailable, without the automation blocker the pause clears.
fn refuse_blocked_cleanup(impact: &Value, pausing: bool) -> Result<()> {
    let blockers: Vec<&str> = impact["blockers"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|blocker| !(pausing && *blocker == AUTOMATION_OWNER_BLOCKER))
        .collect();
    if blockers.is_empty() {
        return Ok(());
    }
    bail!(
        "blocked: Cleanup Unavailable. Alera measured {} bytes across {} entries. Cleanup is blocked: {}",
        impact["sizeBytes"].as_u64().unwrap_or(0),
        impact["entryCount"].as_u64().unwrap_or(0),
        blockers.join("; ")
    )
}

/// Branch deletion is safe like the app's: Git keeps a branch with unmerged
/// work, a protected or default branch, and one checked out elsewhere. The
/// host does not report which happened, so the branch catalog tells.
async fn branch_outcome(
    client: &mut RuntimeHostRpcClient,
    workspace: &Workspace,
    delete_requested: bool,
    keep_requested: bool,
) -> Value {
    let Some(name) = workspace
        .branch
        .as_deref()
        .filter(|branch| !branch.trim().is_empty())
    else {
        return json!({"name": null, "deleted": false, "retainedReason": "The workspace has no branch of its own."});
    };
    let retained = |reason: &str| json!({"name": name, "deleted": false, "retainedReason": reason});
    if workspace.kind == WorkspaceKind::Main {
        return retained("The project folder's branch is never deleted.");
    }
    if workspace.reuses_existing_branch {
        return retained("The workspace reused an existing branch, which Alera never deletes.");
    }
    if !delete_requested {
        return retained(if keep_requested {
            "Kept as requested."
        } else {
            "The branch cannot be deleted."
        });
    }
    let catalog = client
        .request_value(
            "project.branches.list",
            &json!({"projectId": workspace.project_id, "hostId": workspace.host_id}),
        )
        .await;
    match catalog {
        Ok(catalog) => {
            let still_there = catalog["localBranches"]
                .as_array()
                .is_some_and(|branches| branches.iter().any(|branch| branch == name));
            if still_there {
                retained("Git kept the branch: it has unmerged commits, is protected or the default branch, or is checked out elsewhere.")
            } else {
                json!({"name": name, "deleted": true})
            }
        }
        Err(error) => json!({
            "name": name,
            "deleted": Value::Null,
            "retainedReason": format!("Could not check the branch after removal: {error}"),
        }),
    }
}

#[cfg(test)]
#[path = "workspace_remove_tests.rs"]
mod tests;
