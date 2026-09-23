use std::path::PathBuf;

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::json;

use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn run(runtime_dir: PathBuf, json_output: bool, id: String, archived: bool) -> i32 {
    match set_archived(runtime_dir, id, archived).await {
        Ok(workspace) if json_output => {
            println!(
                "{}",
                serde_json::to_string_pretty(&workspace).unwrap_or_else(|_| "{}".to_string())
            );
            0
        }
        Ok(_) => {
            println!(
                "workspace {}",
                if archived { "archived" } else { "unarchived" }
            );
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

async fn set_archived(
    runtime_dir: PathBuf,
    id: String,
    archived: bool,
) -> anyhow::Result<Workspace> {
    if archived {
        let payload = json!({ "workspaceId": id });
        if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir).await? {
            return client.request("workspace.archive", &payload).await;
        }
        return RuntimeStore::open(&runtime_dir)
            .await?
            .set_workspace_archived(&id, true)
            .await;
    }
    let payload = json!({ "workspaceId": id });
    if let Some(mut client) = RuntimeHostRpcClient::connect(&runtime_dir).await? {
        return client.request("workspace.unarchive", &payload).await;
    }
    RuntimeStore::open(&runtime_dir)
        .await?
        .set_workspace_archived(&id, false)
        .await
}
