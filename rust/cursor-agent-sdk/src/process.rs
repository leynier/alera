use crate::{CursorClient, CursorSdkError, ReadyHandshake};
use alera_agent_transport::{ManagedProcess, ProcessConfig};
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct CursorBridgeConfig {
    pub process: ProcessConfig,
    pub startup_timeout: Duration,
    pub client_timeout: Duration,
    pub allow_remote_endpoint: bool,
}

impl Default for CursorBridgeConfig {
    fn default() -> Self {
        Self {
            process: ProcessConfig::default(),
            startup_timeout: Duration::from_secs(30),
            client_timeout: Duration::from_secs(30),
            allow_remote_endpoint: false,
        }
    }
}

pub struct CursorBridge {
    process: ManagedProcess,
    client: CursorClient,
}

impl CursorBridge {
    pub async fn spawn(config: CursorBridgeConfig) -> Result<Self, CursorSdkError> {
        let mut process = ManagedProcess::spawn(config.process)
            .await
            .map_err(|error| CursorSdkError::Process(error.to_string()))?;
        let deadline = Instant::now() + config.startup_timeout;
        let ready = loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                let _ = process.close().await;
                return Err(CursorSdkError::Timeout {
                    operation: "cursor bridge ready handshake".into(),
                    timeout: config.startup_timeout,
                });
            }
            let line = tokio::time::timeout(remaining, process.next_stderr_line())
                .await
                .map_err(|_| CursorSdkError::Timeout {
                    operation: "cursor bridge ready handshake".into(),
                    timeout: config.startup_timeout,
                })?;
            let Some(line) = line else {
                let _ = process.close().await;
                return Err(CursorSdkError::Process(
                    "bridge exited before ready handshake".into(),
                ));
            };
            if let Some(result) = ReadyHandshake::parse_line(&line) {
                break result?;
            }
        };
        let client = CursorClient::from_ready_with_remote(
            ready,
            config.client_timeout,
            config.allow_remote_endpoint,
        )?;
        Ok(Self { process, client })
    }

    pub fn client(&self) -> &CursorClient {
        &self.client
    }

    pub async fn close(&mut self) -> Result<(), CursorSdkError> {
        let _ = self.client.shutdown(0).await;
        self.process
            .close()
            .await
            .map_err(|error| CursorSdkError::Process(error.to_string()))
    }

    pub fn pid(&self) -> Option<u32> {
        self.process.pid()
    }
}

pub fn process_config(
    executable: impl Into<std::path::PathBuf>,
    args: impl IntoIterator<Item = impl Into<std::ffi::OsString>>,
) -> ProcessConfig {
    ProcessConfig {
        executable: executable.into(),
        args: args.into_iter().map(Into::into).collect(),
        ..ProcessConfig::default()
    }
}
