use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use alera_agent_transport::{JsonLineProcess, JsonTransport, ProcessConfig, TransportError};
use serde_json::{json, Value};

const PAYLOAD_BYTES: usize = 2 * 1024 * 1024;
static NEXT_GATE: AtomicU64 = AtomicU64::new(0);

struct InputGate {
    directory: PathBuf,
}

impl InputGate {
    fn new() -> Self {
        let directory = std::env::temp_dir().join(format!(
            "alera-json-write-{}-{}",
            std::process::id(),
            NEXT_GATE.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&directory).unwrap();
        Self { directory }
    }

    fn prefix_received(&self) -> PathBuf {
        self.directory.join("prefix-received")
    }

    fn resume(&self) {
        std::fs::write(self.directory.join("resume"), b"resume").unwrap();
    }

    fn completed_frames(&self) -> Value {
        serde_json::from_slice(&std::fs::read(self.directory.join("completed")).unwrap()).unwrap()
    }

    fn config(&self, timeout: Duration) -> ProcessConfig {
        ProcessConfig {
            executable: PathBuf::from(std::env::var("CARGO_BIN_EXE_json-echo-fixture").unwrap()),
            args: vec![
                "--partial-write-gate".into(),
                self.prefix_received().into_os_string(),
                self.directory.join("resume").into_os_string(),
            ],
            shutdown_timeout: timeout,
            ..ProcessConfig::default()
        }
    }
}

impl Drop for InputGate {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

async fn wait_for_path(path: &Path) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !path.exists() {
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .expect("child did not read a prefix");
}

async fn cancel_after_prefix(transport: &mut JsonLineProcess, gate: &InputGate, frame: Value) {
    let mut send = Box::pin(transport.send(frame));
    let prefix_received = gate.prefix_received();
    tokio::select! {
        result = &mut send => panic!("large send finished before the child resumed: {result:?}"),
        () = wait_for_path(&prefix_received) => {}
    }
    // The child holds its input after reading one byte, so the pipe cannot
    // accept the entire frame. Dropping send cancels a real partial write.
}

async fn received(transport: &mut JsonLineProcess) -> Option<Value> {
    tokio::time::timeout(Duration::from_secs(5), transport.recv())
        .await
        .unwrap()
        .unwrap()
}

async fn assert_two_ordered_frames(transport: &mut JsonLineProcess) {
    transport.send(json!({"op": "exit"})).await.unwrap();
    assert_eq!(
        received(transport).await,
        Some(json!({"id": 1, "received_bytes": PAYLOAD_BYTES}))
    );
    assert_eq!(
        received(transport).await,
        Some(json!({"id": 2, "received_bytes": 6}))
    );
    assert_eq!(received(transport).await, Some(json!({"finished": 2})));
    assert_eq!(received(transport).await, None);
}

#[tokio::test]
async fn different_send_finishes_the_cancelled_frame_before_the_new_frame() {
    let gate = InputGate::new();
    let mut transport = JsonLineProcess::spawn(gate.config(Duration::from_secs(5)))
        .await
        .unwrap();
    let first = json!({"id": 1, "value": "x".repeat(PAYLOAD_BYTES)});
    cancel_after_prefix(&mut transport, &gate, first).await;
    gate.resume();
    transport
        .send(json!({"id": 2, "value": "second"}))
        .await
        .unwrap();
    assert_two_ordered_frames(&mut transport).await;
}

#[tokio::test]
async fn identical_send_retries_the_cancelled_frame_without_duplicating_it() {
    let gate = InputGate::new();
    let mut transport = JsonLineProcess::spawn(gate.config(Duration::from_secs(5)))
        .await
        .unwrap();
    let first = json!({"id": 1, "value": "x".repeat(PAYLOAD_BYTES)});
    cancel_after_prefix(&mut transport, &gate, first.clone()).await;
    gate.resume();
    transport.send(first).await.unwrap();
    transport
        .send(json!({"id": 2, "value": "second"}))
        .await
        .unwrap();
    assert_two_ordered_frames(&mut transport).await;
}

#[tokio::test]
async fn close_finishes_the_cancelled_frame_and_reaps_the_child() {
    let gate = InputGate::new();
    let mut transport = JsonLineProcess::spawn(gate.config(Duration::from_secs(5)))
        .await
        .unwrap();
    let first = json!({"id": 1, "value": "x".repeat(PAYLOAD_BYTES)});
    cancel_after_prefix(&mut transport, &gate, first).await;
    gate.resume();
    tokio::time::timeout(Duration::from_secs(6), transport.close())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        gate.completed_frames(),
        json!([{"id": 1, "received_bytes": PAYLOAD_BYTES}])
    );
    assert!(matches!(
        transport.send(json!({})).await,
        Err(TransportError::Closed)
    ));
    assert!(matches!(
        transport.recv().await,
        Err(TransportError::Closed)
    ));
    transport.close().await.unwrap();
}

#[tokio::test]
async fn cancelled_close_keeps_the_transport_closed_and_can_resume_cleanup() {
    let gate = InputGate::new();
    let mut transport = JsonLineProcess::spawn(gate.config(Duration::from_secs(5)))
        .await
        .unwrap();
    let first = json!({"id": 1, "value": "x".repeat(PAYLOAD_BYTES)});
    cancel_after_prefix(&mut transport, &gate, first).await;
    assert!(
        tokio::time::timeout(Duration::from_millis(20), transport.close())
            .await
            .is_err()
    );
    assert!(matches!(
        transport.send(json!({})).await,
        Err(TransportError::Closed)
    ));
    gate.resume();
    transport.close().await.unwrap();
    assert_eq!(
        gate.completed_frames(),
        json!([{"id": 1, "received_bytes": PAYLOAD_BYTES}])
    );
}

#[tokio::test]
async fn cancelled_close_retains_the_child_while_waiting_for_exit() {
    let gate = InputGate::new();
    let hold_after_eof = gate.directory.join("hold-after-eof");
    std::fs::write(&hold_after_eof, b"hold").unwrap();
    let mut transport = JsonLineProcess::spawn(gate.config(Duration::from_secs(5)))
        .await
        .unwrap();
    let first = json!({"id": 1, "value": "x".repeat(PAYLOAD_BYTES)});
    cancel_after_prefix(&mut transport, &gate, first).await;
    gate.resume();
    {
        let mut close = Box::pin(transport.close());
        let completed = gate.directory.join("completed");
        tokio::select! {
            result = &mut close => panic!("close completed before the child exited: {result:?}"),
            () = wait_for_path(&completed) => {}
        }
    }
    assert!(matches!(
        transport.send(json!({})).await,
        Err(TransportError::Closed)
    ));
    std::fs::remove_file(hold_after_eof).unwrap();
    transport.close().await.unwrap();
    assert!(gate.directory.join("exit-ready").exists());
    assert_eq!(
        gate.completed_frames(),
        json!([{"id": 1, "received_bytes": PAYLOAD_BYTES}])
    );
}
