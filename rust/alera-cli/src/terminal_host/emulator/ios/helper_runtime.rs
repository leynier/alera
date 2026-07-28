use std::net::Ipv6Addr;
use std::path::{Path, PathBuf};
use std::time::Duration;

use futures_util::SinkExt as _;
use serde::Deserialize;
use tokio::net::TcpStream;
use tokio::process::Child;
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::MaybeTlsStream;

use super::super::contract::{EmulatorFailure, EmulatorResult};
use super::http_body;

const CONFIG_RESPONSE_BYTES: usize = 16 * 1024;

pub struct ControlRequest {
    pub frame: Vec<u8>,
    pub completion: oneshot::Sender<EmulatorResult<()>>,
}

#[derive(Deserialize)]
struct ScreenConfig {
    width: u32,
    height: u32,
}

pub async fn wait_until_ready(child: &mut Child, port: u16) -> EmulatorResult<(u32, u32)> {
    let stream_url = format!("http://[::1]:{port}/stream.mjpeg");
    for _ in 0..300 {
        if let Some(status) = child.try_wait().map_err(|error| {
            helper_failure(format!("Could not inspect serve-sim status: {error}"))
        })? {
            return Err(helper_failure(format!(
                "serve-sim exited before capturing a frame with status {status}."
            )));
        }
        if TcpStream::connect((Ipv6Addr::LOCALHOST, port))
            .await
            .is_ok()
        {
            if let Ok(dimensions) = read_dimensions(&stream_url).await {
                return Ok(dimensions);
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err(helper_failure(
        "serve-sim did not capture an iOS Simulator frame within 30 seconds.",
    ))
}

pub async fn read_dimensions(stream_url: &str) -> EmulatorResult<(u32, u32)> {
    let config_url = stream_url.replace("/stream.mjpeg", "/config");
    let response = http_body::get_bounded(
        &config_url,
        Duration::from_secs(2),
        CONFIG_RESPONSE_BYTES,
        "configuration",
    )
    .await?;
    if !response.status.is_success() {
        return Err(helper_failure(format!(
            "serve-sim configuration returned HTTP {}.",
            response.status
        )));
    }
    let config: ScreenConfig = serde_json::from_slice(&response.bytes).map_err(|error| {
        helper_failure(format!(
            "serve-sim returned invalid screen configuration: {error}"
        ))
    })?;
    if config.width == 0 || config.height == 0 {
        return Err(helper_failure(
            "serve-sim has not captured a simulator frame yet.",
        ));
    }
    Ok((config.width, config.height))
}

pub async fn control_worker(url: String, mut requests: mpsc::Receiver<ControlRequest>) {
    let mut socket = None;
    while let Some(request) = requests.recv().await {
        let result = send_control_frame(&url, &mut socket, request.frame).await;
        let _ = request.completion.send(result);
    }
}

async fn send_control_frame(
    url: &str,
    socket: &mut Option<tokio_tungstenite::WebSocketStream<MaybeTlsStream<TcpStream>>>,
    frame: Vec<u8>,
) -> EmulatorResult<()> {
    for _ in 0..2 {
        if socket.is_none() {
            let connected = tokio::time::timeout(
                Duration::from_secs(2),
                tokio_tungstenite::connect_async(url),
            )
            .await
            .map_err(|_| helper_failure("serve-sim control connection timed out."))?
            .map_err(|error| {
                helper_failure(format!("serve-sim control connection failed: {error}"))
            })?;
            *socket = Some(connected.0);
        }
        let sent = tokio::time::timeout(
            Duration::from_secs(2),
            socket
                .as_mut()
                .expect("socket was connected")
                .send(Message::Binary(frame.clone().into())),
        )
        .await;
        if matches!(sent, Ok(Ok(()))) {
            return Ok(());
        }
        *socket = None;
    }
    Err(helper_failure(
        "serve-sim did not accept the iOS input event.",
    ))
}

pub fn serve_sim_path() -> EmulatorResult<PathBuf> {
    let executable = std::env::current_exe().map_err(|error| {
        EmulatorFailure::dependency(
            "serve-sim",
            format!("Could not resolve the Alera executable: {error}"),
        )
    })?;
    let bundled = executable
        .parent()
        .unwrap_or(Path::new("."))
        .join("emulator/ios/serve-sim/0.1.40/serve-sim-bin");
    if bundled.is_file() {
        return Ok(bundled);
    }
    let development = PathBuf::from("resources/alera/emulator/ios/serve-sim/0.1.40/serve-sim-bin");
    if development.is_file() {
        return Ok(development);
    }
    Err(EmulatorFailure::dependency(
        "the bundled serve-sim helper",
        format!("serve-sim helper was not found at {}.", bundled.display()),
    ))
}

pub fn helper_failure(message: impl Into<String>) -> EmulatorFailure {
    EmulatorFailure::new(
        "stream_failed",
        message,
        ["Restart the iOS Simulator and reconnect the emulator tab."],
    )
}
