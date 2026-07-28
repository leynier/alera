use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use bytes::Bytes;
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::TcpStream;
use tokio::process::Child;
use tokio::sync::{oneshot, Mutex};
use tokio::task::JoinHandle;
use uuid::Uuid;

use super::super::contract::{EmulatorFailure, EmulatorResult};
use super::super::process;
use super::super::video_server::{AndroidVideoFrameKind, AndroidVideoSource};

const SCRCPY_VERSION: &str = "4.0";
const DEVICE_JAR: &str = "/data/local/tmp/alera-scrcpy-server.jar";
const FRAME_HEADER_BYTES: usize = 12;
const DEVICE_NAME_BYTES: usize = 64;
const CODEC_META_BYTES: usize = 4;
const H264_CODEC_ID: u32 = u32::from_be_bytes(*b"h264");
const PACKET_FLAG_SESSION: u64 = 1_u64 << 63;
const PACKET_FLAG_CONFIG: u64 = 1_u64 << 62;
const PACKET_FLAG_KEY_FRAME: u64 = 1_u64 << 61;
const MAX_FRAME_BYTES: usize = 16 * 1024 * 1024;

pub struct AndroidStream {
    pub source: AndroidVideoSource,
    pub control: Arc<Mutex<TcpStream>>,
    pub port: u16,
    width: Arc<AtomicU32>,
    height: Arc<AtomicU32>,
    server: Child,
    reader: JoinHandle<()>,
}

impl AndroidStream {
    pub async fn start(adb: &Path, serial: &str, server_jar: &Path) -> EmulatorResult<Self> {
        let scid = scrcpy_id();
        process::output(
            adb,
            &[
                "-s".into(),
                serial.into(),
                "push".into(),
                server_jar.to_string_lossy().into_owned(),
                DEVICE_JAR.into(),
            ],
            "scrcpy server deployment",
        )
        .await?;
        let forward = process::output(
            adb,
            &[
                "-s".into(),
                serial.into(),
                "forward".into(),
                "tcp:0".into(),
                format!("localabstract:scrcpy_{scid}"),
            ],
            "scrcpy port forwarding",
        )
        .await?;
        let port = String::from_utf8_lossy(&forward.stdout)
            .trim()
            .parse::<u16>()
            .map_err(|_| {
                EmulatorFailure::new(
                    "stream_failed",
                    "adb did not allocate a valid scrcpy port.",
                    ["Restart adb and retry."],
                )
            })?;
        let mut command = windowless_async_command(adb);
        command
            .args([
                "-s",
                serial,
                "shell",
                &format!("CLASSPATH={DEVICE_JAR}"),
                "app_process",
                "/",
                "com.genymobile.scrcpy.Server",
                SCRCPY_VERSION,
                &format!("scid={scid}"),
                "log_level=info",
                "tunnel_forward=true",
                "audio=false",
                "control=true",
                "cleanup=true",
                "clipboard_autosync=false",
                "video_codec=h264",
                "max_size=1280",
                "max_fps=60",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        let mut server = match command.spawn() {
            Ok(server) => server,
            Err(error) => {
                remove_forward(adb, serial, port).await;
                return Err(EmulatorFailure::new(
                    "stream_failed",
                    format!("Could not start the scrcpy server: {error}"),
                    ["Restart the selected Android virtual device and retry."],
                ));
            }
        };
        let mut video = match connect_with_data(port).await {
            Ok(video) => video,
            Err(error) => {
                let _ = server.kill().await;
                remove_forward(adb, serial, port).await;
                return Err(error);
            }
        };
        let control = match connect_with_retry(port).await {
            Ok(control) => control,
            Err(error) => {
                let _ = server.kill().await;
                remove_forward(adb, serial, port).await;
                return Err(error);
            }
        };
        let mut device_name = [0_u8; DEVICE_NAME_BYTES];
        let device_metadata =
            tokio::time::timeout(Duration::from_secs(5), video.read_exact(&mut device_name)).await;
        if !matches!(device_metadata, Ok(Ok(_))) {
            let _ = server.kill().await;
            remove_forward(adb, serial, port).await;
            return Err(stream_start_failure(
                "scrcpy did not send its device metadata.",
            ));
        }
        let source = AndroidVideoSource::new(128);
        let width = Arc::new(AtomicU32::new(0));
        let height = Arc::new(AtomicU32::new(0));
        let (meta_tx, meta_rx) = oneshot::channel();
        let reader_width = width.clone();
        let reader_height = height.clone();
        let reader_source = source.clone();
        let reader = tokio::spawn(async move {
            read_video(
                &mut video,
                reader_source,
                reader_width,
                reader_height,
                meta_tx,
            )
            .await;
        });
        let metadata = match tokio::time::timeout(Duration::from_secs(10), meta_rx).await {
            Ok(Ok(metadata)) => metadata,
            Ok(Err(_)) => Err(stream_start_failure("scrcpy closed before video metadata.")),
            Err(_) => Err(stream_start_failure("scrcpy did not send video metadata.")),
        };
        if let Err(error) = metadata {
            reader.abort();
            let _ = server.kill().await;
            remove_forward(adb, serial, port).await;
            return Err(error);
        }
        Ok(Self {
            source,
            control: Arc::new(Mutex::new(control)),
            port,
            width,
            height,
            server,
            reader,
        })
    }

    pub fn dimensions(&self) -> (u32, u32) {
        (
            self.width.load(Ordering::Relaxed),
            self.height.load(Ordering::Relaxed),
        )
    }

    pub fn is_healthy(&mut self) -> bool {
        !self.reader.is_finished() && self.server.try_wait().is_ok_and(|status| status.is_none())
    }

    pub async fn write_control(&self, bytes: &[u8]) -> EmulatorResult<()> {
        tokio::time::timeout(Duration::from_secs(5), async {
            self.control.lock().await.write_all(bytes).await
        })
        .await
        .map_err(|_| {
            EmulatorFailure::new(
                "operation_timeout",
                "Android control input timed out.",
                ["Reconnect the emulator tab and retry."],
            )
        })?
        .map_err(|error| {
            EmulatorFailure::new(
                "stream_failed",
                format!("Android control stream failed: {error}"),
                ["Reconnect the emulator tab and retry."],
            )
        })
    }

    pub async fn stop(mut self, adb: &Path, serial: &str) {
        self.reader.abort();
        let _ = self.server.kill().await;
        let _ = process::output(
            adb,
            &[
                "-s".into(),
                serial.into(),
                "forward".into(),
                "--remove".into(),
                format!("tcp:{}", self.port),
            ],
            "scrcpy port cleanup",
        )
        .await;
    }
}

async fn connect_with_data(port: u16) -> EmulatorResult<TcpStream> {
    for _ in 0..100 {
        if let Ok(mut stream) = TcpStream::connect(("127.0.0.1", port)).await {
            let mut first = [0_u8; 1];
            if tokio::time::timeout(Duration::from_secs(2), stream.read_exact(&mut first))
                .await
                .is_ok_and(|result| result.is_ok())
            {
                return Ok(stream);
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err(stream_start_failure("scrcpy video stream did not start."))
}

async fn connect_with_retry(port: u16) -> EmulatorResult<TcpStream> {
    for _ in 0..100 {
        if let Ok(stream) = TcpStream::connect(("127.0.0.1", port)).await {
            return Ok(stream);
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Err(stream_start_failure("scrcpy control stream did not start."))
}

async fn read_video(
    video: &mut TcpStream,
    source: AndroidVideoSource,
    width: Arc<AtomicU32>,
    height: Arc<AtomicU32>,
    meta_tx: oneshot::Sender<EmulatorResult<(u32, u32)>>,
) {
    let mut codec = [0_u8; CODEC_META_BYTES];
    if video.read_exact(&mut codec).await.is_err() {
        source.close();
        return;
    }
    if u32::from_be_bytes(codec) != H264_CODEC_ID {
        let _ = meta_tx.send(Err(stream_start_failure(
            "scrcpy did not negotiate an H.264 video stream.",
        )));
        source.close();
        return;
    }
    let mut meta_tx = Some(meta_tx);
    loop {
        let mut header = [0_u8; FRAME_HEADER_BYTES];
        if video.read_exact(&mut header).await.is_err() {
            break;
        }
        if let Some((next_width, next_height)) = session_dimensions(&header) {
            if next_width == 0 || next_height == 0 {
                if let Some(meta_tx) = meta_tx.take() {
                    let _ = meta_tx.send(Err(stream_start_failure(
                        "scrcpy reported an invalid video size.",
                    )));
                }
                break;
            }
            width.store(next_width, Ordering::Relaxed);
            height.store(next_height, Ordering::Relaxed);
            source.reset().await;
            if let Some(meta_tx) = meta_tx.take() {
                let _ = meta_tx.send(Ok((next_width, next_height)));
            }
            continue;
        }
        if meta_tx.is_some() {
            if let Some(meta_tx) = meta_tx.take() {
                let _ = meta_tx.send(Err(stream_start_failure(
                    "scrcpy omitted its initial video size.",
                )));
            }
            break;
        }
        let metadata = u64::from_be_bytes(header[..8].try_into().unwrap());
        let size = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
        if size > MAX_FRAME_BYTES {
            break;
        }
        let mut frame = vec![0_u8; size];
        if video.read_exact(&mut frame).await.is_err() {
            break;
        }
        let frame = Bytes::from(frame);
        let is_config = metadata & PACKET_FLAG_CONFIG != 0;
        let is_key = metadata & PACKET_FLAG_KEY_FRAME != 0;
        let kind = if is_config {
            AndroidVideoFrameKind::Config
        } else if is_key {
            AndroidVideoFrameKind::Key
        } else {
            AndroidVideoFrameKind::Delta
        };
        source.publish(kind, frame).await;
    }
    source.close();
}

fn session_dimensions(header: &[u8; FRAME_HEADER_BYTES]) -> Option<(u32, u32)> {
    let metadata = u64::from_be_bytes(header[..8].try_into().unwrap());
    if metadata & PACKET_FLAG_SESSION == 0 {
        return None;
    }
    Some((
        u32::from_be_bytes(header[4..8].try_into().unwrap()),
        u32::from_be_bytes(header[8..12].try_into().unwrap()),
    ))
}

async fn remove_forward(adb: &Path, serial: &str, port: u16) {
    let _ = process::output(
        adb,
        &[
            "-s".into(),
            serial.into(),
            "forward".into(),
            "--remove".into(),
            format!("tcp:{port}"),
        ],
        "scrcpy port cleanup",
    )
    .await;
}

fn scrcpy_id() -> String {
    let raw = u32::from_be_bytes(Uuid::new_v4().as_bytes()[..4].try_into().unwrap());
    format!("{:08x}", raw & 0x7fff_ffff)
}

fn stream_start_failure(message: impl Into<String>) -> EmulatorFailure {
    EmulatorFailure::new(
        "stream_failed",
        message,
        ["Restart the selected Android virtual device and retry."],
    )
}

pub fn bundled_server_path() -> EmulatorResult<PathBuf> {
    let executable = std::env::current_exe().map_err(|error| {
        EmulatorFailure::dependency(
            "scrcpy server",
            format!("Could not resolve the Alera executable: {error}"),
        )
    })?;
    let bundled = executable
        .parent()
        .unwrap_or(Path::new("."))
        .join("emulator/android/scrcpy/4.0/scrcpy-server");
    if bundled.is_file() {
        return Ok(bundled);
    }
    let development = PathBuf::from("resources/alera/emulator/android/scrcpy/4.0/scrcpy-server");
    if development.is_file() {
        return Ok(development);
    }
    Err(EmulatorFailure::dependency(
        "the bundled scrcpy server",
        format!(
            "scrcpy server asset was not found at {}.",
            bundled.display()
        ),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scrcpy_v4_session_metadata_carries_dynamic_dimensions() {
        let mut header = [0_u8; FRAME_HEADER_BYTES];
        header[..4].copy_from_slice(&0x8000_0000_u32.to_be_bytes());
        header[4..8].copy_from_slice(&1080_u32.to_be_bytes());
        header[8..12].copy_from_slice(&2400_u32.to_be_bytes());
        assert_eq!(session_dimensions(&header), Some((1080, 2400)));
    }

    #[test]
    fn scrcpy_v4_frame_flags_do_not_look_like_session_metadata() {
        let mut header = [0_u8; FRAME_HEADER_BYTES];
        header[..8].copy_from_slice(&PACKET_FLAG_CONFIG.to_be_bytes());
        header[8..12].copy_from_slice(&42_u32.to_be_bytes());
        assert_eq!(session_dimensions(&header), None);
    }
}
