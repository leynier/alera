use std::path::Path;

use anyhow::{anyhow, Result};
use serde_json::json;

use super::RuntimeHostRpcClient;

pub(super) async fn connect_or_start_persistent(
    runtime_dir: &Path,
) -> Result<RuntimeHostRpcClient> {
    let mut client = match RuntimeHostRpcClient::connect(runtime_dir).await? {
        Some(client) => client,
        None => RuntimeHostRpcClient::start(runtime_dir, None, true).await?,
    };
    let status = client.request_value("status.get", &json!({})).await?;
    if status
        .get("persistent")
        .and_then(serde_json::Value::as_bool)
        == Some(true)
    {
        return Ok(client);
    }
    let promoted = client
        .request_value("host.promotePersistent", &json!({}))
        .await?;
    if promoted
        .get("persistent")
        .and_then(serde_json::Value::as_bool)
        != Some(true)
    {
        return Err(anyhow!(
            "runtime host did not confirm persistent lifecycle mode"
        ));
    }
    Ok(client)
}

#[cfg(test)]
mod tests {
    use serde_json::Value;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    use super::*;
    use crate::terminal_host::protocol::{
        PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    };

    #[tokio::test]
    async fn existing_host_is_promoted_over_the_same_connection() {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let (read_half, mut write_half) = socket.into_split();
            let mut lines = BufReader::new(read_half).lines();
            let mut request_types = Vec::new();
            for payload in [
                json!({}),
                json!({"persistent": false}),
                json!({"persistent": true}),
            ] {
                let line = lines.next_line().await.unwrap().unwrap();
                let request: Value = serde_json::from_str(&line).unwrap();
                request_types.push(request["type"].as_str().unwrap().to_string());
                let response = json!({
                    "id": request["id"],
                    "ok": true,
                    "payload": payload,
                });
                let mut bytes = serde_json::to_vec(&response).unwrap();
                bytes.push(b'\n');
                write_half.write_all(&bytes).await.unwrap();
            }
            request_types
        });
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("host.json"),
            serde_json::to_vec(&json!({
                "protocolVersion": PROTOCOL_VERSION,
                "port": port,
                "token": "token",
                "persistent": false,
                "runtimeCapabilities": [
                    RUNTIME_HOST_CAPABILITY,
                    RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                ],
            }))
            .unwrap(),
        )
        .unwrap();

        let client = connect_or_start_persistent(dir.path()).await.unwrap();
        drop(client);

        assert_eq!(
            server.await.unwrap(),
            ["hello", "status.get", "host.promotePersistent"]
        );
    }

    #[tokio::test]
    async fn already_persistent_host_does_not_need_the_new_promotion_verb() {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            let (socket, _) = listener.accept().await.unwrap();
            let (read_half, mut write_half) = socket.into_split();
            let mut lines = BufReader::new(read_half).lines();
            let mut request_types = Vec::new();
            for payload in [json!({}), json!({"persistent": true})] {
                let line = lines.next_line().await.unwrap().unwrap();
                let request: Value = serde_json::from_str(&line).unwrap();
                request_types.push(request["type"].as_str().unwrap().to_string());
                let response = json!({
                    "id": request["id"],
                    "ok": true,
                    "payload": payload,
                });
                let mut bytes = serde_json::to_vec(&response).unwrap();
                bytes.push(b'\n');
                write_half.write_all(&bytes).await.unwrap();
            }
            request_types
        });
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("host.json"),
            serde_json::to_vec(&json!({
                "protocolVersion": PROTOCOL_VERSION,
                "port": port,
                "token": "token",
                "persistent": true,
                "runtimeCapabilities": [
                    RUNTIME_HOST_CAPABILITY,
                    RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                ],
            }))
            .unwrap(),
        )
        .unwrap();

        let client = connect_or_start_persistent(dir.path()).await.unwrap();
        drop(client);

        assert_eq!(server.await.unwrap(), ["hello", "status.get"]);
    }
}
