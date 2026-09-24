use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::runtime_host_client::RuntimeHostRpcClient;

pub async fn request_with_workspace_buffer_guard(
    client: &mut RuntimeHostRpcClient,
    operation: &str,
    payload: &Value,
) -> Result<Value> {
    let workspace_id = payload
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("Workspace ID is required"))?;
    let mut status = client
        .request_value(
            "workspace.bufferGuard.acquire",
            &json!({"id": workspace_id, "operation": operation, "expectedInstanceId": payload.get("expectedInstanceId")}),
        )
        .await?;
    let id = status
        .get("guardId")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("Runtime did not return a buffer guard"))?
        .to_string();
    let result = async {
        if let Some(expected) = payload.get("expectedInstanceId").and_then(Value::as_str) {
            if status.get("workspaceInstanceId").and_then(Value::as_str) != Some(expected) {
                bail!("The runtime did not verify the expected workspace instance. Update the owner runtime or refresh the task before retrying.");
            }
        }
        tokio::time::timeout(std::time::Duration::from_secs(20), async {
            while status.get("ready") != Some(&Value::Bool(true)) {
                let blockers = status.get("blockers").and_then(Value::as_array).ok_or_else(|| anyhow!("Runtime did not verify editor buffers"))?;
                if !blockers.is_empty() {
                    bail!("Resolve editor buffers on the connected clients before continuing: {}", blockers.iter().map(|blocker| format!("{}: {}", blocker["path"].as_str().unwrap_or("editor"), blocker["reason"].as_str().unwrap_or("verification failed"))).collect::<Vec<_>>().join("; "));
                }
                if status.get("disconnectedClients").and_then(Value::as_u64) != Some(0) { bail!("A client disconnected during buffer verification. Prepare the operation again."); }
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                status = client.request_value("workspace.bufferGuard.status", &json!({"guardId": id})).await?;
            }
            Ok::<_, anyhow::Error>(())
        }).await.map_err(|_| anyhow!("Some connected editors did not respond. The workspace was preserved."))??;
        let mut request = payload.clone();
        request["bufferGuardId"] = json!(id);
        client.request_value(&format!("workspace.{operation}"), &request).await
    }.await;
    // A started mutation keeps its guard until completion even if the RPC
    // timed out. An unclaimed preparation can safely release or expire.
    let _ = client
        .request_value("workspace.bufferGuard.release", &json!({"guardId": id}))
        .await;
    result
}
