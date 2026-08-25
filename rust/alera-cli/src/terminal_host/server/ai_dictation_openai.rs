use std::path::Path;
use std::time::Duration;

use reqwest::multipart::{Form, Part};
use serde_json::{json, Value};
use url::Url;

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) struct OpenAiDictationRequest<'a> {
    pub(super) audio_path: &'a Path,
    pub(super) base_url: &'a str,
    pub(super) model: &'a str,
    pub(super) token: Option<&'a str>,
    pub(super) language: Option<&'a str>,
    pub(super) prompt: Option<&'a str>,
    pub(super) timeout: Duration,
}

pub(super) async fn transcribe(request: OpenAiDictationRequest<'_>) -> HostResult<Value> {
    let endpoint = transcription_endpoint(request.base_url, request.token.is_some())?;
    let audio_path = request.audio_path.to_path_buf();
    let audio = tokio::task::spawn_blocking(move || std::fs::read(audio_path))
        .await
        .map_err(|error| HostError::state(format!("audio read task failed: {error}")))?
        .map_err(|error| HostError::state(format!("audio could not be read: {error}")))?;
    if audio.is_empty() {
        return Err(HostError::format("audio recording is empty"));
    }
    if audio.len() > 25 * 1024 * 1024 {
        return Err(HostError::format("audio recording is too large"));
    }
    let mut form = Form::new()
        .text("model", request.model.to_string())
        .text("response_format", "json")
        .part(
            "file",
            Part::bytes(audio)
                .file_name("dictation.wav")
                .mime_str("audio/wav")
                .map_err(|error| HostError::state(error.to_string()))?,
        );
    if let Some(language) = normalized(request.language) {
        form = form.text("language", language.to_string());
    }
    if let Some(prompt) = normalized(request.prompt) {
        form = form.text("prompt", prompt.to_string());
    }
    let client = reqwest::Client::builder()
        .timeout(request.timeout)
        .build()
        .map_err(|error| HostError::state(format!("speech provider client failed: {error}")))?;
    let mut outbound = client.post(endpoint).multipart(form);
    if let Some(token) = normalized(request.token) {
        outbound = outbound.bearer_auth(token);
    }
    let response = outbound
        .send()
        .await
        .map_err(|error| HostError::state(format!("speech provider request failed: {error}")))?;
    let status = response.status();
    let body = response
        .bytes()
        .await
        .map_err(|error| HostError::state(format!("speech provider response failed: {error}")))?;
    if !status.is_success() {
        return Err(HostError::state(format!(
            "speech provider returned HTTP {}{}",
            status.as_u16(),
            provider_error_suffix(&body)
        )));
    }
    let decoded: Value = serde_json::from_slice(&body)
        .map_err(|_| HostError::format("speech provider returned invalid JSON"))?;
    let text = decoded
        .get("text")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::format("speech provider returned no transcription"))?;
    Ok(json!({
        "text": text,
        "providerId": "openai-compatible",
    }))
}

pub(super) fn transcription_endpoint(base_url: &str, sends_token: bool) -> HostResult<Url> {
    let mut url = Url::parse(base_url.trim())
        .map_err(|_| HostError::format("speech provider base URL is invalid"))?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(HostError::format(
            "speech provider base URL must use HTTP or HTTPS",
        ));
    }
    if sends_token && url.scheme() != "https" && !url.host_str().is_some_and(is_loopback_host) {
        return Err(HostError::format(
            "a token can only be sent over HTTPS or to a loopback address",
        ));
    }
    url.set_query(None);
    url.set_fragment(None);
    let path = url.path().trim_end_matches('/');
    let endpoint_path = if path.ends_with("/audio/transcriptions") {
        path.to_string()
    } else if path.ends_with("/v1") {
        format!("{path}/audio/transcriptions")
    } else if path.is_empty() || path == "/" {
        "/v1/audio/transcriptions".to_string()
    } else {
        format!("{path}/v1/audio/transcriptions")
    };
    url.set_path(&endpoint_path);
    Ok(url)
}

fn normalized(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

fn is_loopback_host(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback())
}

fn provider_error_suffix(body: &[u8]) -> String {
    let Ok(decoded) = serde_json::from_slice::<Value>(body) else {
        return String::new();
    };
    decoded
        .pointer("/error/message")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .map(|message| format!(": {message}"))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::transcription_endpoint;

    #[test]
    fn builds_openai_transcription_endpoints() {
        assert_eq!(
            transcription_endpoint("https://api.openai.com", true)
                .unwrap()
                .as_str(),
            "https://api.openai.com/v1/audio/transcriptions"
        );
        assert_eq!(
            transcription_endpoint("http://localhost:11434/openai/v1/", true)
                .unwrap()
                .as_str(),
            "http://localhost:11434/openai/v1/audio/transcriptions"
        );
        assert_eq!(
            transcription_endpoint(
                "https://example.test/custom/audio/transcriptions?ignored=true",
                false,
            )
            .unwrap()
            .as_str(),
            "https://example.test/custom/audio/transcriptions"
        );
    }

    #[test]
    fn rejects_tokens_over_cleartext_non_loopback_urls() {
        let error = transcription_endpoint("http://example.test/v1", true).unwrap_err();
        assert!(error.to_string().contains("HTTPS"));
        assert!(transcription_endpoint("http://example.test/v1", false).is_ok());
    }
}
