use super::{chatgpt_oauth, chatgpt_session};
use crate::terminal_host::host_error::{HostError, HostResult};
use futures_util::StreamExt;
use serde_json::{json, Value};
use std::time::Duration;
use tokio::sync::oneshot;

const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

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
            Some(json!({"id": id, "label": label}))
        })
        .collect();
    if models.is_empty() {
        return Err(HostError::state(
            "No models are available for this ChatGPT account.",
        ));
    }
    Ok(json!({"defaultModelId": models[0]["id"], "models": models}))
}

pub(super) async fn complete(
    prompt: &str,
    model: &str,
    timeout: Duration,
    cancel: oneshot::Receiver<()>,
) -> HostResult<String> {
    tokio::select! {
        _ = cancel => Err(HostError::state("Generation canceled.")),
        result = tokio::time::timeout(timeout, complete_request(prompt, model)) =>
            result.unwrap_or_else(|_| Err(HostError::state("ChatGPT generation timed out."))),
    }
}

pub(super) fn request_body(prompt: &str, model: &str) -> Value {
    json!({"model": model, "input": [{"role": "user", "content": prompt}], "store": false, "stream": true})
}

async fn complete_request(prompt: &str, selected: &str) -> HostResult<String> {
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
            let model = if selected.is_empty() { available["defaultModelId"].as_str().unwrap() } else { selected };
            if !available["models"].as_array().unwrap().iter().any(|item| item["id"] == model) {
                return Err(HostError::state("This model is unavailable for the active ChatGPT account. Refresh models in Settings > AI Assist."));
            }
            let client = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).build()
                .map_err(|_| HostError::state("ChatGPT connection failed."))?;
            let response = client.post(format!("{}/responses", chatgpt_oauth::RESOURCE))
                .bearer_auth(token).header("Accept", "text/event-stream")
                .json(&request_body(prompt, model)).send().await
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
                ))
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
