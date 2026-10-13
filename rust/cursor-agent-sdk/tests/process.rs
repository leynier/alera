#![cfg(unix)]

use cursor_agent_sdk::{process_config, CursorBridge, CursorBridgeConfig};
use std::ffi::OsString;
use std::time::Duration;

#[tokio::test]
async fn bridge_process_parses_ready_line_and_keeps_external_runtime_boundary() {
    let script = r#"printf '%s\n' 'cursor-sdk-bridge ready {"schemaVersion":1,"serverVersion":"1","transport":"tcp","protocol":"connect","host":"127.0.0.1","port":1,"url":"http://127.0.0.1:1","authToken":"token"}' >&2; sleep 1"#;
    let config = CursorBridgeConfig {
        process: process_config("sh", [OsString::from("-c"), OsString::from(script)]),
        startup_timeout: Duration::from_secs(2),
        client_timeout: Duration::from_secs(1),
        allow_remote_endpoint: false,
    };
    let mut bridge = CursorBridge::spawn(config).await.unwrap();
    assert!(bridge.pid().is_some());
    bridge.close().await.unwrap();
}
