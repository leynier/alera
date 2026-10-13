use std::path::PathBuf;
use std::time::Duration;

use alera_agent_transport::{
    JsonLineProcess, JsonTransport, MockTransport, ProcessConfig, TransportError,
};
use serde_json::json;

fn fixture() -> PathBuf {
    PathBuf::from(std::env::var("CARGO_BIN_EXE_json-echo-fixture").unwrap())
}

fn config() -> ProcessConfig {
    ProcessConfig {
        executable: fixture(),
        shutdown_timeout: Duration::from_secs(1),
        ..ProcessConfig::default()
    }
}

#[tokio::test]
async fn fragmented_and_multiple_frames_are_decoded() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();

    transport
        .send(json!({"op": "fragmented", "value": "hello"}))
        .await
        .unwrap();
    assert_eq!(
        transport.recv().await.unwrap(),
        Some(json!({"fragmented": "hello"}))
    );

    transport.send(json!({"op": "multi"})).await.unwrap();
    assert_eq!(transport.recv().await.unwrap(), Some(json!({"n": 1})));
    assert_eq!(transport.recv().await.unwrap(), Some(json!({"n": 2})));
    transport.close().await.unwrap();
}

#[tokio::test]
async fn final_frame_without_newline_is_delivered_before_eof() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport
        .send(json!({"op": "no-final-newline"}))
        .await
        .unwrap();

    assert_eq!(transport.recv().await.unwrap(), Some(json!({"done": true})));
    assert_eq!(transport.recv().await.unwrap(), None);
}

#[tokio::test]
async fn invalid_json_closes_the_process_and_reports_the_parse_error() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport.send(json!({"op": "invalid"})).await.unwrap();

    assert!(matches!(
        transport.recv().await,
        Err(TransportError::InvalidJson { .. })
    ));
    assert!(matches!(
        transport.send(json!({"op": "echo"})).await,
        Err(TransportError::Closed)
    ));
}

#[tokio::test]
async fn invalid_utf8_is_reported_before_json_decoding() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport.send(json!({"op": "invalid-utf8"})).await.unwrap();

    assert!(matches!(
        transport.recv().await,
        Err(TransportError::InvalidUtf8 { .. })
    ));
}

#[tokio::test]
async fn oversized_input_is_rejected_before_buffer_growth() {
    let mut process_config = config();
    process_config.max_frame_bytes = 32;
    let mut transport = JsonLineProcess::spawn(process_config).await.unwrap();
    transport.send(json!({"op": "oversized"})).await.unwrap();

    assert!(matches!(
        transport.recv().await,
        Err(TransportError::FrameTooLarge { limit: 32, .. })
    ));
}

#[tokio::test]
async fn oversized_final_frame_without_newline_is_rejected() {
    let mut process_config = config();
    process_config.max_frame_bytes = 32;
    let mut transport = JsonLineProcess::spawn(process_config).await.unwrap();
    transport.send(json!({"op": "f"})).await.unwrap();

    assert!(matches!(
        transport.recv().await,
        Err(TransportError::FrameTooLarge { limit: 32, .. })
    ));
}

#[tokio::test]
async fn oversized_frame_after_buffered_valid_frame_is_rejected() {
    let mut process_config = config();
    process_config.max_frame_bytes = 16;
    let mut transport = JsonLineProcess::spawn(process_config).await.unwrap();
    transport.send(json!({"op": "b"})).await.unwrap();

    assert_eq!(transport.recv().await.unwrap(), Some(json!({"ok": true})));
    assert!(matches!(
        transport.recv().await,
        Err(TransportError::FrameTooLarge { limit: 16, .. })
    ));
}

#[tokio::test]
async fn stderr_is_drained_while_stdout_is_read() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport.send(json!({"op": "stderr-flood"})).await.unwrap();
    let response = tokio::time::timeout(Duration::from_secs(2), transport.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response, Some(json!({"stderr": "drained"})));
    transport.close().await.unwrap();
}

#[tokio::test]
async fn stdout_drain_allows_large_send_before_child_reads_it() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport
        .send(json!({"op": "write-before-read"}))
        .await
        .unwrap();

    let large_value = "r".repeat(128 * 1024);
    tokio::time::timeout(
        Duration::from_secs(5),
        transport.send(json!({"op": "large-request", "value": large_value})),
    )
    .await
    .unwrap()
    .unwrap();

    let preface = transport.recv().await.unwrap().unwrap();
    assert_eq!(preface["preface"].as_str().unwrap().len(), 128 * 1024);
    assert_eq!(
        transport.recv().await.unwrap(),
        Some(json!({"received_bytes": 128 * 1024}))
    );
    transport.close().await.unwrap();
}

#[tokio::test]
async fn blocked_write_times_out_and_closes_the_child() {
    let mut process_config = config();
    process_config.max_frame_bytes = 8 * 1024 * 1024;
    process_config.shutdown_timeout = Duration::from_millis(50);
    let mut transport = JsonLineProcess::spawn(process_config).await.unwrap();
    transport.send(json!({"op": "sleep"})).await.unwrap();

    let payload = "w".repeat(2 * 1024 * 1024);
    let error = tokio::time::timeout(
        Duration::from_secs(2),
        transport.send(json!({"op": "blocked", "value": payload})),
    )
    .await
    .unwrap()
    .unwrap_err();
    assert!(matches!(
        error,
        TransportError::IoTimeout {
            operation: "write stdin",
            ..
        }
    ));
    assert!(matches!(
        transport.send(json!({"op": "echo"})).await,
        Err(TransportError::Closed)
    ));
}

#[tokio::test]
async fn nonzero_exit_is_explicit() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport.send(json!({"op": "exit-nonzero"})).await.unwrap();

    assert!(matches!(
        transport.recv().await,
        Err(TransportError::ProcessExited { code: Some(7), .. })
    ));
}

#[tokio::test]
async fn cancelled_receive_can_be_followed_by_bounded_close() {
    let mut transport = JsonLineProcess::spawn(config()).await.unwrap();
    transport.send(json!({"op": "sleep"})).await.unwrap();

    let timed_out = tokio::time::timeout(Duration::from_millis(20), transport.recv())
        .await
        .is_err();
    assert!(timed_out);

    let close = tokio::time::timeout(Duration::from_secs(2), transport.close())
        .await
        .unwrap();
    assert!(matches!(close, Err(TransportError::ShutdownTimeout { .. })));
}

#[tokio::test]
async fn mock_captures_writes_and_replays_scripted_values() {
    let mut transport = MockTransport::new([json!({"ok": true})]);
    transport.send(json!({"request": 1})).await.unwrap();
    assert_eq!(transport.recv().await.unwrap(), Some(json!({"ok": true})));
    assert_eq!(transport.recv().await.unwrap(), None);
    assert_eq!(transport.writes(), &[json!({"request": 1})]);
    transport.close().await.unwrap();
    assert!(transport.is_closed());
}

#[tokio::test]
async fn empty_executable_is_rejected_without_spawning() {
    let error = JsonLineProcess::spawn(ProcessConfig::default())
        .await
        .unwrap_err();
    assert!(matches!(error, TransportError::InvalidConfig { .. }));
}
