use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Duration;

use alera_agent_transport::{ManagedProcess, ProcessConfig, DEFAULT_MAX_FRAME_BYTES};

#[tokio::test]
async fn managed_process_reads_stdout_and_stderr_and_reaps_child() {
    let executable = PathBuf::from(env!("CARGO_BIN_EXE_managed-process-fixture"));
    let mut process = ManagedProcess::spawn(ProcessConfig {
        executable,
        env: BTreeMap::new(),
        max_frame_bytes: DEFAULT_MAX_FRAME_BYTES,
        shutdown_timeout: Duration::from_secs(2),
        ..ProcessConfig::default()
    })
    .await
    .unwrap();
    assert!(process.pid().is_some());
    assert_eq!(
        process.next_stdout_line().await.as_deref(),
        Some("stdout-ready")
    );
    assert_eq!(
        process.next_stderr_line().await.as_deref(),
        Some("stderr-ready")
    );
    process.close().await.unwrap();
    assert!(process.pid().is_none());
    assert!(process.next_stdout_line().await.is_none());
}
