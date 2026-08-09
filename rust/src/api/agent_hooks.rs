use std::collections::{HashMap, HashSet};
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use axum::body::{to_bytes, Body};
use axum::extract::State;
use axum::http::{HeaderMap, Request, StatusCode};
use axum::response::IntoResponse;
use axum::routing::post;
use axum::Router;
use serde_json::Value;
use tokio::net::TcpListener;
use tokio::runtime::{Builder, Runtime};
use tokio::sync::{mpsc, oneshot, RwLock};

use crate::frb_generated::StreamSink;

const AGENT_HOOK_TOKEN_HEADER: &str = "X-Alera-Agent-Hook-Token";
const REQUEST_MAX_BYTES: usize = 1_000_000;
const BATCH_MAX_EVENTS: usize = 64;
const BATCH_FLUSH_MILLIS: u64 = 16;
const COALESCE_THRESHOLD: usize = 1024;

pub struct AgentHookEndpointDto {
    pub port: u16,
}

pub struct AgentHookEventDto {
    pub terminal_session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub agent_type: String,
    pub payload_json: String,
    pub hook_event_name: Option<String>,
    pub version: Option<String>,
    pub inferred_event_name: Option<String>,
}

pub struct AgentHookEventBatchDto {
    pub events: Vec<AgentHookEventDto>,
    pub coalesced_intermediate_count: u32,
}

struct ServerHandle {
    port: u16,
    shutdown: oneshot::Sender<()>,
    enabled_agents: Arc<RwLock<HashSet<String>>>,
}

#[derive(Clone)]
struct AppState {
    token: String,
    enabled_agents: Arc<RwLock<HashSet<String>>>,
    tx: mpsc::UnboundedSender<AgentHookEventDto>,
}

struct Globals {
    server: Option<ServerHandle>,
    sink: Option<StreamSink<AgentHookEventBatchDto>>,
}

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static GLOBALS: OnceLock<Mutex<Globals>> = OnceLock::new();

pub fn start_agent_hook_receiver(
    token: String,
    enabled_agents: Vec<String>,
) -> Result<AgentHookEndpointDto, String> {
    let enabled = normalized_enabled_agents(enabled_agents);
    let mut globals = globals().lock().map_err(|_| "agent hook lock poisoned")?;
    if let Some(server) = &globals.server {
        let enabled_agents = server.enabled_agents.clone();
        runtime().spawn(async move {
            *enabled_agents.write().await = enabled;
        });
        return Ok(AgentHookEndpointDto { port: server.port });
    }

    let std_listener =
        std::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).map_err(|error| error.to_string())?;
    std_listener
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;
    let port = std_listener
        .local_addr()
        .map_err(|error| error.to_string())?
        .port();
    let (tx, rx) = mpsc::unbounded_channel();
    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let enabled_agents = Arc::new(RwLock::new(enabled));
    let state = AppState {
        token,
        enabled_agents: enabled_agents.clone(),
        tx,
    };

    runtime().spawn(batch_loop(rx));
    runtime().spawn(async move {
        let Ok(listener) = TcpListener::from_std(std_listener) else {
            return;
        };
        let app = Router::new()
            .route("/hook/codex", post(handle_codex))
            .route("/hook/claude", post(handle_claude))
            .route("/hook/copilot", post(handle_copilot))
            .route("/hook/cursor", post(handle_cursor))
            .route("/hook/agy", post(handle_agy))
            .route("/hook/opencode", post(handle_opencode))
            .route("/hook/opencode2", post(handle_opencode2))
            .route("/hook/pi", post(handle_pi))
            .route("/hook/amp", post(handle_amp))
            .route("/hook/grok", post(handle_grok))
            .with_state(state);
        let _ = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .with_graceful_shutdown(async {
            let _ = shutdown_rx.await;
        })
        .await;
    });

    globals.server = Some(ServerHandle {
        port,
        shutdown: shutdown_tx,
        enabled_agents,
    });
    Ok(AgentHookEndpointDto { port })
}

pub fn stop_agent_hook_receiver() {
    let Ok(mut globals) = globals().lock() else {
        return;
    };
    if let Some(server) = globals.server.take() {
        let _ = server.shutdown.send(());
    }
}

pub fn set_agent_hook_enabled_agents(enabled_agents: Vec<String>) {
    let Ok(globals) = globals().lock() else {
        return;
    };
    if let Some(server) = &globals.server {
        let enabled_agents_lock = server.enabled_agents.clone();
        let next = normalized_enabled_agents(enabled_agents);
        runtime().spawn(async move {
            *enabled_agents_lock.write().await = next;
        });
    }
}

pub fn watch_agent_hook_event_batches(sink: StreamSink<AgentHookEventBatchDto>) {
    if let Ok(mut globals) = globals().lock() {
        globals.sink = Some(sink);
    }
}

async fn handle_codex(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "codex").await
}

async fn handle_claude(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "claude").await
}

async fn handle_copilot(
    State(state): State<AppState>,
    request: Request<Body>,
) -> impl IntoResponse {
    handle_hook_request(state, request, "copilot").await
}

async fn handle_cursor(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "cursor").await
}

async fn handle_agy(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "agy").await
}

async fn handle_opencode(
    State(state): State<AppState>,
    request: Request<Body>,
) -> impl IntoResponse {
    handle_hook_request(state, request, "opencode").await
}

async fn handle_opencode2(
    State(state): State<AppState>,
    request: Request<Body>,
) -> impl IntoResponse {
    handle_hook_request(state, request, "opencode2").await
}

async fn handle_pi(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "pi").await
}

async fn handle_amp(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "amp").await
}

async fn handle_grok(State(state): State<AppState>, request: Request<Body>) -> impl IntoResponse {
    handle_hook_request(state, request, "grok").await
}

async fn handle_hook_request(
    state: AppState,
    request: Request<Body>,
    agent_type: &'static str,
) -> StatusCode {
    if !valid_token(request.headers(), &state.token) {
        return StatusCode::FORBIDDEN;
    }
    if !state.enabled_agents.read().await.contains(agent_type) {
        return StatusCode::NO_CONTENT;
    }

    let content_type = request
        .headers()
        .get(axum::http::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string();
    let body = match to_bytes(request.into_body(), REQUEST_MAX_BYTES).await {
        Ok(body) => body,
        Err(_) => return StatusCode::NO_CONTENT,
    };
    let Some(event) = parse_hook_event(agent_type, &content_type, &body) else {
        return StatusCode::NO_CONTENT;
    };
    let _ = state.tx.send(event);
    StatusCode::NO_CONTENT
}

fn valid_token(headers: &HeaderMap, expected: &str) -> bool {
    headers
        .get(AGENT_HOOK_TOKEN_HEADER)
        .and_then(|value| value.to_str().ok())
        == Some(expected)
}

fn parse_hook_event(
    agent_type: &str,
    content_type: &str,
    body: &[u8],
) -> Option<AgentHookEventDto> {
    if body.len() > REQUEST_MAX_BYTES {
        return None;
    }
    let text = String::from_utf8_lossy(body);
    let decoded = if text.trim().is_empty() {
        Value::Object(Default::default())
    } else if content_type.contains("application/x-www-form-urlencoded") {
        let form: HashMap<String, String> = serde_urlencoded::from_str(&text).ok()?;
        serde_json::to_value(form).ok()?
    } else {
        serde_json::from_str(&text).ok()?
    };
    let record = decoded.as_object()?;
    let terminal_session_id = required_string(record.get("terminalSessionId"))?;
    let workspace_id = required_string(record.get("workspaceId"))?;
    let tab_id = required_string(record.get("tabId"))?;
    let payload = payload_value(record.get("payload"))?;
    let hook_event_name = optional_string(record.get("hookEventName"))
        .or_else(|| optional_string(record.get("hook_event_name")));
    let version = optional_string(record.get("version"));
    let inferred_event_name = hook_event_name
        .clone()
        .or_else(|| optional_string(payload.get("hook_event_name")))
        .or_else(|| optional_string(payload.get("hookEventName")))
        .or_else(|| optional_string(payload.get("hook_type")))
        .or_else(|| optional_string(payload.get("hookType")));
    Some(AgentHookEventDto {
        terminal_session_id,
        workspace_id,
        tab_id,
        agent_type: agent_type.to_string(),
        payload_json: serde_json::to_string(&payload).ok()?,
        hook_event_name,
        version,
        inferred_event_name,
    })
}

fn required_string(value: Option<&Value>) -> Option<String> {
    let trimmed = value?.as_str()?.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn optional_string(value: Option<&Value>) -> Option<String> {
    let trimmed = value?.as_str()?.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn payload_value(value: Option<&Value>) -> Option<Value> {
    match value? {
        Value::String(raw) => {
            let decoded: Value = serde_json::from_str(raw).ok()?;
            decoded.as_object()?;
            Some(decoded)
        }
        Value::Object(_) => Some(value?.clone()),
        _ => None,
    }
}

async fn batch_loop(mut rx: mpsc::UnboundedReceiver<AgentHookEventDto>) {
    let mut interval = tokio::time::interval(Duration::from_millis(BATCH_FLUSH_MILLIS));
    let mut pending = Vec::new();
    loop {
        tokio::select! {
            maybe_event = rx.recv() => {
                let Some(event) = maybe_event else {
                    flush_events(&mut pending, 0);
                    break;
                };
                pending.push(event);
                if pending.len() > COALESCE_THRESHOLD {
                    let coalesced = coalesce_pending(&mut pending);
                    flush_events(&mut pending, coalesced);
                } else if pending.len() >= BATCH_MAX_EVENTS {
                    flush_events(&mut pending, 0);
                }
            }
            _ = interval.tick() => {
                flush_events(&mut pending, 0);
            }
        }
    }
}

fn flush_events(pending: &mut Vec<AgentHookEventDto>, coalesced_intermediate_count: u32) {
    if pending.is_empty() {
        return;
    }
    let Ok(mut globals) = globals().lock() else {
        return;
    };
    let Some(sink) = &globals.sink else {
        return;
    };
    let events = std::mem::take(pending);
    let batch = AgentHookEventBatchDto {
        events,
        coalesced_intermediate_count,
    };
    if sink.add(batch).is_err() {
        globals.sink = None;
    }
}

fn coalesce_pending(pending: &mut Vec<AgentHookEventDto>) -> u32 {
    let original_len = pending.len();
    let mut latest_by_key = HashMap::<(String, String), usize>::new();
    for (index, event) in pending.iter().enumerate() {
        if !is_session_close_event(event) {
            latest_by_key.insert(
                (event.terminal_session_id.clone(), event.agent_type.clone()),
                index,
            );
        }
    }
    let mut index = 0usize;
    pending.retain(|event| {
        let keep = if is_session_close_event(event) {
            true
        } else {
            latest_by_key
                .get(&(event.terminal_session_id.clone(), event.agent_type.clone()))
                .copied()
                == Some(index)
        };
        index += 1;
        keep
    });
    original_len.saturating_sub(pending.len()) as u32
}

fn is_session_close_event(event: &AgentHookEventDto) -> bool {
    let Some(name) = event.inferred_event_name.as_deref() else {
        return false;
    };
    matches!(
        (event.agent_type.as_str(), name),
        ("copilot", "SessionEnd")
            | ("cursor", "sessionEnd")
            | ("pi", "session_shutdown")
            | ("grok", "Stop")
            | ("grok", "StopFailure")
            | ("grok", "SessionEnd")
    )
}

fn normalized_enabled_agents(enabled_agents: Vec<String>) -> HashSet<String> {
    enabled_agents
        .into_iter()
        .map(|agent| agent.trim().to_string())
        .filter(|agent| !agent.is_empty())
        .collect()
}

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_time()
            .enable_io()
            .thread_name("alera-agent-hook")
            .build()
            .expect("failed to build agent hook runtime")
    })
}

fn globals() -> &'static Mutex<Globals> {
    GLOBALS.get_or_init(|| {
        Mutex::new(Globals {
            server: None,
            sink: None,
        })
    })
}

#[cfg(test)]
#[path = "agent_hooks_tests.rs"]
mod tests;
