use std::path::PathBuf;

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::json;

use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn run(runtime_dir: PathBuf, json_output: bool, id: String, is_pinned: bool) -> i32 {
    match set_pinned(runtime_dir, id, is_pinned).await {
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
