use std::time::Duration;

use reqwest::header::{ACCEPT, AUTHORIZATION, USER_AGENT};
use reqwest::StatusCode;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::opencode_auth::{opencode_auth_key, OPENCODE_GO_PROVIDER};
use crate::terminal_host::diagnostics::redaction::register_secret;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::runtime_build_info;

pub(super) const OPENCODE_GO_LABEL: &str = "OpenCode Go";
pub(super) const OPENCODE_GO_DEFAULT_MODEL: &str = "glm-5.3-flash";
pub(super) const OPENCODE_GO_AGENT: &str = "opencode-go";

const OPENCODE_GO_BASE_URL: &str = "https://opencode.ai/zen/go/v1";
const OPENCODE_GO_SESSION_HEADER: &str = "x-opencode-session";
const KEY_MISSING: &str = "OpenCode Go API key was not found";
const KEY_REJECTED: &str = "OpenCode Go API key was rejected";
const SUBSCRIPTION_INACTIVE: &str = "OpenCode Go subscription is not active";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum OpenCodeGoRoute {
    ChatCompletions,
    Responses,
    Messages,
}

impl OpenCodeGoRoute {
    fn path(self) -> &'static str {
        match self {
            Self::ChatCompletions => "/chat/completions",
            Self::Responses => "/responses",
            Self::Messages => "/messages",
        }
    }
}

pub(super) fn route_for_model(model: &str) -> OpenCodeGoRoute {
    match model.trim() {
        "grok-4.6"
        | "gpt-5.6-luna"
        | "muse-spark-1.3-contributor"
        | "muse-spark-1.2-contributor" => OpenCodeGoRoute::Responses,
        "minimax-m3" | "minimax-m2.7" | "minimax-m2.5" | "qwen3.8-max" | "qwen3.8-flash"
        | "qwen3.7-max" | "qwen3.7-plus" | "qwen3.6-plus" => OpenCodeGoRoute::Messages,
        _ => OpenCodeGoRoute::ChatCompletions,
    }
}

pub(super) struct OpenCodeGoDiscoveredModel {
    pub id: String,
    pub label: String,
}

pub(super) fn completion_url(route: OpenCodeGoRoute) -> String {
    format!("{}{}", OPENCODE_GO_BASE_URL, route.path())
}

pub(super) async fn complete_opencode_go(
    prompt: &str,
    model: &str,
    session_id: &str,
    timeout: Duration,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<String> {
    let api_key = require_go_api_key().await?;
    let route = route_for_model(model);
    let url = completion_url(route);
    let body = request_body(route, model, prompt);
    let request = go_client(timeout)?
        .post(url)
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(ACCEPT, "application/json")
        .header(USER_AGENT, user_agent())
        .header(OPENCODE_GO_SESSION_HEADER, session_id)
        .json(&body);
    let (status, body) = send_and_read_cancellable(request, cancel_rx).await?;
    interpret_completion(route, status, body)
}

pub(super) async fn list_opencode_go_models(
    timeout: Duration,
) -> HostResult<Vec<OpenCodeGoDiscoveredModel>> {
    let api_key = require_go_api_key().await?;
    let response = go_client(timeout)?
        .get(format!("{OPENCODE_GO_BASE_URL}/models"))
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(ACCEPT, "application/json")
        .header(USER_AGENT, user_agent())
        .send()
        .await
        .map_err(|error| {
            HostError::state(format!("OpenCode Go model discovery failed: {error}"))
        })?;
    let status = response.status();
    let body = read_body(response).await?;
    if let Some(error) = map_go_http_error(status) {
        return Err(error);
    }
    if !status.is_success() {
        return Err(HostError::state(format!(
            "OpenCode Go model discovery failed (HTTP {status})"
        )));
    }
    let value: Value = serde_json::from_str(&body)
        .map_err(|_| HostError::state("Unable to parse OpenCode Go models"))?;
    let models = parse_models_catalog(&value);
    if models.is_empty() {
        return Err(HostError::state(
            "OpenCode Go returned no available models.",
        ));
    }
    Ok(models)
}

async fn require_go_api_key() -> HostResult<String> {
    let Some(api_key) = opencode_auth_key(OPENCODE_GO_PROVIDER).await else {
        return Err(HostError::state(KEY_MISSING));
    };
    register_secret(&api_key);
    Ok(api_key)
}

fn go_client(timeout: Duration) -> HostResult<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(timeout)
        .build()
        .map_err(|error| HostError::state(format!("OpenCode Go client failed: {error}")))
}

fn user_agent() -> String {
    format!("alera/{}", runtime_build_info::version())
}

pub(super) fn request_body(route: OpenCodeGoRoute, model: &str, prompt: &str) -> Value {
    match route {
        OpenCodeGoRoute::ChatCompletions => json!({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": false,
        }),
        OpenCodeGoRoute::Responses => json!({
            "model": model,
            "input": prompt,
            "store": false,
            "stream": true,
        }),
        OpenCodeGoRoute::Messages => json!({
            "model": model,
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": prompt}],
            "stream": false,
        }),
    }
}

async fn send_and_read_cancellable(
    request: reqwest::RequestBuilder,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<(StatusCode, String)> {
    tokio::select! {
        _ = cancel_rx => Err(HostError::state("Generation canceled.")),
        result = send_and_read(request) => result,
    }
}

async fn send_and_read(request: reqwest::RequestBuilder) -> HostResult<(StatusCode, String)> {
    let response = request
        .send()
        .await
        .map_err(|error| HostError::state(format!("OpenCode Go request failed: {error}")))?;
    let status = response.status();
    let body = read_body(response).await?;
    Ok((status, body))
}

async fn read_body(response: reqwest::Response) -> HostResult<String> {
    response
        .text()
        .await
        .map_err(|error| HostError::state(format!("OpenCode Go response failed: {error}")))
}

pub(super) fn interpret_completion(
    route: OpenCodeGoRoute,
    status: StatusCode,
    body: String,
) -> HostResult<String> {
    if let Some(error) = map_go_http_error(status) {
        return Err(error);
    }
    if !status.is_success() {
        return Err(HostError::state(format!(
            "OpenCode Go request failed (HTTP {status})"
        )));
    }
    let text = match route {
        OpenCodeGoRoute::ChatCompletions => extract_chat_completions_text(&body),
        OpenCodeGoRoute::Responses => extract_responses_text(&body),
        OpenCodeGoRoute::Messages => extract_messages_text(&body),
    }
    .unwrap_or_default();
    let trimmed = text.trim().to_string();
    if trimmed.is_empty() {
        return Err(HostError::state("OpenCode Go returned no text."));
    }
    Ok(trimmed)
}

pub(super) fn map_go_http_error(status: StatusCode) -> Option<HostError> {
    if status == StatusCode::UNAUTHORIZED {
        return Some(HostError::state(KEY_REJECTED));
    }
    if status == StatusCode::FORBIDDEN {
        return Some(HostError::state(SUBSCRIPTION_INACTIVE));
    }
    None
}

pub(super) fn extract_chat_completions_text(body: &str) -> Option<String> {
    if let Some(text) = extract_sse_text(body, |value| {
        value
            .pointer("/choices/0/delta/content")
            .and_then(json_text)
            .or_else(|| {
                value
                    .pointer("/choices/0/message/content")
                    .and_then(json_text)
            })
    }) {
        return Some(text);
    }
    let value: Value = serde_json::from_str(body).ok()?;
    value
        .pointer("/choices/0/message/content")
        .and_then(json_text)
}

pub(super) fn extract_responses_text(body: &str) -> Option<String> {
    if let Some(text) = extract_sse_text(body, |value| {
        if value.get("type").and_then(Value::as_str) == Some("response.output_text.delta") {
            return json_text(value.get("delta").unwrap_or(&Value::Null));
        }
        value
            .pointer("/response/output_text")
            .and_then(json_text)
            .or_else(|| collect_responses_output(value))
    }) {
        return Some(text);
    }
    let value: Value = serde_json::from_str(body).ok()?;
    json_text(value.get("output_text").unwrap_or(&Value::Null))
        .or_else(|| collect_responses_output(&value))
}

pub(super) fn extract_messages_text(body: &str) -> Option<String> {
    if let Some(text) = extract_sse_text(body, |value| {
        value
            .pointer("/delta/text")
            .and_then(json_text)
            .or_else(|| collect_anthropic_content(value))
    }) {
        return Some(text);
    }
    let value: Value = serde_json::from_str(body).ok()?;
    collect_anthropic_content(&value)
}

pub(super) fn parse_models_catalog(value: &Value) -> Vec<OpenCodeGoDiscoveredModel> {
    let items = value
        .get("data")
        .or_else(|| value.get("models"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut models = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for item in items {
        let Some(id) = item
            .get("id")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|id| !id.is_empty())
        else {
            continue;
        };
        if !seen.insert(id.to_string()) {
            continue;
        }
        let label = item
            .get("name")
            .or_else(|| item.get("display_name"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|label| !label.is_empty())
            .unwrap_or(id)
            .to_string();
        models.push(OpenCodeGoDiscoveredModel {
            id: id.to_string(),
            label,
        });
    }
    models
}

fn collect_responses_output(value: &Value) -> Option<String> {
    let output = value.get("output")?.as_array()?;
    let mut parts = Vec::new();
    for item in output {
        let Some(content) = item.get("content").and_then(Value::as_array) else {
            continue;
        };
        for block in content {
            if let Some(text) = json_text(block.get("text").unwrap_or(&Value::Null)) {
                parts.push(text);
            }
        }
    }
    join_parts(parts)
}

fn collect_anthropic_content(value: &Value) -> Option<String> {
    let content = value.get("content")?.as_array()?;
    let mut parts = Vec::new();
    for block in content {
        if let Some(text) = json_text(block.get("text").unwrap_or(&Value::Null)) {
            parts.push(text);
        }
    }
    join_parts(parts)
}

fn extract_sse_text(body: &str, extract: impl Fn(&Value) -> Option<String>) -> Option<String> {
    if !body.contains("data:") {
        return None;
    }
    let mut parts = Vec::new();
    for chunk in body.split("\n\n") {
        for line in chunk.lines() {
            let Some(data) = line.strip_prefix("data:") else {
                continue;
            };
            let data = data.trim();
            if data.is_empty() || data == "[DONE]" {
                continue;
            }
            if let Ok(value) = serde_json::from_str::<Value>(data) {
                if let Some(text) = extract(&value) {
                    parts.push(text);
                }
            }
        }
    }
    join_parts(parts)
}

fn json_text(value: &Value) -> Option<String> {
    match value {
        Value::String(text) if !text.is_empty() => Some(text.clone()),
        Value::Array(parts) => {
            let mut text = String::new();
            for part in parts {
                if let Some(piece) = part
                    .get("text")
                    .and_then(Value::as_str)
                    .or_else(|| part.as_str())
                {
                    text.push_str(piece);
                }
            }
            (!text.is_empty()).then_some(text)
        }
        _ => None,
    }
}

fn join_parts(parts: Vec<String>) -> Option<String> {
    let text = parts.concat();
    (!text.is_empty()).then_some(text)
}

#[cfg(test)]
#[path = "ai_assist_opencode_go_tests.rs"]
mod tests;
