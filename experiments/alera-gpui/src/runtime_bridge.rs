use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use alera_core::child_process::detached_windowless_async_command;
use alera_runtime_client::{
    RuntimeClientConnection, RuntimeClientEvent, RuntimeClientHandle, RuntimeClientOptions,
};
use async_channel::{Receiver, Sender};
use serde_json::Value;

const EVENT_CAPACITY: usize = 256;
const RECONNECT_DELAY: Duration = Duration::from_secs(2);
const HOST_STARTUP_TIMEOUT: Duration = Duration::from_secs(30);
const HOST_STARTUP_POLL: Duration = Duration::from_millis(100);

#[derive(Clone, Debug)]
pub struct RuntimeHostStartConfig {
    pub empty_shutdown_delay_seconds: u64,
    pub detached_session_shutdown_delay_seconds: u64,
    pub scrollback_bytes: u64,
    pub login_shell: bool,
    pub crash_reporting: bool,
}

#[derive(Clone, Debug)]
pub enum BridgeEvent {
    Connected,
    Unavailable,
    Notification { name: String, payload: Value },
    TerminalOutput { session_id: String, data: Vec<u8> },
    Disconnected { reason: String },
}

#[derive(Clone)]
pub struct RuntimeBridge {
    commands: Sender<BridgeCommand>,
    events: Arc<Receiver<BridgeEvent>>,
}

enum BridgeCommand {
    Request {
        request_type: String,
        payload: Value,
        deadline: Duration,
        reply: Sender<Result<Value, String>>,
    },
    OrderedRequest {
        request_type: String,
        payload: Value,
        deadline: Duration,
    },
    StartHost {
        config: RuntimeHostStartConfig,
        reply: Sender<Result<(), String>>,
    },
    Close,
}

impl RuntimeBridge {
    pub fn start(runtime_dir: PathBuf) -> Self {
        let (command_tx, command_rx) = async_channel::unbounded();
        let (event_tx, event_rx) = async_channel::bounded(EVENT_CAPACITY);
        thread::Builder::new()
            .name("alera-gpui-runtime".to_string())
            .spawn(move || {
                let runtime = tokio::runtime::Runtime::new()
                    .expect("failed to create the GPUI runtime bridge");
                runtime.block_on(run_bridge(runtime_dir, command_rx, event_tx));
            })
            .expect("failed to start the GPUI runtime bridge thread");
        Self {
            commands: command_tx,
            events: Arc::new(event_rx),
        }
    }

    pub fn events(&self) -> Arc<Receiver<BridgeEvent>> {
        self.events.clone()
    }

    pub async fn request(
        &self,
        request_type: impl Into<String>,
        payload: Value,
    ) -> Result<Value, String> {
        self.request_with_timeout(request_type, payload, Duration::from_secs(3))
            .await
    }

    pub async fn request_with_timeout(
        &self,
        request_type: impl Into<String>,
        payload: Value,
        deadline: Duration,
    ) -> Result<Value, String> {
        let (reply_tx, reply_rx) = async_channel::bounded(1);
        self.commands
            .send(BridgeCommand::Request {
                request_type: request_type.into(),
                payload,
                deadline,
                reply: reply_tx,
            })
            .await
            .map_err(|_| "Runtime bridge is closed.".to_string())?;
        reply_rx
            .recv()
            .await
            .map_err(|_| "Runtime bridge closed before replying.".to_string())?
    }

    pub fn send_ordered(
        &self,
        request_type: impl Into<String>,
        payload: Value,
    ) -> Result<(), String> {
        self.commands
            .try_send(BridgeCommand::OrderedRequest {
                request_type: request_type.into(),
                payload,
                deadline: Duration::from_secs(3),
            })
            .map_err(|error| error.to_string())
    }

    pub async fn start_host(&self, config: RuntimeHostStartConfig) -> Result<(), String> {
        let (reply_tx, reply_rx) = async_channel::bounded(1);
        self.commands
            .send(BridgeCommand::StartHost {
                config,
                reply: reply_tx,
            })
            .await
            .map_err(|_| "Runtime bridge is closed.".to_string())?;
        reply_rx
            .recv()
            .await
            .map_err(|_| "Runtime bridge closed before starting the host.".to_string())?
    }
}

impl Drop for RuntimeBridge {
    fn drop(&mut self) {
        if self.commands.sender_count() == 1 {
            let _ = self.commands.try_send(BridgeCommand::Close);
        }
    }
}

async fn run_bridge(
    runtime_dir: PathBuf,
    commands: Receiver<BridgeCommand>,
    events: Sender<BridgeEvent>,
) {
    loop {
        let connection =
            RuntimeClientConnection::connect(&runtime_dir, RuntimeClientOptions::default()).await;
        match connection {
            Ok(Some(connection)) => {
                crate::app_log::info("runtime_bridge", "connected to the runtime host");
                if events.send(BridgeEvent::Connected).await.is_err() {
                    return;
                }
                if !serve_connection(connection, &commands, &events).await {
                    return;
                }
            }
            Ok(None) => {
                crate::app_log::debug("runtime_bridge", "runtime host is unavailable");
                if events.send(BridgeEvent::Unavailable).await.is_err() {
                    return;
                }
                if !wait_for_reconnect(&runtime_dir, &commands).await {
                    return;
                }
            }
            Err(error) => {
                crate::app_log::warning(
                    "runtime_bridge",
                    &format!("runtime connection failed: {error}"),
                );
                if events
                    .send(BridgeEvent::Disconnected {
                        reason: error.to_string(),
                    })
                    .await
                    .is_err()
                {
                    return;
                }
                if !wait_for_reconnect(&runtime_dir, &commands).await {
                    return;
                }
            }
        }
    }
}

async fn serve_connection(
    mut connection: RuntimeClientConnection,
    commands: &Receiver<BridgeCommand>,
    events: &Sender<BridgeEvent>,
) -> bool {
    loop {
        tokio::select! {
            command = commands.recv() => {
                match command {
                    Ok(BridgeCommand::Request {
                        request_type,
                        payload,
                        deadline,
                        reply,
                    }) => {
                        dispatch_request(
                            connection.handle.clone(),
                            request_type,
                            payload,
                            deadline,
                            reply,
                        );
                    }
                    Ok(BridgeCommand::OrderedRequest {
                        request_type,
                        payload,
                        deadline,
                    }) => {
                        if let Err(error) = connection
                            .handle
                            .request_with_timeout(request_type.clone(), &payload, deadline)
                            .await
                        {
                            crate::app_log::warning(
                                "runtime_bridge",
                                &format!("ordered request {request_type} failed: {error}"),
                            );
                        }
                    }
                    Ok(BridgeCommand::StartHost { reply, .. }) => {
                        let _ = reply.send(Ok(())).await;
                    }
                    Ok(BridgeCommand::Close) | Err(_) => {
                        connection.handle.close().await;
                        return false;
                    }
                }
            }
            event = connection.events.recv() => {
                match event {
                    Some(RuntimeClientEvent::Notification { name, payload }) => {
                        if events.send(BridgeEvent::Notification { name, payload }).await.is_err() {
                            return false;
                        }
                    }
                    Some(RuntimeClientEvent::TerminalOutput { session_id, data }) => {
                        if events.send(BridgeEvent::TerminalOutput { session_id, data }).await.is_err() {
                            return false;
                        }
                    }
                    Some(RuntimeClientEvent::Disconnected { reason }) => {
                        crate::app_log::warning(
                            "runtime_bridge",
                            &format!("runtime disconnected: {reason}"),
                        );
                        let _ = events.send(BridgeEvent::Disconnected { reason }).await;
                        return true;
                    }
                    None => return true,
                }
            }
        }
    }
}

fn dispatch_request(
    handle: RuntimeClientHandle,
    request_type: String,
    payload: Value,
    deadline: Duration,
    reply: Sender<Result<Value, String>>,
) {
    tokio::spawn(async move {
        let request_label = request_type.clone();
        let result = handle
            .request_with_timeout(request_type, &payload, deadline)
            .await
            .map_err(|error| error.to_string());
        if let Err(error) = result.as_ref() {
            crate::app_log::warning(
                "runtime_bridge",
                &format!("request {request_label} failed: {error}"),
            );
        }
        let _ = reply.send(result).await;
    });
}

async fn wait_for_reconnect(runtime_dir: &Path, commands: &Receiver<BridgeCommand>) -> bool {
    let reconnect_at = tokio::time::Instant::now() + RECONNECT_DELAY;
    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(reconnect_at) => return true,
            command = commands.recv() => {
                match command {
                    Ok(BridgeCommand::Request { reply, .. }) => {
                        let _ = reply.send(Err("Alera Runtime Is Unavailable.".to_string())).await;
                    }
                    Ok(BridgeCommand::OrderedRequest { .. }) => {}
                    Ok(BridgeCommand::StartHost { config, reply }) => {
                        let result = spawn_runtime_host(runtime_dir, &config).await;
                        let started = result.is_ok();
                        let _ = reply.send(result).await;
                        if started {
                            tokio::time::sleep(Duration::from_millis(150)).await;
                            return true;
                        }
                    }
                    Ok(BridgeCommand::Close) | Err(_) => return false,
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn unavailable_requests_do_not_short_circuit_the_reconnect_delay() {
        let runtime_dir = std::env::temp_dir().join(format!(
            "alera-runtime-bridge-reconnect-{}",
            uuid::Uuid::new_v4()
        ));
        let (commands, command_rx) = async_channel::unbounded();
        let (reply, reply_rx) = async_channel::bounded(1);
        commands
            .send(BridgeCommand::Request {
                request_type: "status.get".to_string(),
                payload: Value::Null,
                deadline: Duration::from_secs(1),
                reply,
            })
            .await
            .expect("queue request");

        let result = tokio::time::timeout(
            Duration::from_millis(100),
            wait_for_reconnect(&runtime_dir, &command_rx),
        )
        .await;

        assert!(
            result.is_err(),
            "request must not trigger an immediate reconnect"
        );
        assert_eq!(
            reply_rx.recv().await.expect("unavailable reply"),
            Err("Alera Runtime Is Unavailable.".to_string())
        );
    }
}

async fn spawn_runtime_host(
    runtime_dir: &Path,
    config: &RuntimeHostStartConfig,
) -> Result<(), String> {
    std::fs::create_dir_all(runtime_dir)
        .map_err(|error| format!("Failed To Create The Runtime Directory: {error}"))?;

    // A queued Start action can arrive just after the host has published its
    // control file. Reuse that live host instead of creating another process
    // that races to replace the same control file.
    if let Ok(Some(connection)) =
        RuntimeClientConnection::connect(runtime_dir, RuntimeClientOptions::default()).await
    {
        connection.handle.close().await;
        return Ok(());
    }

    let control_file = runtime_dir.join("runtime-host.json");
    let _ = tokio::fs::remove_file(&control_file).await;
    let token = uuid::Uuid::new_v4().to_string();
    let (program, prefix, working_directory) = resolve_cli_command()?;
    let mut command = detached_windowless_async_command(program);
    command
        .args(prefix)
        .arg("runtime-host")
        .arg("--runtime-dir")
        .arg(runtime_dir)
        .arg("--control-file")
        .arg(control_file)
        .arg("--token")
        .arg(token)
        .arg("--empty-shutdown-delay-seconds")
        .arg(config.empty_shutdown_delay_seconds.to_string())
        .arg("--detached-session-shutdown-delay-seconds")
        .arg(config.detached_session_shutdown_delay_seconds.to_string())
        .arg("--scrollback-bytes")
        .arg(config.scrollback_bytes.to_string())
        .arg("--restore-snapshot-bytes")
        .arg(config.scrollback_bytes.to_string())
        .arg("--login-shell")
        .arg(config.login_shell.to_string())
        .env("ALERA_TERMINAL_HOST", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if config.crash_reporting {
        command.arg("--crash-reporting");
    }
    if let Some(working_directory) = working_directory {
        command.current_dir(working_directory);
    }
    command
        .spawn()
        .map_err(|error| format!("Failed To Start The Runtime Host: {error}"))?;

    let deadline = tokio::time::Instant::now() + HOST_STARTUP_TIMEOUT;
    let mut last_error = None;
    loop {
        match RuntimeClientConnection::connect(runtime_dir, RuntimeClientOptions::default()).await {
            Ok(Some(connection)) => {
                connection.handle.close().await;
                return Ok(());
            }
            Ok(None) => {}
            Err(error) => last_error = Some(error.to_string()),
        }
        if tokio::time::Instant::now() >= deadline {
            return Err(last_error.unwrap_or_else(|| {
                "Timed Out Waiting For The Runtime Host To Start.".to_string()
            }));
        }
        tokio::time::sleep(HOST_STARTUP_POLL).await;
    }
}

fn resolve_cli_command() -> Result<(PathBuf, Vec<String>, Option<PathBuf>), String> {
    if let Some(path) = non_blank_environment_path("ALERA_CLI_PATH") {
        return Ok((path, Vec::new(), None));
    }
    if let Some(bundle_dir) = non_blank_environment_path("ALERA_CLI_BUNDLE_DIR") {
        for relative in [
            Path::new("bin").join(cli_executable_name()),
            PathBuf::from(cli_executable_name()),
        ] {
            let candidate = bundle_dir.join(relative);
            if candidate.is_file() {
                return Ok((candidate, Vec::new(), None));
            }
        }
    }
    if let Ok(executable) = std::env::current_exe() {
        if let Some(contents) = executable
            .ancestors()
            .find(|path| path.file_name().is_some_and(|name| name == "Contents"))
        {
            let candidate = contents
                .join("Resources")
                .join("alera")
                .join(cli_executable_name());
            if candidate.is_file() {
                return Ok((candidate, Vec::new(), None));
            }
        }
    }
    let repository = repository_root()
        .ok_or_else(|| "The Bundled Alera Runtime Sidecar Could Not Be Located.".to_string())?;

    // Development GPUI builds are launched through macOS `open`, so shell
    // environment variables are not reliably inherited by the app. Prefer a
    // sidecar already built in this checkout before falling back to `cargo
    // run`, which can take long enough for repeated Start actions to race.
    for profile in ["debug", "release"] {
        let candidate = repository
            .join("rust")
            .join("target")
            .join(profile)
            .join(cli_executable_name());
        if candidate.is_file() {
            return Ok((candidate, Vec::new(), None));
        }
    }

    Ok((
        std::env::var_os("CARGO")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("cargo")),
        vec![
            "run".to_string(),
            "--quiet".to_string(),
            "--locked".to_string(),
            "--manifest-path".to_string(),
            "rust/Cargo.toml".to_string(),
            "-p".to_string(),
            "alera-cli".to_string(),
            "--".to_string(),
        ],
        Some(repository),
    ))
}

fn repository_root() -> Option<PathBuf> {
    let roots = [
        std::env::current_dir().ok(),
        std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(Path::to_path_buf)),
    ];
    roots
        .into_iter()
        .flatten()
        .flat_map(|root| root.ancestors().map(Path::to_path_buf).collect::<Vec<_>>())
        .find(|root| root.join("rust").join("Cargo.toml").is_file())
}

fn non_blank_environment_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn cli_executable_name() -> &'static str {
    if cfg!(windows) {
        "alera.exe"
    } else {
        "alera"
    }
}
