use std::collections::HashMap;
use std::net::{Ipv4Addr, SocketAddr};
use std::path::Path;

use axum::body::{to_bytes, Body};
use axum::extract::{Path as AxumPath, State};
use axum::http::{HeaderMap, Request, StatusCode};
use axum::routing::post;
use axum::Router;
use serde_json::Value;
use tokio::net::TcpListener;
use tokio::sync::mpsc::UnboundedSender;
use uuid::Uuid;

use crate::terminal_host::server::ServerCommand;

const TOKEN_HEADER: &str = "X-Alera-Agent-Hook-Token";
const REQUEST_MAX_BYTES: usize = 1_000_000;
const SUPPORTED_AGENTS: [&str; 11] = [
    "codex",
    "claude",
    "copilot",
    "cursor",
    "agy",
    "opencode",
    "opencode2",
    "pi",
    "amp",
    "grok",
    "fx",
];

#[derive(Debug, Clone)]
pub struct AgentHookEvent {
    pub terminal_session_id: String,
    pub workspace_id: String,
    pub tab_id: String,
    pub agent_type: String,
    pub payload: Value,
    pub event_name: Option<String>,
}

#[derive(Clone)]
struct HookState {
    token: String,
    inbox: UnboundedSender<ServerCommand>,
}

pub async fn start_hook_receiver(
    runtime_dir: &Path,
    inbox: UnboundedSender<ServerCommand>,
) -> anyhow::Result<u16> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?;
    let port = listener.local_addr()?.port();
    let token = Uuid::new_v4().to_string();
    write_endpoint_file(runtime_dir, port, &token)?;
    let state = HookState { token, inbox };
    let app = Router::new()
        .route("/hook/{agent}", post(handle_hook))
        .with_state(state);
    tokio::spawn(async move {
        let _ = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await;
    });
    Ok(port)
}

async fn handle_hook(
    AxumPath(agent): AxumPath<String>,
    State(state): State<HookState>,
    request: Request<Body>,
) -> StatusCode {
    if !SUPPORTED_AGENTS.contains(&agent.as_str()) || !valid_token(request.headers(), &state.token)
    {
        return StatusCode::FORBIDDEN;
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
    let Some(event) = parse_hook_event(&agent, &content_type, &body) else {
        return StatusCode::NO_CONTENT;
    };
    let _ = state.inbox.send(ServerCommand::AgentHookEvent { event });
    StatusCode::NO_CONTENT
}

fn valid_token(headers: &HeaderMap, expected: &str) -> bool {
    headers
        .get(TOKEN_HEADER)
        .and_then(|value| value.to_str().ok())
        == Some(expected)
}

fn parse_hook_event(agent: &str, content_type: &str, body: &[u8]) -> Option<AgentHookEvent> {
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
    let payload = match record.get("payload")? {
        Value::Object(_) => record.get("payload")?.clone(),
        Value::String(raw) => serde_json::from_str(raw).ok()?,
        _ => return None,
    };
    let payload_record = payload.as_object()?;
    let event_name = optional_string(record.get("hookEventName"))
        .or_else(|| optional_string(record.get("hook_event_name")))
        .or_else(|| optional_string(payload_record.get("hook_event_name")))
        .or_else(|| optional_string(payload_record.get("hookEventName")))
        .or_else(|| optional_string(payload_record.get("hook_type")))
        .or_else(|| optional_string(payload_record.get("hookType")));
    Some(AgentHookEvent {
        terminal_session_id: required_string(record.get("terminalSessionId"))?,
        workspace_id: required_string(record.get("workspaceId"))?,
        tab_id: required_string(record.get("tabId"))?,
        agent_type: agent.to_string(),
        payload,
        event_name,
    })
}

fn required_string(value: Option<&Value>) -> Option<String> {
    optional_string(value)
}

fn optional_string(value: Option<&Value>) -> Option<String> {
    let value = value?.as_str()?.trim();
    (!value.is_empty()).then(|| value.to_string())
}

fn write_endpoint_file(runtime_dir: &Path, port: u16, token: &str) -> anyhow::Result<()> {
    let directory = runtime_dir.join("agent-hooks");
    std::fs::create_dir_all(&directory)?;
    #[cfg(windows)]
    let (path, contents) = (
        directory.join("endpoint.cmd"),
        format!(
            "set ALERA_AGENT_HOOK_PORT={port}\r\nset ALERA_AGENT_HOOK_TOKEN={token}\r\nset ALERA_AGENT_HOOK_VERSION=1\r\n"
        ),
    );
    #[cfg(not(windows))]
    let (path, contents) = (
        directory.join("endpoint.env"),
        format!(
            "ALERA_AGENT_HOOK_PORT={port}\nALERA_AGENT_HOOK_TOKEN={token}\nALERA_AGENT_HOOK_VERSION=1\n"
        ),
    );
    std::fs::write(&path, contents)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}
