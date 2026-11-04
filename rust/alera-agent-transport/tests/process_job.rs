//! An agent and everything it starts stop together on Windows. Each fake agent
//! below is the fixture leaving a copy of itself running, the way a CLI leaves
//! an MCP server behind. That grandchild holds a named pipe open, so its death
//! reads as end-of-file here, with no pid polling.
#![cfg(windows)]

use std::ffi::OsString;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use alera_agent_transport::{
    JsonLineProcess, JsonTransport, ManagedProcess, ProcessConfig, TransportError,
};
use alera_core::child_process::windowless_async_command;
use tokio::io::AsyncReadExt;
use tokio::net::windows::named_pipe::{NamedPipeServer, ServerOptions};

static NEXT_PIPE: AtomicU64 = AtomicU64::new(0);

const FIXTURE: &str = env!("CARGO_BIN_EXE_json-echo-fixture");
/// The agent exits once its input closes.
const EXITS_ON_EOF: &str = "exit-on-eof";
/// The agent ignores its input and never exits on its own.
const KEEPS_RUNNING: &str = "keep-running";

/// How long a stopped job may take to release the pipe.
const STOP_DEADLINE: Duration = Duration::from_secs(10);

struct HeldPipe {
    name: String,
    server: NamedPipeServer,
}

impl HeldPipe {
    fn new() -> Self {
        let name = format!(
            r"\\.\pipe\alera-process-job-{}-{}",
            std::process::id(),
            NEXT_PIPE.fetch_add(1, Ordering::Relaxed)
        );
        let server = ServerOptions::new()
            .first_pipe_instance(true)
            .create(&name)
            .unwrap();
        Self { name, server }
    }

    fn agent_args(&self, mode: &str) -> Vec<OsString> {
        vec![
            "--leave-grandchild".into(),
            self.name.clone().into(),
            mode.into(),
        ]
    }

    fn agent(&self, mode: &str, shutdown_timeout: Duration) -> ProcessConfig {
        ProcessConfig {
            executable: FIXTURE.into(),
            args: self.agent_args(mode),
            shutdown_timeout,
            ..ProcessConfig::default()
        }
    }

    /// Wait until the agent's grandchild opened the pipe.
    async fn opened(&self) {
        tokio::time::timeout(Duration::from_secs(5), self.server.connect())
            .await
            .expect("the agent did not start its grandchild")
            .unwrap();
    }

    /// Wait until the grandchild died and the pipe reads as closed.
    async fn assert_released(mut self) {
        let read = async {
            let mut buffer = [0_u8; 1];
            while let Ok(1..) = self.server.read(&mut buffer).await {}
        };
        tokio::time::timeout(STOP_DEADLINE, read)
            .await
            .expect("the agent's grandchild outlived its job");
    }
}

#[tokio::test]
async fn close_stops_what_the_agent_left_running() {
    let pipe = HeldPipe::new();
    let mut transport = JsonLineProcess::spawn(pipe.agent(EXITS_ON_EOF, Duration::from_secs(5)))
        .await
        .unwrap();
    pipe.opened().await;

    // The grandchild inherited stderr, so close only drains it in time when
    // the job is killed first.
    tokio::time::timeout(Duration::from_secs(5), transport.close())
        .await
        .unwrap()
        .unwrap();
    pipe.assert_released().await;
}

#[tokio::test]
async fn close_kills_a_job_whose_agent_ignores_its_input() {
    let pipe = HeldPipe::new();
    let mut transport =
        JsonLineProcess::spawn(pipe.agent(KEEPS_RUNNING, Duration::from_millis(200)))
            .await
            .unwrap();
    pipe.opened().await;

    let close = tokio::time::timeout(Duration::from_secs(5), transport.close())
        .await
        .unwrap();
    assert!(matches!(close, Err(TransportError::ShutdownTimeout { .. })));
    pipe.assert_released().await;
}

#[tokio::test]
async fn drop_stops_the_agent_job() {
    let pipe = HeldPipe::new();
    let transport = JsonLineProcess::spawn(pipe.agent(KEEPS_RUNNING, Duration::from_secs(5)))
        .await
        .unwrap();
    pipe.opened().await;

    drop(transport);
    pipe.assert_released().await;
}

#[tokio::test]
async fn managed_process_close_stops_the_agent_job() {
    let pipe = HeldPipe::new();
    let mut process = ManagedProcess::spawn(pipe.agent(KEEPS_RUNNING, Duration::from_secs(5)))
        .await
        .unwrap();
    pipe.opened().await;

    tokio::time::timeout(Duration::from_secs(5), process.close())
        .await
        .unwrap()
        .unwrap();
    pipe.assert_released().await;
}

/// TerminateProcess gives the owner no chance to clean up, which is what a
/// crashed or killed runtime host looks like to its agents. The kernel then
/// closes the owner's only job handle.
#[tokio::test]
async fn killed_owner_takes_the_agent_job_with_it() {
    let pipe = HeldPipe::new();
    let mut owner = windowless_async_command(FIXTURE);
    owner
        .arg("--own-agent")
        .arg(FIXTURE)
        .args(pipe.agent_args(KEEPS_RUNNING))
        .kill_on_drop(true);
    let mut owner = owner.spawn().unwrap();
    pipe.opened().await;

    owner.start_kill().unwrap();
    owner.wait().await.unwrap();
    pipe.assert_released().await;
}
