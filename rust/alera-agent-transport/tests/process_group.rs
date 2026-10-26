//! An agent and everything it starts stop together. Each fake agent below is
//! `/bin/sh` leaving a `sleep` running, the way a CLI leaves an MCP server
//! behind. Every process that must stop holds a FIFO open for writing, so its
//! death reads as end-of-file here, with no pid polling.
#![cfg(unix)]

use std::ffi::OsString;
use std::io::Read;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use alera_agent_transport::{
    JsonLineProcess, JsonTransport, ManagedProcess, ProcessConfig, TransportError,
};
use alera_core::child_process::windowless_async_command;
use tokio::sync::oneshot;

static NEXT_FIFO: AtomicU64 = AtomicU64::new(0);

/// Exits once its input closes, leaving a child behind.
const LEAVES_A_CHILD: &str = "sleep 600 > \"$1\" & cat > /dev/null";
/// Ignores its input, and both it and its child hold the FIFO.
const KEEPS_RUNNING: &str = "sleep 600 > \"$1\" & exec sleep 600 > \"$1\"";
/// Like `KEEPS_RUNNING`, but nothing in it stops for SIGTERM.
const IGNORES_SIGTERM: &str = "trap '' TERM; sleep 600 > \"$1\" & exec sleep 600 > \"$1\"";

/// How long a stopped group may take to release the FIFO.
const STOP_DEADLINE: Duration = Duration::from_secs(10);

struct Fifo {
    directory: PathBuf,
}

impl Fifo {
    fn new() -> Self {
        let directory = std::env::temp_dir().join(format!(
            "alera-process-group-{}-{}",
            std::process::id(),
            NEXT_FIFO.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&directory).unwrap();
        let fifo = Self { directory };
        let path =
            std::ffi::CString::new(fifo.path().into_os_string().into_encoded_bytes()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
        fifo
    }

    fn path(&self) -> PathBuf {
        self.directory.join("alive")
    }

    fn agent(&self, script: &str, shutdown_timeout: Duration) -> ProcessConfig {
        ProcessConfig {
            executable: "/bin/sh".into(),
            args: vec![
                "-c".into(),
                script.into(),
                "agent".into(),
                self.path().into(),
            ],
            shutdown_timeout,
            ..ProcessConfig::default()
        }
    }

    /// Wait until the agent's processes opened the FIFO, and return a receiver
    /// that resolves once every one of them has closed it. A plain thread
    /// reads it so a failing test is not held up by a blocked reader.
    async fn opened(&self) -> oneshot::Receiver<()> {
        let path = self.path();
        let (opened_tx, opened) = oneshot::channel();
        let (closed_tx, closed) = oneshot::channel();
        std::thread::spawn(move || {
            let mut fifo = std::fs::File::open(path).unwrap();
            let _ = opened_tx.send(());
            let _ = fifo.read_to_end(&mut Vec::new());
            let _ = closed_tx.send(());
        });
        tokio::time::timeout(Duration::from_secs(5), opened)
            .await
            .expect("the agent did not start")
            .unwrap();
        closed
    }
}

impl Drop for Fifo {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
    }
}

async fn assert_stopped(closed: oneshot::Receiver<()>) {
    tokio::time::timeout(STOP_DEADLINE, closed)
        .await
        .expect("the agent's process group outlived it")
        .unwrap();
}

#[tokio::test]
async fn close_stops_what_the_agent_left_running() {
    let fifo = Fifo::new();
    let mut transport = JsonLineProcess::spawn(fifo.agent(LEAVES_A_CHILD, Duration::from_secs(5)))
        .await
        .unwrap();
    let closed = fifo.opened().await;

    // The leftover child inherited stderr, so close only drains it in time
    // when the child is stopped first.
    tokio::time::timeout(Duration::from_secs(5), transport.close())
        .await
        .unwrap()
        .unwrap();
    assert_stopped(closed).await;
}

#[tokio::test]
async fn close_kills_a_group_that_ignores_sigterm() {
    let fifo = Fifo::new();
    let mut transport =
        JsonLineProcess::spawn(fifo.agent(IGNORES_SIGTERM, Duration::from_millis(200)))
            .await
            .unwrap();
    let closed = fifo.opened().await;

    let close = tokio::time::timeout(Duration::from_secs(5), transport.close())
        .await
        .unwrap();
    assert!(matches!(close, Err(TransportError::ShutdownTimeout { .. })));
    assert_stopped(closed).await;
}

#[tokio::test]
async fn drop_stops_the_agent_group() {
    let fifo = Fifo::new();
    let transport = JsonLineProcess::spawn(fifo.agent(KEEPS_RUNNING, Duration::from_secs(5)))
        .await
        .unwrap();
    let closed = fifo.opened().await;

    drop(transport);
    assert_stopped(closed).await;
}

#[tokio::test]
async fn managed_process_close_stops_the_agent_group() {
    let fifo = Fifo::new();
    let mut process = ManagedProcess::spawn(fifo.agent(KEEPS_RUNNING, Duration::from_secs(5)))
        .await
        .unwrap();
    let closed = fifo.opened().await;

    tokio::time::timeout(Duration::from_secs(5), process.close())
        .await
        .unwrap()
        .unwrap();
    assert_stopped(closed).await;
}

/// SIGKILL gives the owner no chance to clean up, which is what a crashed or
/// killed runtime host looks like to its agents.
#[tokio::test]
async fn killed_owner_takes_the_agent_group_with_it() {
    let fifo = Fifo::new();
    let mut owner = windowless_async_command(env!("CARGO_BIN_EXE_json-echo-fixture"));
    owner
        .args([
            OsString::from("--own-agent"),
            "-c".into(),
            KEEPS_RUNNING.into(),
            "agent".into(),
            fifo.path().into(),
        ])
        .kill_on_drop(true);
    let mut owner = owner.spawn().unwrap();
    let closed = fifo.opened().await;

    owner.start_kill().unwrap();
    owner.wait().await.unwrap();
    assert_stopped(closed).await;
}
