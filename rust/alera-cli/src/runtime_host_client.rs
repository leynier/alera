use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::process::Command;
use tokio::time::{sleep, timeout, Instant};
use uuid::Uuid;

use crate::terminal_host::protocol::{
    DEFAULT_DETACHED_SESSION_SHUTDOWN_DELAY_SECONDS, DEFAULT_EMPTY_SHUTDOWN_DELAY_SECONDS,
    DEFAULT_SCROLLBACK_BYTES, PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY,
};

const CONTROL_FILE_NAME: &str = "host.json";
const RUNTIME_CONTROL_FILE_NAME: &str = "runtime-host.json";
const CONNECT_TIMEOUT: Duration = Duration::from_millis(750);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(3);
const STARTUP_TIMEOUT: Duration = Duration::from_secs(10);
const BASE_RUNTIME_HOST_CAPABILITIES: &[&str] = &[
    RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
];
const MOBILE_RUNTIME_HOST_CAPABILITIES: &[&str] = &[
    RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    RUNTIME_HOST_MOBILE_CAPABILITY,
];

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
        Self::connect_with_capabilities(runtime_dir, BASE_RUNTIME_HOST_CAPABILITIES).await
    }

    pub(crate) async fn connect_mobile(runtime_dir: &Path) -> Result<Option<Self>> {
        Self::connect_with_capabilities(runtime_dir, MOBILE_RUNTIME_HOST_CAPABILITIES).await
    }

    async fn connect_with_capabilities(
        runtime_dir: &Path,
        required_capabilities: &[&str],
    ) -> Result<Option<Self>> {
        for control_path in [
            runtime_dir.join(CONTROL_FILE_NAME),
            runtime_dir.join(RUNTIME_CONTROL_FILE_NAME),
        ] {
            if let Some(client) =
                Self::connect_control_file(&control_path, required_capabilities).await?
            {
                return Ok(Some(client));
            }
        }
        Ok(None)
    }

    pub(crate) async fn connect_or_start(runtime_dir: &Path) -> Result<Self> {
        Self::connect_or_start_with_capabilities(runtime_dir, BASE_RUNTIME_HOST_CAPABILITIES).await
    }

    pub(crate) async fn connect_or_start_mobile(runtime_dir: &Path) -> Result<Self> {
        Self::connect_or_start_with_capabilities(runtime_dir, MOBILE_RUNTIME_HOST_CAPABILITIES)
            .await
    }

    async fn connect_or_start_with_capabilities(
        runtime_dir: &Path,
        required_capabilities: &[&str],
    ) -> Result<Self> {
        if let Some(client) =
            Self::connect_with_capabilities(runtime_dir, required_capabilities).await?
        {
            return Ok(client);
        }
        tokio::fs::create_dir_all(runtime_dir).await?;
        let control_file = runtime_dir.join(RUNTIME_CONTROL_FILE_NAME);
        let _ = tokio::fs::remove_file(&control_file).await;
        let token = Uuid::new_v4().to_string();
        let executable = std::env::current_exe().context("failed to resolve current alera CLI")?;
        Command::new(executable)
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
            .stderr(Stdio::null())
            .spawn()
            .context("failed to start alera runtime-host")?;

        let deadline = Instant::now() + STARTUP_TIMEOUT;
        while Instant::now() < deadline {
            if let Some(client) =
                Self::connect_control_file(&control_file, required_capabilities).await?
            {
                return Ok(client);
            }
            sleep(Duration::from_millis(100)).await;
        }
        Err(anyhow!("timed out waiting for alera runtime-host to start"))
    }

    async fn connect_control_file(
        control_path: &Path,
        required_capabilities: &[&str],
    ) -> Result<Option<Self>> {
        let contents = match tokio::fs::read_to_string(&control_path).await {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error).context("failed reading runtime host control file"),
        };
        let control: RuntimeHostControl = match serde_json::from_str(&contents) {
            Ok(control) => control,
            Err(_) => return Ok(None),
        };
        if !control.is_usable(required_capabilities) {
            return Ok(None);
        }

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
        let hello = json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": control.token,
        });
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
    fn is_usable(&self, required_capabilities: &[&str]) -> bool {
        self.protocol_version == PROTOCOL_VERSION
            && !self.token.is_empty()
            && required_capabilities.iter().all(|required| {
                self.runtime_capabilities
                    .iter()
                    .any(|capability| capability == required)
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn control_with_capabilities(runtime_capabilities: &[&str]) -> RuntimeHostControl {
        RuntimeHostControl {
            protocol_version: PROTOCOL_VERSION,
            port: 12345,
            token: "token".to_string(),
            runtime_capabilities: runtime_capabilities
                .iter()
                .map(|capability| capability.to_string())
                .collect(),
        }
    }

    #[test]
    fn mobile_capability_is_required_only_for_mobile_connections() {
        let control = control_with_capabilities(BASE_RUNTIME_HOST_CAPABILITIES);

        assert!(control.is_usable(BASE_RUNTIME_HOST_CAPABILITIES));
        assert!(!control.is_usable(MOBILE_RUNTIME_HOST_CAPABILITIES));
    }

    #[test]
    fn mobile_connections_accept_mobile_capable_hosts() {
        let control = control_with_capabilities(MOBILE_RUNTIME_HOST_CAPABILITIES);

        assert!(control.is_usable(MOBILE_RUNTIME_HOST_CAPABILITIES));
    }
}
