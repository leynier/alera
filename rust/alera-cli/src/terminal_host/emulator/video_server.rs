use std::collections::{HashMap, VecDeque};
use std::convert::Infallible;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::Response;
use axum::routing::get;
use axum::Router;
use bytes::Bytes;
use futures_util::stream::{self, StreamExt as _};
use serde::Deserialize;
use tokio::net::TcpListener;
use tokio::sync::{broadcast, watch, Mutex, RwLock};

use super::contract::{EmulatorFailure, EmulatorResult};

const MAX_ANDROID_REPLAY_BYTES: usize = 64 * 1024 * 1024;
const MAX_ANDROID_REPLAY_PACKETS: usize = 600;
const IOS_PROXY_IDLE_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Copy)]
pub enum AndroidVideoFrameKind {
    Config,
    Key,
    Delta,
}

#[derive(Clone)]
struct AndroidVideoPacket {
    sequence: u64,
    bytes: Bytes,
}

#[derive(Default)]
struct AndroidReplayState {
    last_sequence: u64,
    config: Option<AndroidVideoPacket>,
    gop: Vec<AndroidVideoPacket>,
    gop_bytes: usize,
}

struct AndroidSubscription {
    receiver: broadcast::Receiver<AndroidVideoPacket>,
    closed: watch::Receiver<bool>,
    pending: VecDeque<AndroidVideoPacket>,
    next_sequence: u64,
}

#[derive(Clone)]
pub struct AndroidVideoSource {
    sender: broadcast::Sender<AndroidVideoPacket>,
    closed: watch::Sender<bool>,
    replay: Arc<Mutex<AndroidReplayState>>,
}

impl AndroidVideoSource {
    pub fn new(channel_capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(channel_capacity);
        let (closed, _) = watch::channel(false);
        Self {
            sender,
            closed,
            replay: Arc::new(Mutex::new(AndroidReplayState::default())),
        }
    }

    pub fn close(&self) {
        self.closed.send_replace(true);
    }

    pub async fn reset(&self) {
        let mut replay = self.replay.lock().await;
        replay.config = None;
        replay.gop.clear();
        replay.gop_bytes = 0;
    }

    pub async fn publish(&self, kind: AndroidVideoFrameKind, bytes: Bytes) {
        // Replay state and broadcast position must advance under the same lock so
        // a subscriber sees each packet in either its snapshot or its receiver.
        let mut replay = self.replay.lock().await;
        replay.last_sequence = replay.last_sequence.wrapping_add(1);
        let packet = AndroidVideoPacket {
            sequence: replay.last_sequence,
            bytes,
        };
        match kind {
            AndroidVideoFrameKind::Config => {
                replay.config = Some(packet.clone());
                replay.gop.clear();
                replay.gop_bytes = 0;
            }
            AndroidVideoFrameKind::Key => {
                replay.gop.clear();
                replay.gop_bytes = 0;
                if replay_size_with(&replay, &packet) <= MAX_ANDROID_REPLAY_BYTES {
                    replay.gop_bytes = packet.bytes.len();
                    replay.gop.push(packet.clone());
                }
            }
            AndroidVideoFrameKind::Delta => {
                if !replay.gop.is_empty()
                    && replay.gop.len() < MAX_ANDROID_REPLAY_PACKETS
                    && replay_size_with(&replay, &packet) <= MAX_ANDROID_REPLAY_BYTES
                {
                    replay.gop_bytes += packet.bytes.len();
                    replay.gop.push(packet.clone());
                } else if !replay.gop.is_empty() {
                    // A partial GOP cannot initialize a decoder, so wait for the
                    // next keyframe instead of evicting only its oldest packets.
                    replay.gop.clear();
                    replay.gop_bytes = 0;
                }
            }
        }
        let _ = self.sender.send(packet);
    }

    async fn subscribe(&self, next_sequence: Option<u64>) -> AndroidSubscription {
        let replay = self.replay.lock().await;
        let receiver = self.sender.subscribe();
        let pending = match next_sequence {
            Some(next_sequence) => recovery_packets(&replay, next_sequence),
            None => initial_packets(&replay),
        };
        AndroidSubscription {
            receiver,
            closed: self.closed.subscribe(),
            pending,
            next_sequence: replay.last_sequence.wrapping_add(1),
        }
    }
}

fn replay_size_with(replay: &AndroidReplayState, packet: &AndroidVideoPacket) -> usize {
    replay
        .config
        .as_ref()
        .map_or(0, |config| config.bytes.len())
        .saturating_add(replay.gop_bytes)
        .saturating_add(packet.bytes.len())
}

fn initial_packets(replay: &AndroidReplayState) -> VecDeque<AndroidVideoPacket> {
    replay
        .config
        .iter()
        .chain(replay.gop.iter())
        .cloned()
        .collect()
}

fn recovery_packets(
    replay: &AndroidReplayState,
    next_sequence: u64,
) -> VecDeque<AndroidVideoPacket> {
    let gop_start = replay.gop.first().map(|packet| packet.sequence);
    let restart_from_keyframe = gop_start.is_some_and(|start| next_sequence < start);
    let config = replay
        .config
        .iter()
        .filter(|packet| packet.sequence >= next_sequence || restart_from_keyframe);
    let gop = replay
        .gop
        .iter()
        .filter(|packet| packet.sequence >= next_sequence || restart_from_keyframe);
    config.chain(gop).cloned().collect()
}

#[derive(Clone)]
pub enum VideoSource {
    Android(AndroidVideoSource),
    Proxy {
        url: String,
        healthy: Arc<AtomicBool>,
    },
}

#[derive(Clone)]
struct VideoEntry {
    token: String,
    source: VideoSource,
}

#[derive(Clone)]
pub struct VideoRegistry {
    entries: Arc<RwLock<HashMap<String, VideoEntry>>>,
    port: u16,
}

#[derive(Deserialize)]
struct TokenQuery {
    token: String,
}

impl VideoRegistry {
    pub async fn bind() -> EmulatorResult<Self> {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.map_err(|error| {
            EmulatorFailure::new(
                "stream_failed",
                format!("Could not bind the local emulator stream: {error}"),
                ["Check local firewall policy and retry."],
            )
        })?;
        let port = listener
            .local_addr()
            .map_err(|error| {
                EmulatorFailure::new(
                    "stream_failed",
                    format!("Could not read the emulator stream address: {error}"),
                    ["Retry the operation."],
                )
            })?
            .port();
        let registry = Self {
            entries: Arc::new(RwLock::new(HashMap::new())),
            port,
        };
        let router = Router::new()
            .route("/emulator/{session_id}/video", get(video))
            .with_state(registry.clone());
        tokio::spawn(async move {
            if let Err(error) = axum::serve(listener, router).await {
                eprintln!("alera emulator video server stopped: {error}");
            }
        });
        Ok(registry)
    }

    pub async fn register(&self, session_id: &str, token: String, source: VideoSource) -> String {
        self.entries.write().await.insert(
            session_id.to_string(),
            VideoEntry {
                token: token.clone(),
                source,
            },
        );
        format!(
            "http://127.0.0.1:{}/emulator/{session_id}/video?token={token}",
            self.port
        )
    }

    pub async fn remove(&self, session_id: &str) {
        self.entries.write().await.remove(session_id);
    }
}

async fn video(
    State(registry): State<VideoRegistry>,
    Path(session_id): Path<String>,
    Query(query): Query<TokenQuery>,
) -> Response {
    let entry = registry.entries.read().await.get(&session_id).cloned();
    let Some(entry) = entry else {
        return response(StatusCode::NOT_FOUND, "text/plain", Body::from("not found"));
    };
    if entry.token.as_bytes() != query.token.as_bytes() {
        return response(
            StatusCode::UNAUTHORIZED,
            "text/plain",
            Body::from("unauthorized"),
        );
    }
    match entry.source {
        VideoSource::Android(source) => android_response(source).await,
        VideoSource::Proxy { url, healthy } => proxy_response(url, healthy).await,
    }
}

async fn android_response(source: AndroidVideoSource) -> Response {
    response(
        StatusCode::OK,
        "video/h264",
        Body::from_stream(android_stream(source).await),
    )
}

async fn android_stream(
    source: AndroidVideoSource,
) -> impl futures_util::Stream<Item = Result<Bytes, Infallible>> {
    let subscription = source.subscribe(None).await;
    stream::unfold(
        (source, subscription),
        |(source, mut subscription)| async move {
            loop {
                if !subscription.pending.is_empty() {
                    let packet = subscription.pending.pop_front().unwrap();
                    return Some((Ok(packet.bytes), (source, subscription)));
                }
                if *subscription.closed.borrow() {
                    return None;
                }
                let received = tokio::select! {
                    packet = subscription.receiver.recv() => Some(packet),
                    changed = subscription.closed.changed() => {
                        if changed.is_err() || *subscription.closed.borrow() {
                            None
                        } else {
                            continue;
                        }
                    }
                };
                let received = received?;
                match received {
                    Ok(packet) if packet.sequence < subscription.next_sequence => continue,
                    Ok(packet) => {
                        subscription.next_sequence = packet.sequence.wrapping_add(1);
                        return Some((Ok(packet.bytes), (source, subscription)));
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        subscription = source.subscribe(Some(subscription.next_sequence)).await;
                    }
                    Err(broadcast::error::RecvError::Closed) => return None,
                }
            }
        },
    )
}

async fn proxy_response(url: String, healthy: Arc<AtomicBool>) -> Response {
    let Ok(url) = reqwest::Url::parse(&url) else {
        healthy.store(false, Ordering::Relaxed);
        return unavailable_proxy_response();
    };
    if url.scheme() != "http" || url.host_str() != Some("::1") {
        healthy.store(false, Ordering::Relaxed);
        return unavailable_proxy_response();
    }
    let client = match reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .no_proxy()
        .connect_timeout(Duration::from_secs(3))
        .build()
    {
        Ok(client) => client,
        Err(_) => {
            healthy.store(false, Ordering::Relaxed);
            return unavailable_proxy_response();
        }
    };
    let upstream = match tokio::time::timeout(Duration::from_secs(5), client.get(url).send()).await
    {
        Ok(Ok(response)) if response.status().is_success() => response,
        _ => {
            healthy.store(false, Ordering::Relaxed);
            return unavailable_proxy_response();
        }
    };
    let content_type = upstream
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("multipart/x-mixed-replace")
        .to_string();
    let upstream_stream = upstream
        .bytes_stream()
        .map(|result| result.map_err(std::io::Error::other));
    let stream = monitored_proxy_stream(upstream_stream, IOS_PROXY_IDLE_TIMEOUT, healthy);
    response(StatusCode::OK, &content_type, Body::from_stream(stream))
}

fn monitored_proxy_stream<S>(
    stream: S,
    timeout: Duration,
    healthy: Arc<AtomicBool>,
) -> impl futures_util::Stream<Item = Result<Bytes, std::io::Error>>
where
    S: futures_util::Stream<Item = Result<Bytes, std::io::Error>> + Send + 'static,
{
    stream::unfold(Some(Box::pin(stream)), move |state| {
        let healthy = healthy.clone();
        async move {
            let mut stream = state?;
            match tokio::time::timeout(timeout, stream.next()).await {
                Ok(Some(Ok(bytes))) => Some((Ok(bytes), Some(stream))),
                Ok(Some(Err(error))) => {
                    healthy.store(false, Ordering::Relaxed);
                    Some((Err(error), None))
                }
                Ok(None) => {
                    healthy.store(false, Ordering::Relaxed);
                    None
                }
                Err(_) => {
                    healthy.store(false, Ordering::Relaxed);
                    Some((
                        Err(std::io::Error::new(
                            std::io::ErrorKind::TimedOut,
                            "iOS emulator video stream became idle",
                        )),
                        None,
                    ))
                }
            }
        }
    })
}

fn unavailable_proxy_response() -> Response {
    response(
        StatusCode::BAD_GATEWAY,
        "text/plain",
        Body::from("emulator stream unavailable"),
    )
}

fn response(status: StatusCode, content_type: &str, body: Body) -> Response {
    let mut response = Response::new(body);
    *response.status_mut() = status;
    if let Ok(value) = HeaderValue::from_str(content_type) {
        response.headers_mut().insert(header::CONTENT_TYPE, value);
    }
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

#[cfg(test)]
#[path = "video_server_tests.rs"]
mod tests;
