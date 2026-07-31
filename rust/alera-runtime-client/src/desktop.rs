use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::Path;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use base64::prelude::{Engine as _, BASE64_STANDARD};
use serde::Serialize;
use serde_json::{json, Value};
use tokio::io::{
    AsyncBufReadExt as _, AsyncReadExt as _, AsyncWriteExt as _, BufReader, ReadHalf, WriteHalf,
};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, oneshot};
use tokio::time::timeout;

use alera_runtime_protocol::frame_codec::{FRAME_HEADER_LEN, FRAME_KIND_JSON, FRAME_KIND_OUTPUT};
use alera_runtime_protocol::{
    BINARY_FRAMES_ENABLED_EVENT, MOBILE_EMULATOR_TAB_KIND, PROTOCOL_VERSION,
    RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
};

use super::{
    RuntimeHostControl, CONNECT_TIMEOUT, CONTROL_FILE_NAME, REQUEST_TIMEOUT,
    RUNTIME_CONTROL_FILE_NAME,
};

const EVENT_QUEUE_CAPACITY: usize = 256;
const COMMAND_QUEUE_CAPACITY: usize = 64;
const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Debug)]
pub struct RuntimeClientOptions {
    pub client_kind: String,
    pub supported_tab_kinds: Vec<String>,
    pub binary_frames: bool,
}

impl Default for RuntimeClientOptions {
    fn default() -> Self {
        Self {
            client_kind: "app".to_string(),
            supported_tab_kinds: vec![MOBILE_EMULATOR_TAB_KIND.to_string()],
            binary_frames: true,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum RuntimeClientEvent {
    Notification { name: String, payload: Value },
    TerminalOutput { session_id: String, data: Vec<u8> },
    Disconnected { reason: String },
}

pub struct RuntimeClientConnection {
    pub handle: RuntimeClientHandle,
    pub events: mpsc::Receiver<RuntimeClientEvent>,
}

#[derive(Clone)]
pub struct RuntimeClientHandle {
    commands: mpsc::Sender<ClientCommand>,
}

enum ClientCommand {
    Request {
        request_type: String,
        payload: Value,
        reply: oneshot::Sender<Result<Value>>,
    },
    Close,
}

enum IncomingFrame {
    Json(Value),
    Output { session_id: String, data: Vec<u8> },
}

impl RuntimeClientConnection {
    pub async fn connect(
        runtime_dir: &Path,
        options: RuntimeClientOptions,
    ) -> Result<Option<Self>> {
        for control_path in [
            runtime_dir.join(CONTROL_FILE_NAME),
            runtime_dir.join(RUNTIME_CONTROL_FILE_NAME),
        ] {
            let contents = match tokio::fs::read_to_string(&control_path).await {
                Ok(contents) => contents,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => {
                    return Err(error).context("failed reading runtime host control file");
                }
            };
            let control: RuntimeHostControl = match serde_json::from_str(&contents) {
                Ok(control) => control,
                Err(_) => continue,
            };
            if !control.is_usable(None) {
                continue;
            }
            if let Some(connection) = Self::connect_control(&control, &options).await? {
                return Ok(Some(connection));
            }
        }
        Ok(None)
    }

    async fn connect_control(
        control: &RuntimeHostControl,
        options: &RuntimeClientOptions,
    ) -> Result<Option<Self>> {
        let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), control.port);
        let stream = match timeout(CONNECT_TIMEOUT, TcpStream::connect(address)).await {
            Ok(Ok(stream)) => stream,
            Ok(Err(_)) | Err(_) => return Ok(None),
        };
        stream.set_nodelay(true)?;
        let (read_half, mut write_half) = tokio::io::split(stream);
        let mut reader = BufReader::new(read_half);
        let binary_frames = options.binary_frames
            && control
                .runtime_capabilities
                .iter()
                .any(|value| value == RUNTIME_HOST_BINARY_FRAMES_CAPABILITY);
        let hello = json!({
            "protocolVersion": PROTOCOL_VERSION,
            "token": control.token,
            "clientKind": options.client_kind,
            "supportedTabKinds": options.supported_tab_kinds,
            "binaryFrames": binary_frames,
        });
        write_request(&mut write_half, 1, "hello", hello).await?;
        let first = timeout(REQUEST_TIMEOUT, read_json_line(&mut reader))
            .await
            .map_err(|_| anyhow!("runtime host hello timed out"))??;
        let (response, upgrade_seen) = if binary_frames && is_binary_upgrade_event(&first) {
            let response = timeout(REQUEST_TIMEOUT, read_frame(&mut reader, true))
                .await
                .map_err(|_| anyhow!("runtime host hello timed out after binary upgrade"))??;
            match response {
                IncomingFrame::Json(value) => (value, true),
                IncomingFrame::Output { .. } => {
                    return Err(anyhow!(
                        "runtime host sent terminal output before the hello response"
                    ));
                }
            }
        } else {
            (first, false)
        };
        validate_hello_response(&response)?;

        if binary_frames && !upgrade_seen {
            let upgrade = timeout(REQUEST_TIMEOUT, read_json_line(&mut reader))
                .await
                .map_err(|_| anyhow!("runtime host binary upgrade timed out"))??;
            if !is_binary_upgrade_event(&upgrade) {
                return Err(anyhow!(
                    "runtime host did not confirm the binary frame upgrade"
                ));
            }
        }

        let (command_tx, command_rx) = mpsc::channel(COMMAND_QUEUE_CAPACITY);
        let (event_tx, event_rx) = mpsc::channel(EVENT_QUEUE_CAPACITY);
        tokio::spawn(run_connection(
            reader,
            write_half,
            command_rx,
            event_tx,
            binary_frames,
        ));

        Ok(Some(Self {
            handle: RuntimeClientHandle {
                commands: command_tx,
            },
            events: event_rx,
        }))
    }
}

impl RuntimeClientHandle {
    pub async fn request<P>(&self, request_type: impl Into<String>, payload: &P) -> Result<Value>
    where
        P: Serialize + ?Sized,
    {
        self.request_with_timeout(request_type, payload, REQUEST_TIMEOUT)
            .await
    }

    pub async fn request_with_timeout<P>(
        &self,
        request_type: impl Into<String>,
        payload: &P,
        deadline: Duration,
    ) -> Result<Value>
    where
        P: Serialize + ?Sized,
    {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.commands
            .send(ClientCommand::Request {
                request_type: request_type.into(),
                payload: serde_json::to_value(payload)?,
                reply: reply_tx,
            })
            .await
            .map_err(|_| anyhow!("runtime host connection is closed"))?;
        timeout(deadline, reply_rx)
            .await
            .map_err(|_| anyhow!("runtime host request timed out"))?
            .map_err(|_| anyhow!("runtime host connection closed before replying"))?
    }

    pub async fn close(&self) {
        let _ = self.commands.send(ClientCommand::Close).await;
    }
}

async fn run_connection(
    mut reader: BufReader<ReadHalf<TcpStream>>,
    mut writer: WriteHalf<TcpStream>,
    mut commands: mpsc::Receiver<ClientCommand>,
    events: mpsc::Sender<RuntimeClientEvent>,
    binary_frames: bool,
) {
    let mut next_request_id = 2_i64;
    let mut pending = HashMap::<i64, oneshot::Sender<Result<Value>>>::new();
    let disconnect_reason = loop {
        tokio::select! {
            command = commands.recv() => {
                match command {
                    Some(ClientCommand::Request { request_type, payload, reply }) => {
                        let id = next_request_id;
                        next_request_id += 1;
                        if let Err(error) = write_request(&mut writer, id, &request_type, payload).await {
                            let reason = format!("failed writing runtime request: {error}");
                            let _ = reply.send(Err(anyhow!(reason.clone())));
                            break reason;
                        }
                        pending.insert(id, reply);
                    }
                    Some(ClientCommand::Close) => break "connection closed by client".to_string(),
                    None => break "all runtime client handles were dropped".to_string(),
                }
            }
            frame = read_frame(&mut reader, binary_frames) => {
                match frame {
                    Ok(IncomingFrame::Output { session_id, data }) => {
                        if events.send(RuntimeClientEvent::TerminalOutput { session_id, data }).await.is_err() {
                            break "runtime event consumer was dropped".to_string();
                        }
                    }
                    Ok(IncomingFrame::Json(value)) => {
                        if let Some(id) = value.get("id").and_then(Value::as_i64) {
                            if let Some(reply) = pending.remove(&id) {
                                let result = response_result(value);
                                let _ = reply.send(result);
                            }
                        } else if let Some(event) = normalize_json_event(value) {
                            if events.send(event).await.is_err() {
                                break "runtime event consumer was dropped".to_string();
                            }
                        }
                    }
                    Err(error) => break format!("runtime host connection ended: {error}"),
                }
            }
        }
    };

    for (_, reply) in pending {
        let _ = reply.send(Err(anyhow!(disconnect_reason.clone())));
    }
    let _ = events
        .send(RuntimeClientEvent::Disconnected {
            reason: disconnect_reason,
        })
        .await;
}

async fn write_request(
    writer: &mut WriteHalf<TcpStream>,
    id: i64,
    request_type: &str,
    payload: Value,
) -> Result<()> {
    let mut bytes = serde_json::to_vec(&json!({
        "id": id,
        "type": request_type,
        "payload": payload,
    }))?;
    bytes.push(b'\n');
    writer.write_all(&bytes).await?;
    writer.flush().await?;
    Ok(())
}

async fn read_frame(
    reader: &mut BufReader<ReadHalf<TcpStream>>,
    binary_frames: bool,
) -> Result<IncomingFrame> {
    if !binary_frames {
        return Ok(IncomingFrame::Json(read_json_line(reader).await?));
    }

    let mut header = [0_u8; FRAME_HEADER_LEN];
    reader.read_exact(&mut header).await?;
    let kind = header[0];
    let length = u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(anyhow!(
            "runtime frame exceeds the {MAX_FRAME_BYTES}-byte client limit"
        ));
    }
    let mut payload = vec![0_u8; length];
    reader.read_exact(&mut payload).await?;
    match kind {
        FRAME_KIND_JSON => Ok(IncomingFrame::Json(serde_json::from_slice(&payload)?)),
        FRAME_KIND_OUTPUT => {
            if payload.len() < 2 {
                return Err(anyhow!(
                    "runtime output frame omitted its session id length"
                ));
            }
            let id_length = u16::from_be_bytes([payload[0], payload[1]]) as usize;
            if payload.len() < 2 + id_length {
                return Err(anyhow!("runtime output frame truncated its session id"));
            }
            let session_id = std::str::from_utf8(&payload[2..2 + id_length])?.to_string();
            Ok(IncomingFrame::Output {
                session_id,
                data: payload[2 + id_length..].to_vec(),
            })
        }
        _ => Err(anyhow!("runtime host sent unknown frame kind {kind}")),
    }
}

async fn read_json_line(reader: &mut BufReader<ReadHalf<TcpStream>>) -> Result<Value> {
    let mut bytes = Vec::new();
    let count = reader.read_until(b'\n', &mut bytes).await?;
    if count == 0 {
        return Err(anyhow!("runtime host closed the connection"));
    }
    if bytes.len() > MAX_FRAME_BYTES {
        return Err(anyhow!(
            "runtime JSON line exceeds the {MAX_FRAME_BYTES}-byte client limit"
        ));
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn validate_hello_response(value: &Value) -> Result<()> {
    if value.get("id").and_then(Value::as_i64) != Some(1) {
        return Err(anyhow!(
            "runtime host returned an invalid hello response id"
        ));
    }
    response_result(value.clone()).map(|_| ())
}

fn is_binary_upgrade_event(value: &Value) -> bool {
    value.get("event").and_then(Value::as_str) == Some(BINARY_FRAMES_ENABLED_EVENT)
}

fn response_result(mut value: Value) -> Result<Value> {
    if value.get("ok").and_then(Value::as_bool) == Some(true) {
        return Ok(value
            .as_object_mut()
            .and_then(|object| object.remove("payload"))
            .unwrap_or(Value::Null));
    }
    Err(anyhow!(
        "{}",
        value
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("runtime host request failed")
    ))
}

fn normalize_json_event(value: Value) -> Option<RuntimeClientEvent> {
    let name = value.get("event")?.as_str()?.to_string();
    let payload = value.get("payload").cloned().unwrap_or(Value::Null);
    if name == "output" {
        let session_id = payload.get("sessionId")?.as_str()?.to_string();
        let encoded = payload.get("dataBase64")?.as_str()?;
        let data = BASE64_STANDARD.decode(encoded).ok()?;
        return Some(RuntimeClientEvent::TerminalOutput { session_id, data });
    }
    Some(RuntimeClientEvent::Notification { name, payload })
}

#[cfg(test)]
#[path = "desktop_tests.rs"]
mod tests;
