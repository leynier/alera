use super::{chatgpt_oauth, chatgpt_session};
use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{
    RuntimeAiAssistSettings, CHAT_GPT_SERVICE_TIER_DEFAULT, CHAT_GPT_SERVICE_TIER_FAST,
};
use futures_util::StreamExt;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::time::Duration;
use tokio::sync::oneshot;

const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;
const SUPPORTED_REASONING_EFFORTS: [&str; 7] =
    ["none", "minimal", "low", "medium", "high", "xhigh", "max"];

pub(super) struct ConfiguredThinking {
    pub(super) operation: Option<String>,
    pub(super) selected_by_model: HashMap<String, String>,
    pub(super) selected_by_operation: HashMap<String, HashMap<String, String>>,
}

impl ConfiguredThinking {
    pub(super) fn from_settings(operation: &str, settings: &RuntimeAiAssistSettings) -> Self {
        Self {
            operation: Some(operation.to_string()),
            selected_by_model: settings.selected_thinking_by_model.clone(),
            selected_by_operation: settings.selected_thinking_by_operation.clone(),
        }
    }

    pub(super) fn effort_for(&self, actual_model: &str) -> Option<&str> {
        let operation_values = self
            .operation
            .as_ref()
            .and_then(|operation| self.selected_by_operation.get(operation));
        operation_values
            .and_then(|values| values.get(actual_model))
            .map(String::as_str)
            .or_else(|| self.selected_by_model.get(actual_model).map(String::as_str))
    }
}

pub(super) fn resolve_thinking_level<'a>(
    explicit: Option<&'a str>,
    configured: Option<&'a ConfiguredThinking>,
    actual_model: &str,
) -> Option<&'a str> {
    explicit.or_else(|| configured.and_then(|value| value.effort_for(actual_model)))
}

pub(super) async fn models() -> HostResult<Value> {
    let session = chatgpt_session::session()?;
    let (token, mut changed) = session.access().await?;
    tokio::select! {
        _ = changed.changed() => Err(HostError::state("ChatGPT account changed. Try again.")),
        result = fetch_models(&token) => result,
    }
}

async fn fetch_models(token: &str) -> HostResult<Value> {
    let response = chatgpt_oauth::client()?
        .get(format!("{}/models", chatgpt_oauth::RESOURCE))
        .bearer_auth(token)
        .send()
        .await
        .map_err(|_| HostError::state("ChatGPT model discovery failed."))?;
    let status = response.status();
    let request_id = request_id(&response);
    let body = read_bounded(response).await?;
    if !status.is_success() {
        return Err(with_request_id(
            api_error(status.as_u16(), &body),
            request_id,
        ));
    }
    let value: Value = serde_json::from_slice(&body)
        .map_err(|_| HostError::state("ChatGPT model catalog is invalid."))?;
    catalog(&value)
}

pub(super) fn catalog(value: &Value) -> HostResult<Value> {
    let items = value
        .get("models")
        .and_then(Value::as_array)
        .ok_or_else(|| HostError::state("ChatGPT model catalog is invalid."))?;
    let mut seen = std::collections::HashSet::new();
    let models: Vec<Value> = items
        .iter()
        .filter_map(|item| {
            if item.get("visibility")?.as_str()? != "list" {
                return None;
            }
            let id = item.get("slug")?.as_str()?.trim();
            let label = item.get("display_name")?.as_str()?.trim();
            if id.is_empty() || label.is_empty() || !seen.insert(id) {
                return None;
            }
            let mut model = json!({"id": id, "label": label});
            let (thinking_levels, default_thinking_level) = reasoning_metadata(item);
            if let Some(levels) = thinking_levels {
                model["thinkingLevels"] = Value::Array(levels);
            }
            if let Some(level) = default_thinking_level {
                model["defaultThinkingLevel"] = Value::String(level);
            }
            Some(model)
        })
        .collect();
    if models.is_empty() {
        return Err(HostError::state(
            "No models are available for this ChatGPT account.",
        ));
    }
    Ok(json!({"defaultModelId": models[0]["id"], "models": models}))
}

fn reasoning_metadata(item: &Value) -> (Option<Vec<Value>>, Option<String>) {
    let supported = item.get("supported_reasoning_levels");
    let levels = supported.and_then(Value::as_array).map(|entries| {
        let mut seen = std::collections::HashSet::new();
        entries
            .iter()
            .filter_map(|entry| {
                let effort = entry
                    .get("effort")
                    .and_then(Value::as_str)
                    .and_then(normalize_known_effort)?;
                seen.insert(effort)
                    .then(|| json!({"id": effort, "label": reasoning_effort_label(effort)}))
            })
            .collect::<Vec<_>>()
    });
    let default = item
        .get("default_reasoning_level")
        .and_then(Value::as_str)
        .and_then(normalize_known_effort)
        .filter(|effort| {
            levels
                .as_ref()
                .is_none_or(|levels| levels.iter().any(|level| level["id"] == *effort))
        })
        .map(str::to_string);
    (levels, default)
}

fn normalize_known_effort(value: &str) -> Option<&'static str> {
    let value = value.trim().to_ascii_lowercase();
    SUPPORTED_REASONING_EFFORTS
        .iter()
        .copied()
        .find(|effort| *effort == value)
}

fn reasoning_effort_label(effort: &str) -> &'static str {
    match effort {
        "none" => "None",
        "minimal" => "Minimal",
        "low" => "Low",
        "medium" => "Medium",
        "high" => "High",
        "xhigh" => "Extra High",
        "max" => "Maximum",
        _ => "Reasoning",
    }
}

pub(super) fn normalize_thinking_level(value: Option<&str>) -> HostResult<Option<String>> {
    let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    normalize_known_effort(value)
        .map(str::to_string)
        .map(Some)
        .ok_or_else(|| {
            HostError::format(
                "Unsupported ChatGPT thinking level. Use none, minimal, low, medium, high, xhigh, or max.",
            )
        })
}

pub(super) fn normalize_service_tier(value: Option<&str>) -> HostResult<String> {
    let value = value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(CHAT_GPT_SERVICE_TIER_DEFAULT)
        .to_ascii_lowercase();
    match value.as_str() {
        CHAT_GPT_SERVICE_TIER_DEFAULT | CHAT_GPT_SERVICE_TIER_FAST => Ok(value),
        _ => Err(HostError::format(
            "Unsupported ChatGPT service tier. Use default or fast.",
        )),
    }
}

pub(super) fn validate_effort_for_model(model: &Value, effort: Option<&str>) -> HostResult<()> {
    let Some(effort) = effort else {
        return Ok(());
    };
    let Some(levels) = model.get("thinkingLevels").and_then(Value::as_array) else {
        // Older model catalog entries have no capability metadata. Known
        // Responses API effort values remain usable and the provider decides
        // whether that model accepts the request.
        return Ok(());
    };
    if levels.iter().any(|level| level["id"] == effort) {
        return Ok(());
    }
    Err(HostError::format(format!(
        "ChatGPT model {} does not support thinking level {effort}.",
        model["id"].as_str().unwrap_or("selected")
    )))
}

pub(super) async fn complete_with_options(
    prompt: &str,
    model: &str,
    thinking_level: Option<&str>,
    service_tier: Option<&str>,
    configured: Option<ConfiguredThinking>,
    timeout: Duration,
    cancel: oneshot::Receiver<()>,
) -> HostResult<String> {
    let thinking_level = normalize_thinking_level(thinking_level)?;
    let service_tier = normalize_service_tier(service_tier)?;
    tokio::select! {
        _ = cancel => Err(HostError::state("Generation canceled.")),
        result = tokio::time::timeout(timeout, complete_request(prompt, model, thinking_level.as_deref(), &service_tier, configured)) =>
            result.unwrap_or_else(|_| Err(HostError::state("ChatGPT generation timed out."))),
    }
}

pub(super) async fn complete_configured(
    prompt: &str,
    model: &str,
    operation: &str,
    settings: &RuntimeAiAssistSettings,
    timeout: Duration,
    cancel: oneshot::Receiver<()>,
) -> HostResult<String> {
    let service_tier = normalize_service_tier(Some(&settings.chat_gpt_service_tier))?;
    let configured = ConfiguredThinking::from_settings(operation, settings);
    tokio::select! {
        _ = cancel => Err(HostError::state("Generation canceled.")),
        result = tokio::time::timeout(timeout, complete_request(prompt, model, None, &service_tier, Some(configured))) =>
            result.unwrap_or_else(|_| Err(HostError::state("ChatGPT generation timed out."))),
    }
}

pub(super) fn request_body(prompt: &str, model: &str) -> Value {
    request_body_with_options(prompt, model, None, CHAT_GPT_SERVICE_TIER_DEFAULT)
}

pub(super) fn request_body_with_options(
    prompt: &str,
    model: &str,
    thinking_level: Option<&str>,
    service_tier: &str,
) -> Value {
    let mut body = json!({
        "model": model,
        "input": [{"role": "user", "content": prompt}],
        "store": false,
        "stream": true,
        "service_tier": service_tier,
    });
    if let Some(effort) = thinking_level {
        body["reasoning"] = json!({"effort": effort});
    }
    body
}

async fn complete_request(
    prompt: &str,
    selected: &str,
    thinking_level: Option<&str>,
    service_tier: &str,
    configured: Option<ConfiguredThinking>,
) -> HostResult<String> {
    if prompt.len() > MAX_RESPONSE_BYTES {
        return Err(HostError::state("ChatGPT prompt is too large."));
    }
    let session = chatgpt_session::session()?;
    let (token, mut changed) = session.access().await?;
    tokio::select! {
        _ = changed.changed() => Err(HostError::state("ChatGPT account changed. Generation canceled.")),
        result = async {
            // Catalog and inference use the same credential snapshot.
            let available = fetch_models(&token).await?;
            let model = if selected.trim().is_empty() { available["defaultModelId"].as_str().unwrap() } else { selected.trim() };
            let Some(model_entry) = available["models"].as_array().and_then(|models| models.iter().find(|item| item["id"] == model)) else {
                return Err(HostError::state("This model is unavailable for the active ChatGPT account. Refresh models in Settings > AI Assist."));
            };
            let thinking_level =
                resolve_thinking_level(thinking_level, configured.as_ref(), model);
            let thinking_level = normalize_thinking_level(thinking_level)?;
            validate_effort_for_model(model_entry, thinking_level.as_deref())?;
            let client = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).build()
                .map_err(|_| HostError::state("ChatGPT connection failed."))?;
            let body = if thinking_level.is_none()
                && service_tier == CHAT_GPT_SERVICE_TIER_DEFAULT
            {
                request_body(prompt, model)
            } else {
                request_body_with_options(prompt, model, thinking_level.as_deref(), service_tier)
            };
            let response = client.post(format!("{}/responses", chatgpt_oauth::RESOURCE))
                .bearer_auth(token).header("Accept", "text/event-stream")
                .json(&body).send().await
                .map_err(|_| HostError::state("ChatGPT request failed. Try again."))?;
            let status = response.status();
            let request_id = request_id(&response);
            let body = read_bounded(response).await?;
            if !status.is_success() { return Err(with_request_id(api_error(status.as_u16(), &body), request_id)); }
            parse_stream(&body).map_err(|error| with_request_id(error, request_id))
        } => result,
    }
}

fn request_id(response: &reqwest::Response) -> Option<String> {
    response
        .headers()
        .get("openai-request-id")
        .or_else(|| response.headers().get("x-request-id"))
        .and_then(|v| v.to_str().ok())
        .filter(|s| s.len() <= 128)
        .map(str::to_string)
}

fn with_request_id(error: HostError, request_id: Option<String>) -> HostError {
    let Some(request_id) = request_id else {
        return error;
    };
    match error {
        HostError::Conflict {
            code,
            message,
            mut details,
        } => {
            details["requestId"] = json!(request_id);
            HostError::Conflict {
                code,
                message,
                details,
            }
        }
        error => HostError::conflict(
            "chatgptRequestFailed",
            error.to_string(),
            json!({"requestId":request_id}),
        ),
    }
}

async fn read_bounded(response: reqwest::Response) -> HostResult<Vec<u8>> {
    let mut stream = response.bytes_stream();
    let mut bytes = Vec::new();
    while let Some(chunk) = stream.next().await {
        let chunk =
            chunk.map_err(|_| HostError::state("ChatGPT connection ended before completion."))?;
        if bytes.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err(HostError::state(
                "ChatGPT response exceeded the size limit.",
            ));
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

pub(super) fn parse_stream(bytes: &[u8]) -> HostResult<String> {
    let body = std::str::from_utf8(bytes)
        .map_err(|_| HostError::state("ChatGPT returned invalid text."))?
        .replace("\r\n", "\n");
    let mut text = String::new();
    let mut completed = false;
    for event in body.split("\n\n") {
        let data = event
            .lines()
            .filter_map(|line| line.strip_prefix("data:").map(str::trim_start))
            .collect::<Vec<_>>()
            .join("\n");
        if data.is_empty() || data == "[DONE]" {
            continue;
        }
        let value: Value = serde_json::from_str(&data)
            .map_err(|_| HostError::state("ChatGPT returned an invalid stream event."))?;
        match value.get("type").and_then(Value::as_str) {
            Some("response.output_text.delta") => text.push_str(
                value
                    .get("delta")
                    .and_then(Value::as_str)
                    .unwrap_or_default(),
            ),
            Some("response.completed") => completed = true,
            Some("response.failed" | "error") => return Err(api_error(200, data.as_bytes())),
            Some("response.incomplete") => {
                return Err(HostError::state(
                    "ChatGPT response was incomplete. Try again.",
                ));
            }
            _ => {}
        }
    }
    if !completed {
        return Err(HostError::state(
            "ChatGPT connection ended before response.completed.",
        ));
    }
    if text.trim().is_empty() {
        return Err(HostError::state("ChatGPT returned no text."));
    }
    Ok(text.trim().to_string())
}

fn api_error(status: u16, bytes: &[u8]) -> HostError {
    let value: Value = serde_json::from_slice(bytes).unwrap_or(Value::Null);
    let code = value
        .pointer("/error/code")
        .or_else(|| value.pointer("/response/error/code"))
        .or_else(|| value.get("code"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    let message = match code {
        "subscription_sharing_usage_limit_exceeded" => {
            "ChatGPT app usage limit reached. Review ChatGPT Settings > Usage before trying again."
        }
        "subscription_sharing_usage_unavailable" | "subscription_sharing_user_unavailable" => {
            "ChatGPT usage is temporarily unavailable. Try again later."
        }
        "subscription_sharing_user_not_eligible" => {
            "This ChatGPT account or workspace is not eligible for plan usage."
        }
        "subscription_sharing_unsupported_capability" => {
            "ChatGPT does not support this request capability."
        }
        "unsupported_service_tier" | "service_tier_not_available" | "fast_mode_unavailable" => {
            "Fast ChatGPT responses are unavailable for this account or model."
        }
        _ if status == 401 => {
            "ChatGPT authorization was rejected. Reconnect the account in Settings > AI Assist."
        }
        _ if status == 403 => {
            "ChatGPT denied this request under the account's permissions or policy."
        }
        _ if status == 429 => {
            "ChatGPT usage is currently limited. Review ChatGPT Settings > Usage."
        }
        _ if status == 503 => "ChatGPT is temporarily unavailable. Try again later.",
        _ => "ChatGPT request failed.",
    };
    let param = value
        .pointer("/error/param")
        .or_else(|| value.pointer("/response/error/param"))
        .and_then(Value::as_str)
        .filter(|s| s.len() <= 128);
    HostError::conflict(
        "chatgptRequestFailed",
        if status == 200 {
            message.to_string()
        } else {
            format!("{message} (HTTP {status})")
        },
        json!({
            "httpStatus": status,
            "providerCode": if code.len() <= 128 { code } else { "unknown" },
            "providerParam": param,
            "bodyShape": if value.get("detail").is_some() { "detail" } else if value.pointer("/response/error").is_some() { "response.error" } else if value.get("error").is_some() { "error" } else { "other" },
        }),
    )
}
