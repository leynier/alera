use super::*;
use alera_runtime_protocol::frame_codec::{encode_json_frame, encode_output_frame};
use alera_runtime_protocol::{
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
};
use tokio::net::TcpListener;

#[tokio::test]
async fn binary_connection_correlates_replies_and_delivers_raw_output() {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (read_half, mut write_half) = tokio::io::split(socket);
        let mut lines = BufReader::new(read_half).lines();
        let hello: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(hello["payload"]["clientKind"], "app");
        assert_eq!(hello["payload"]["binaryFrames"], true);
        write_half
            .write_all(
                format!(
                    "{}\n{}\n",
                    json!({"id": 1, "ok": true, "payload": {"binaryFrames": true}}),
                    json!({"event": BINARY_FRAMES_ENABLED_EVENT, "payload": {}})
                )
                .as_bytes(),
            )
            .await
            .unwrap();

        let request: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        write_half
            .write_all(&encode_output_frame("session-1", &[0xff, b'x']))
            .await
            .unwrap();
        write_half
            .write_all(
                &encode_json_frame(
                    &json!({"id": request["id"], "ok": true, "payload": {"value": 7}}),
                )
                .unwrap(),
            )
            .await
            .unwrap();
    });
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join(CONTROL_FILE_NAME),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "test-token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
            ],
        }))
        .unwrap(),
    )
    .unwrap();

    let mut connection =
        RuntimeClientConnection::connect(directory.path(), RuntimeClientOptions::default())
            .await
            .unwrap()
            .unwrap();
    let result = connection
        .handle
        .request("demo.read", &json!({}))
        .await
        .unwrap();
    assert_eq!(result, json!({"value": 7}));
    assert_eq!(
        connection.events.recv().await.unwrap(),
        RuntimeClientEvent::TerminalOutput {
            session_id: "session-1".to_string(),
            data: vec![0xff, b'x'],
        }
    );
    server.await.unwrap();
}

#[tokio::test]
async fn binary_connection_accepts_upgrade_before_hello_response() {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (read_half, mut write_half) = tokio::io::split(socket);
        let mut lines = BufReader::new(read_half).lines();
        let _: Value = serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        write_half
            .write_all(
                format!(
                    "{}\n",
                    json!({"event": BINARY_FRAMES_ENABLED_EVENT, "payload": {}})
                )
                .as_bytes(),
            )
            .await
            .unwrap();
        write_half
            .write_all(
                &encode_json_frame(
                    &json!({"id": 1, "ok": true, "payload": {"binaryFrames": true}}),
                )
                .unwrap(),
            )
            .await
            .unwrap();
    });
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join(CONTROL_FILE_NAME),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "test-token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
                RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
            ],
        }))
        .unwrap(),
    )
    .unwrap();

    let connection =
        RuntimeClientConnection::connect(directory.path(), RuntimeClientOptions::default())
            .await
            .unwrap()
            .unwrap();
    connection.handle.close().await;
    server.await.unwrap();
}

#[test]
fn newline_output_is_normalized_for_older_hosts() {
    let event = json!({
        "event": "output",
        "payload": {
            "sessionId": "s1",
            "dataBase64": BASE64_STANDARD.encode([0, 1, 2]),
        }
    });
    assert_eq!(
        normalize_json_event(event),
        Some(RuntimeClientEvent::TerminalOutput {
            session_id: "s1".to_string(),
            data: vec![0, 1, 2],
        })
    );
}
