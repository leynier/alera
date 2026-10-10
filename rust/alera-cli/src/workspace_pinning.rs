use std::path::PathBuf;

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::json;

use crate::cli::WorkspacePinArgs;
use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn run(
    runtime_dir: PathBuf,
    json_output: bool,
    args: WorkspacePinArgs,
    is_pinned: bool,
) -> i32 {
    let result = if args.tree {
        set_tree_pinned(runtime_dir, &args.id, is_pinned)
            .await
            .map(|items| json!({ "kind": "workspaces", "items": items }))
    } else {
        set_pinned(runtime_dir, args.id, is_pinned)
            .await
            .map(|workspace| json!(workspace))
    };
    match result {
        Ok(value) if json_output => {
            println!(
                "{}",
                serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string())
            );
            0
        }
        Ok(_) => {
            println!(
                "workspace {}",
                if is_pinned { "pinned" } else { "unpinned" }
            );
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

/// Pin Workspace Tree: the workspace and every descendant, as the sidebar
/// applies it one workspace at a time.
async fn set_tree_pinned(
    runtime_dir: PathBuf,
    id: &str,
    is_pinned: bool,
) -> anyhow::Result<Vec<Workspace>> {
    let workspaces = crate::workspace_tree::all_workspaces(&runtime_dir).await?;
    if !workspaces.iter().any(|workspace| workspace.id == id) {
        anyhow::bail!("Workspace not found: {id}");
    }
    let mut updated = Vec::new();
    for workspace_id in crate::workspace_tree::tree_ids(&workspaces, id) {
        updated.push(set_pinned(runtime_dir.clone(), workspace_id, is_pinned).await?);
    }
    Ok(updated)
}

async fn set_pinned(
    runtime_dir: PathBuf,
    id: String,
    is_pinned: bool,
) -> anyhow::Result<Workspace> {
    let payload = json!({ "id": id, "isPinned": is_pinned });
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir).await? {
        return client.request("workspace.setPinned", &payload).await;
    }
    RuntimeStore::open(&runtime_dir)
        .await?
        .set_workspace_pinned(&id, is_pinned)
        .await
}
