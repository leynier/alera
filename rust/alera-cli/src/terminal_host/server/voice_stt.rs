use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderValue, CONTENT_TYPE};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

const GEMINI_STT_MODEL: &str = "gemini-2.5-flash";

pub(super) async fn transcribe_gemini(wav: &[u8], token: &str) -> HostResult<String> {
    let token = token.trim();
    if token.is_empty() {
        return Err(HostError::state(
            "A Gemini API key is required for Gemini transcribe.",
        ));
    }
    if wav.is_empty() {
        return Err(HostError::format("audio recording is empty"));
    }
    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_STT_MODEL}:generateContent"
    );
    let body = gemini_stt_request_body(wav);
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(45))
        .build()
        .map_err(|error| HostError::state(format!("Gemini STT client failed: {error}")))?;
    let mut headers = HeaderMap::new();
    headers.insert(
        "x-goog-api-key",
        HeaderValue::from_str(token)
            .map_err(|_| HostError::format("Gemini API key is invalid."))?,
    );
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    let response = client
        .post(url)
        .headers(headers)
        .json(&body)
        .send()
        .await
        .map_err(|error| HostError::state(format!("Gemini STT request failed: {error}")))?;
    let status = response.status();
    let decoded: Value = response
        .json()
        .await
        .map_err(|error| HostError::state(format!("Gemini STT response failed: {error}")))?;
    if !status.is_success() {
        let message = decoded
            .pointer("/error/message")
            .and_then(Value::as_str)
            .unwrap_or("request failed");
        return Err(HostError::state(format!(
            "Gemini STT returned HTTP {}: {message}",
            status.as_u16()
        )));
    }
    Ok(transcript_from_gemini(&decoded))
}

fn gemini_stt_request_body(wav: &[u8]) -> Value {
    use base64::Engine as _;
    json!({
        "contents": [{
            "parts": [
                { "text": "Transcribe the spoken audio. Return only the transcript text, with no quotes or extra words. If there is no speech, return an empty string." },
                {
                    "inlineData": {
                        "mimeType": "audio/wav",
                        "data": base64::engine::general_purpose::STANDARD.encode(wav),
                    }
                }
            ],
        }],
        "generationConfig": {
            "thinkingConfig": {
                "thinkingBudget": 0,
            }
        }
    })
}

pub(super) fn transcript_from_gemini(decoded: &Value) -> String {
    decoded
        .pointer("/candidates/0/content/parts")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|part| part.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::{gemini_stt_request_body, transcript_from_gemini};
    use serde_json::json;

    #[test]
    fn gemini_stt_disables_thinking() {
        let body = gemini_stt_request_body(b"RIFF");
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            0
        );
    }

    #[test]
    fn reads_the_first_candidate_text() {
        let text = transcript_from_gemini(&json!({
            "candidates": [{
                "content": {
                    "parts": [{ "text": " open the repo " }]
                }
            }]
        }));
        assert_eq!(text, "open the repo");
    }
}
