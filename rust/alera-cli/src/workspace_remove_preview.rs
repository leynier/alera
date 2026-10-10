//! `alera workspace remove-preview`: what the app's Remove flow would do,
//! without doing it. It measures storage (and its blockers), lists the
//! automations a removal pauses and the linked workspaces it unlinks, and says
//! what happens to the branch. Nothing changes.

use alera_core::runtime::{Workspace, WorkspaceKind};
use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::cli::{IdArgs, RuntimeDirArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::workspace_removal_dependencies::WorkspaceRemovalDependency;

const AUTOMATION_OWNER_BLOCKER: &str = "Workspace is owned by an active automation";

pub async fn run(runtime: RuntimeDirArgs, args: IdArgs, json_output: bool) -> i32 {
    let result = async {
        let mut client = crate::runtime_host_required(&runtime).await?;
        preview(&mut client, args.id.trim()).await
    }
    .await;
    match result {
        Ok(value) => {
            let message = if value["removable"] == true {
                "workspace can be removed"
            } else {
                "workspace removal is blocked"
            };
            crate::print_value(&value, json_output, message);
            0
        }
        Err(error) => crate::print_error(error),
    }
}

pub(crate) async fn preview(client: &mut RuntimeHostRpcClient, id: &str) -> Result<Value> {
    let workspace: Option<Workspace> = client.request("workspace.find", &json!({"id": id})).await?;
    let workspace = workspace.ok_or_else(|| anyhow!("Workspace not found: {id}"))?;
    let shared = workspace.kind == WorkspaceKind::Main;
    let dependencies: Vec<WorkspaceRemovalDependency> = client
        .request("workspace.removalDependencies", &json!({"id": id}))
        .await?;
    let pausing = dependencies
        .iter()
        .any(|dependency| dependency.requires_pause);
    let storage = if shared {
        Value::Null
    } else {
        client
            .request_value_with_deadline(
                "workspace.storageImpact",
                &json!({"id": id, "closeSessions": true}),
                120_000,
            )
            .await?
    };
    let blockers: Vec<Value> = storage["blockers"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|blocker| !(pausing && blocker.as_str() == Some(AUTOMATION_OWNER_BLOCKER)))
        .cloned()
        .collect();
    let all: Vec<Workspace> = client.request("workspace.listAll", &json!({})).await?;
    let children: Vec<Value> = all
        .iter()
        .filter(|candidate| candidate.parent_workspace_id.as_deref() == Some(id))
        .map(|child| json!({"id": child.id, "name": child.name}))
        .collect();
    let terminals = client
        .request_value("orchestration.terminals", &json!({"workspace": id}))
        .await?;
    let live_sessions = terminals["items"].as_array().map_or(0, |items| {
        items.iter().filter(|item| item["running"] == true).count()
    });
    let can_delete = crate::workspace_remove::can_delete_branch(&workspace);
    Ok(json!({
        "workspaceId": id,
        "name": workspace.name,
        "sharedCheckout": shared,
        "removable": blockers.is_empty(),
        "blockers": blockers,
        "storage": storage,
        "automations": dependencies,
        "unlinkedChildren": children,
        "liveSessions": live_sessions,
        "branch": {
            "name": workspace.branch,
            "canDelete": can_delete,
            "defaultAction": if can_delete { "delete" } else { "keep" },
        },
        "uncommittedChangesLost": !shared,
    }))
}
