use super::*;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
};

fn control(capabilities: &[&str]) -> RuntimeHostControl {
    RuntimeHostControl {
        protocol_version: PROTOCOL_VERSION,
        port: 1234,
        token: "token".to_string(),
        runtime_capabilities: capabilities.iter().map(|value| value.to_string()).collect(),
    }
}

#[test]
fn required_capability_must_be_advertised() {
    let base = [
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    ];
    assert!(control(&base).is_usable(None));
    assert!(!control(&base).is_usable(Some(RUNTIME_HOST_ORCHESTRATION_CAPABILITY)));
    assert!(!control(&base).is_usable(Some(RUNTIME_HOST_MOBILE_CAPABILITY)));

    let with_orchestration = [
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    ];
    assert!(control(&with_orchestration).is_usable(Some(RUNTIME_HOST_ORCHESTRATION_CAPABILITY)));
    assert!(!control(&with_orchestration).is_usable(Some(
        RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY
    )));

    let with_terminal_inspection = [
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
        RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY,
    ];
    assert!(control(&with_terminal_inspection).is_usable(Some(
        RUNTIME_HOST_ORCHESTRATION_TERMINAL_INSPECTION_CAPABILITY
    )));

    let with_mobile = [
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
        RUNTIME_HOST_MOBILE_CAPABILITY,
    ];
    assert!(control(&with_mobile).is_usable(Some(RUNTIME_HOST_MOBILE_CAPABILITY)));
}

#[test]
fn cli_hello_identifies_the_cli_client() {
    let payload = control_hello_payload(&control(&[
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    ]));

    assert_eq!(payload["clientKind"], json!("cli"));
    assert!(payload.get("supportedTabKinds").is_none());
}

#[tokio::test]
async fn live_host_missing_required_capability_requires_restart() {
    let (port, server) = start_hello_server().await;
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join(CONTROL_FILE_NAME),
        serde_json::to_string(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
                RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
            ],
        }))
        .unwrap(),
    )
    .unwrap();

    let error = match RuntimeHostRpcClient::connect_with_required_capability(
        dir.path(),
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    )
    .await
    {
        Ok(_) => panic!("expected a restart-required capability error"),
        Err(error) => error,
    };

    assert!(error.to_string().contains("Restart Alera"));
    server.await.unwrap();
}

#[tokio::test]
async fn live_host_missing_baseline_capability_requires_restart_for_orchestration() {
    let (port, server) = start_hello_server().await;
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(
        dir.path().join(CONTROL_FILE_NAME),
        serde_json::to_string(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "token",
            "runtimeCapabilities": [
                RUNTIME_HOST_CAPABILITY,
                RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
            ],
        }))
        .unwrap(),
    )
    .unwrap();

    let error = match RuntimeHostRpcClient::connect_with_required_capability(
        dir.path(),
        RUNTIME_HOST_ORCHESTRATION_CAPABILITY,
    )
    .await
    {
        Ok(_) => panic!("expected a restart-required capability error"),
        Err(error) => error,
    };

    assert!(error.to_string().contains("Restart Alera"));
    server.await.unwrap();
}

async fn start_hello_server() -> (u16, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
        .await
        .unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (read_half, mut write_half) = socket.into_split();
        let mut lines = BufReader::new(read_half).lines();
        let line = lines.next_line().await.unwrap().unwrap();
        let request: Value = serde_json::from_str(&line).unwrap();
        let response = json!({
            "id": request["id"],
            "ok": true,
            "payload": {},
        });
        let mut bytes = serde_json::to_vec(&response).unwrap();
        bytes.push(b'\n');
        write_half.write_all(&bytes).await.unwrap();
    });
    (port, server)
}
