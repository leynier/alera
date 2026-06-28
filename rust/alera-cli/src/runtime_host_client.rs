use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::time::timeout;

use crate::terminal_host::protocol::{PROTOCOL_VERSION, RUNTIME_HOST_CAPABILITY};

const CONTROL_FILE_NAME: &str = "host.json";
const RUNTIME_CONTROL_FILE_NAME: &str = "runtime-host.json";
const CONNECT_TIMEOUT: Duration = Duration::from_millis(750);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(3);

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
        for control_path in [
            runtime_dir.join(CONTROL_FILE_NAME),
            runtime_dir.join(RUNTIME_CONTROL_FILE_NAME),
        ] {
            if let Some(client) = Self::connect_control_file(&control_path).await? {
                return Ok(Some(client));
            }
        }
        Ok(None)
    }

    async fn connect_control_file(control_path: &Path) -> Result<Option<Self>> {
        let contents = match tokio::fs::read_to_string(&control_path).await {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error).context("failed reading runtime host control file"),
        };
        let control: RuntimeHostControl = match serde_json::from_str(&contents) {
            Ok(control) => control,
            Err(_) => return Ok(None),
        };
        if !control.is_usable() {
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
    fn is_usable(&self) -> bool {
        self.protocol_version == PROTOCOL_VERSION
            && !self.token.is_empty()
            && self
                .runtime_capabilities
                .iter()
                .any(|capability| capability == RUNTIME_HOST_CAPABILITY)
    }
}
