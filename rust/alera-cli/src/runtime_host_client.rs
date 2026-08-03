use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::detached_windowless_async_command;
use anyhow::{anyhow, Context, Result};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::time::{sleep, timeout, Instant};
use uuid::Uuid;

mod persistence;
#[path = "runtime_host_agent_canvas.rs"]
mod runtime_host_agent_canvas;

use crate::terminal_host::protocol::{
    DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS, DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_SCROLLBACK_BYTES, MOBILE_EMULATOR_TAB_KIND, PROTOCOL_VERSION,
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_MOBILE_CAPABILITY,
};

const CONTROL_FILE_NAME: &str = "host.json";
const RUNTIME_CONTROL_FILE_NAME: &str = "runtime-host.json";
const CONNECT_TIMEOUT: Duration = Duration::from_millis(750);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(3);
const STARTUP_TIMEOUT: Duration = Duration::from_secs(10);

pub(crate) struct RuntimeHostRpcClient {
    reader: Lines<BufReader<OwnedReadHalf>>,
    writer: OwnedWriteHalf,
    next_request_id: i64,
}

#[derive(Debug, Deserialize)]
struct RuntimeHostControl {
    #[serde(rename = "protocolVersion")]
    protocol_version: i64,
    port: u16,
    token: String,
    #[serde(rename = "runtimeCapabilities", default)]
    runtime_capabilities: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RuntimeHostFrame {
    id: Option<i64>,
    ok: Option<bool>,
    payload: Option<Value>,
    error: Option<String>,
    event: Option<String>,
}

impl RuntimeHostRpcClient {
    pub(crate) async fn connect(runtime_dir: &Path) -> Result<Option<Self>> {
        Self::connect_with_capability(runtime_dir, None).await
    }

    pub(crate) async fn connect_mobile(runtime_dir: &Path) -> Result<Option<Self>> {
        Self::connect_with_required_capability(runtime_dir, RUNTIME_HOST_MOBILE_CAPABILITY).await
    }

    pub(crate) async fn connect_with_required_capability(
        runtime_dir: &Path,
        required_capability: &str,
    ) -> Result<Option<Self>> {
        Self::connect_with_capability(runtime_dir, Some(required_capability)).await
    }

    async fn connect_with_capability(
        runtime_dir: &Path,
        required_capability: Option<&str>,
    ) -> Result<Option<Self>> {
        for control_path in [
            runtime_dir.join(CONTROL_FILE_NAME),
            runtime_dir.join(RUNTIME_CONTROL_FILE_NAME),
        ] {
            if let Some(client) =
                Self::connect_control_file(&control_path, required_capability).await?
            {
                return Ok(Some(client));
            }
        }
        Ok(None)
    }

    pub(crate) async fn connect_or_start(runtime_dir: &Path) -> Result<Self> {
        if let Some(client) = Self::connect(runtime_dir).await? {
            return Ok(client);
        }
        Self::start(runtime_dir, None, false).await
    }

    pub(crate) async fn connect_or_start_persistent(runtime_dir: &Path) -> Result<Self> {
        persistence::connect_or_start_persistent(runtime_dir).await
    }

    pub(crate) async fn connect_or_start_mobile(runtime_dir: &Path) -> Result<Self> {
        Self::connect_or_start_with_required_capability(runtime_dir, RUNTIME_HOST_MOBILE_CAPABILITY)
            .await
    }

    pub(crate) async fn connect_or_start_with_required_capability(
        runtime_dir: &Path,
        required_capability: &str,
    ) -> Result<Self> {
        if let Some(client) =
            Self::connect_with_required_capability(runtime_dir, required_capability).await?
        {
            return Ok(client);
        }
        Self::start(runtime_dir, Some(required_capability), false).await
    }

    async fn start(
        runtime_dir: &Path,
        required_capability: Option<&str>,
        persistent: bool,
    ) -> Result<Self> {
        tokio::fs::create_dir_all(runtime_dir).await?;
        let control_file = runtime_dir.join(RUNTIME_CONTROL_FILE_NAME);
        let _ = tokio::fs::remove_file(&control_file).await;
        let token = Uuid::new_v4().to_string();
        let executable = std::env::current_exe().context("failed to resolve current alera CLI")?;
        let mut command = detached_windowless_async_command(executable);
        command
            .arg("runtime-host")
            .arg("--runtime-dir")
            .arg(runtime_dir)
            .arg("--control-file")
            .arg(&control_file)
            .arg("--token")
            .arg(&token)
            .arg("--empty-shutdown-delay-seconds")
            .arg(DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS.to_string())
            .arg("--detached-session-shutdown-delay-seconds")
            .arg(DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS.to_string())
            .arg("--scrollback-bytes")
            .arg(DEFAULT_SCROLLBACK_BYTES.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if persistent {
            command.arg("--persistent");
        }
        command
            .spawn()
            .context("failed to start alera runtime-host")?;

        let deadline = Instant::now() + STARTUP_TIMEOUT;
        while Instant::now() < deadline {
            if let Some(client) =
                Self::connect_control_file(&control_file, required_capability).await?
            {
                return Ok(client);
            }
            sleep(Duration::from_millis(100)).await;
        }
        Err(anyhow!("timed out waiting for alera runtime-host to start"))
    }

    async fn connect_control_file(
        control_path: &Path,
        required_capability: Option<&str>,
    ) -> Result<Option<Self>> {
        let contents = match tokio::fs::read_to_string(control_path).await {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error).context("failed reading runtime host control file"),
        };
        let control: RuntimeHostControl = match serde_json::from_str(&contents) {
            Ok(control) => control,
            Err(_) => return Ok(None),
        };
        if !control.is_protocol_compatible() {
            return Ok(None);
        }
        if required_capability.is_none() && !control.is_usable(None) {
            return Ok(None);
        }

        let Some(client) = Self::connect_control(&control).await? else {
            return Ok(None);
        };
        if !control.is_usable(required_capability) {
            let required = required_capability.unwrap_or("requested");
            return Err(anyhow!(
                "A live Alera runtime host does not support {required}. Restart Alera and retry."
            ));
        }

        Ok(Some(client))
    }

    async fn connect_control(control: &RuntimeHostControl) -> Result<Option<Self>> {
        let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), control.port);
        let stream = match timeout(CONNECT_TIMEOUT, TcpStream::connect(address)).await {
            Ok(Ok(stream)) => stream,
            Ok(Err(_)) | Err(_) => return Ok(None),
        };
        let (read_half, write_half) = stream.into_split();
        let mut client = RuntimeHostRpcClient {
            reader: BufReader::new(read_half).lines(),
            writer: write_half,
            next_request_id: 1,
        };
        let hello = control_hello_payload(control);
        match timeout(REQUEST_TIMEOUT, client.request_value("hello", &hello)).await {
            Ok(Ok(_)) => Ok(Some(client)),
            Ok(Err(_)) | Err(_) => Ok(None),
        }
    }

    pub(crate) async fn request<T, P>(&mut self, request_type: &str, payload: &P) -> Result<T>
    where
        T: DeserializeOwned,
        P: Serialize + ?Sized,
    {
        let value = self.request_value(request_type, payload).await?;
        serde_json::from_value(value)
            .with_context(|| format!("runtime host response for {request_type} was invalid"))
    }

    /// Like `request_value` but bounded by a client-side deadline. Used by
    /// wait-capable orchestration verbs so a vanished host cannot hang the
    /// CLI past the server-side wait timeout.
    pub(crate) async fn request_value_with_deadline<P>(
        &mut self,
        request_type: &str,
        payload: &P,
        deadline_ms: u64,
    ) -> Result<Value>
    where
        P: Serialize + ?Sized,
    {
        match timeout(
            Duration::from_millis(deadline_ms),
            self.request_value(request_type, payload),
        )
        .await
        {
            Ok(result) => result,
            Err(_) => Err(anyhow!(
                "runtime host did not answer {request_type} within {deadline_ms}ms"
            )),
        }
    }

    pub(crate) async fn request_value<P>(
        &mut self,
        request_type: &str,
        payload: &P,
    ) -> Result<Value>
    where
        P: Serialize + ?Sized,
    {
        let id = self.next_request_id;
        self.next_request_id += 1;
        let mut line = serde_json::to_vec(&json!({
            "id": id,
            "type": request_type,
            "payload": payload,
        }))?;
        line.push(b'\n');
        self.writer.write_all(&line).await?;
        self.writer.flush().await?;

        loop {
            let Some(line) = self.reader.next_line().await? else {
                return Err(anyhow!("runtime host closed the connection"));
            };
            let frame: RuntimeHostFrame = serde_json::from_str(&line)?;
            if frame.event.is_some() {
                continue;
            }
            if frame.id != Some(id) {
                continue;
            }
            if frame.ok == Some(true) {
                return Ok(frame.payload.unwrap_or(Value::Null));
            }
            return Err(anyhow!(
                "{}",
                frame
                    .error
                    .unwrap_or_else(|| "runtime host request failed".to_string())
            ));
        }
    }
}

impl RuntimeHostControl {
    fn is_protocol_compatible(&self) -> bool {
        self.protocol_version == PROTOCOL_VERSION && !self.token.is_empty()
    }

    fn is_usable(&self, required_capability: Option<&str>) -> bool {
        self.is_protocol_compatible()
            && self
                .runtime_capabilities
                .iter()
                .any(|capability| capability == RUNTIME_HOST_CAPABILITY)
            && self
                .runtime_capabilities
                .iter()
                .any(|capability| capability == RUNTIME_HOST_BOOTSTRAP_CAPABILITY)
            && self
                .runtime_capabilities
                .iter()
                .any(|capability| capability == RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY)
            && match required_capability {
                None => true,
                Some(required) => self
                    .runtime_capabilities
                    .iter()
                    .any(|capability| capability == required),
            }
    }
}

fn control_hello_payload(control: &RuntimeHostControl) -> Value {
    json!({
        "protocolVersion": PROTOCOL_VERSION,
        "token": control.token,
        "clientKind": "cli",
        "supportedTabKinds": [MOBILE_EMULATOR_TAB_KIND],
    })
}

#[cfg(test)]
mod tests {
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
    fn cli_hello_declares_mobile_emulator_tab_support() {
        let payload = control_hello_payload(&control(&[
            RUNTIME_HOST_CAPABILITY,
            RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
            RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
        ]));

        assert_eq!(payload["clientKind"], json!("cli"));
        assert_eq!(
            payload["supportedTabKinds"],
            json!([MOBILE_EMULATOR_TAB_KIND])
        );
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
}
