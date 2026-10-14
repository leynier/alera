use crate::Generation;
use alera_agent_transport::{ManagedProcess, ProcessConfig, TransportError};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use thiserror::Error;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use uuid::Uuid;

const DEFAULT_HOSTNAME: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 4096;
const DEFAULT_STARTUP_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_STARTUP_OUTPUT: usize = 8 * 1024;

#[derive(Debug, Clone)]
pub struct OpenCodeServerConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub hostname: String,
    pub port: u16,
    pub startup_timeout: Duration,
    pub max_frame_bytes: usize,
    pub shutdown_timeout: Duration,
    pub password: Option<String>,
    pub generation: Generation,
}

impl Default for OpenCodeServerConfig {
    fn default() -> Self {
        Self {
            executable: PathBuf::from("opencode"),
            args: vec![OsString::from("serve")],
            cwd: None,
            env: BTreeMap::new(),
            hostname: DEFAULT_HOSTNAME.into(),
            port: DEFAULT_PORT,
            startup_timeout: DEFAULT_STARTUP_TIMEOUT,
            max_frame_bytes: 1024 * 1024,
            shutdown_timeout: Duration::from_secs(5),
            password: None,
            generation: Generation::V2,
        }
    }
}

#[derive(Debug, Error)]
pub enum OpenCodeServerError {
    #[error("OpenCode server transport failed: {0}")]
    Transport(String),
    #[error("OpenCode server exited before reporting its listening URL")]
    Exited,
    #[error("OpenCode server startup timed out after {0:?}")]
    StartupTimeout(Duration),
    #[error("OpenCode server output did not contain a valid listening URL")]
    InvalidOutput,
}

impl From<TransportError> for OpenCodeServerError {
    fn from(error: TransportError) -> Self {
        Self::Transport(error.to_string())
    }
}

pub struct OpenCodeServer {
    url: String,
    password: Option<String>,
    process: Arc<Mutex<Option<ManagedProcess>>>,
    drain_task: Option<JoinHandle<()>>,
    closed: bool,
}

impl std::fmt::Debug for OpenCodeServer {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("OpenCodeServer")
            .field("url", &self.url)
            .field("password_set", &self.password.is_some())
            .field("closed", &self.closed)
            .finish_non_exhaustive()
    }
}

impl OpenCodeServer {
    pub async fn spawn(config: OpenCodeServerConfig) -> Result<Self, OpenCodeServerError> {
        let mut args = config.args.clone();
        add_flag(&mut args, "--hostname=", &config.hostname);
        add_flag(&mut args, "--port=", &config.port.to_string());
        let mut env = config.env.clone();
        let password = match config.generation {
            Generation::V2 => {
                let password = config
                    .password
                    .clone()
                    .or_else(|| {
                        env.get(&OsString::from("OPENCODE_PASSWORD"))
                            .and_then(|value| value.to_str())
                            .map(str::to_owned)
                    })
                    .unwrap_or_else(|| format!("opencode-{}", Uuid::new_v4().simple()));
                env.remove(&OsString::from("OPENCODE_SERVER_PASSWORD"));
                env.insert(
                    OsString::from("OPENCODE_PASSWORD"),
                    OsString::from(password.as_str()),
                );
                Some(password)
            }
            Generation::Legacy1 => {
                let password = config.password.clone().or_else(|| {
                    env.get(&OsString::from("OPENCODE_SERVER_PASSWORD"))
                        .and_then(|value| value.to_str())
                        .map(str::to_owned)
                });
                if let Some(password) = &password {
                    if config.password.is_some() {
                        env.insert(
                            OsString::from("OPENCODE_SERVER_PASSWORD"),
                            OsString::from(password.as_str()),
                        );
                    } else {
                        env.entry(OsString::from("OPENCODE_SERVER_PASSWORD"))
                            .or_insert_with(|| OsString::from(password.as_str()));
                    }
                }
                password
            }
        };
        let process = ManagedProcess::spawn(ProcessConfig {
            executable: config.executable,
            args,
            cwd: config.cwd,
            env,
            max_frame_bytes: config.max_frame_bytes,
            shutdown_timeout: config.shutdown_timeout,
        })
        .await?;
        let deadline = Instant::now() + config.startup_timeout;
        let mut process = process;
        let mut output = String::new();
        let url = loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                let _ = process.close().await;
                return Err(OpenCodeServerError::StartupTimeout(config.startup_timeout));
            }
            let line = match tokio::time::timeout(remaining, process.next_stdout_line()).await {
                Ok(line) => line,
                Err(_) => {
                    let _ = process.close().await;
                    return Err(OpenCodeServerError::StartupTimeout(config.startup_timeout));
                }
            };
            let Some(line) = line else {
                let _ = process.close().await;
                return Err(OpenCodeServerError::Exited);
            };
            output.push_str(&line);
            output.push('\n');
            if output.len() > MAX_STARTUP_OUTPUT {
                let keep_from = output.len() - MAX_STARTUP_OUTPUT;
                output.drain(..keep_from);
            }
            if let Some(url) = parse_server_url(&line) {
                break url;
            }
        };
        let process = Arc::new(Mutex::new(Some(process)));
        let drain_process = Arc::clone(&process);
        let drain_task = tokio::spawn(async move {
            loop {
                let line = {
                    let mut guard = drain_process.lock().await;
                    let Some(process) = guard.as_mut() else {
                        return;
                    };
                    process.next_stdout_line().await
                };
                if line.is_none() {
                    return;
                }
            }
        });
        Ok(Self {
            url,
            password,
            process,
            drain_task: Some(drain_task),
            closed: false,
        })
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    pub fn password(&self) -> Option<&str> {
        self.password.as_deref()
    }

    pub fn client_config(&self, mut config: crate::ClientConfig) -> crate::ClientConfig {
        config.base_url = self.url.clone();
        config.password = self.password.clone();
        config
    }

    pub async fn close(&mut self) -> Result<(), OpenCodeServerError> {
        if self.closed {
            return Ok(());
        }
        self.closed = true;
        if let Some(task) = self.drain_task.take() {
            task.abort();
        }
        let mut guard = self.process.lock().await;
        if let Some(process) = guard.as_mut() {
            process.close().await?;
        }
        *guard = None;
        Ok(())
    }
}

impl Drop for OpenCodeServer {
    fn drop(&mut self) {
        if let Some(task) = self.drain_task.take() {
            task.abort();
        }
    }
}

fn add_flag(args: &mut Vec<OsString>, prefix: &str, value: &str) {
    if args
        .iter()
        .filter_map(|arg| arg.to_str())
        .any(|arg| arg == prefix.trim_end_matches('=') || arg.starts_with(prefix))
    {
        return;
    }
    args.push(OsString::from(format!("{prefix}{value}")));
}

fn parse_server_url(line: &str) -> Option<String> {
    let lower = line.to_ascii_lowercase();
    let marker = "server listening on";
    let start = lower.find(marker)? + marker.len();
    let candidate = line[start..].split_whitespace().next()?.trim();
    if candidate.starts_with("http://") || candidate.starts_with("https://") {
        Some(candidate.trim_end_matches('/').to_owned())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::parse_server_url;

    #[test]
    fn parses_server_listening_marker() {
        assert_eq!(
            parse_server_url("INFO server listening on http://127.0.0.1:4096"),
            Some("http://127.0.0.1:4096".into())
        );
    }
}
