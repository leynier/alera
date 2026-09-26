use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderValue, CONTENT_TYPE};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

const GEMINI_TTS_MODEL: &str = "gemini-2.5-flash-preview-tts";
const GEMINI_TTS_DEFAULT_VOICE: &str = "Kore";
const GEMINI_TTS_SAMPLE_RATE: u32 = 24_000;
const OPENAI_TTS_MODEL: &str = "gpt-4o-mini-tts";
const OPENAI_TTS_DEFAULT_VOICE: &str = "alloy";

pub(super) struct SynthesizeRequest<'a> {
    pub(super) text: &'a str,
    pub(super) gemini_token: Option<&'a str>,
    pub(super) openai_token: Option<&'a str>,
    pub(super) tts_provider: &'a str,
    pub(super) tts_voice: Option<&'a str>,
}

pub(super) async fn synthesize(request: SynthesizeRequest<'_>) -> HostResult<Vec<u8>> {
    match request.tts_provider {
        "openAiTts" => synthesize_openai(request).await,
        _ => synthesize_gemini(request).await,
    }
}

async fn synthesize_gemini(request: SynthesizeRequest<'_>) -> HostResult<Vec<u8>> {
    let token = request
        .gemini_token
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::state("A Gemini API key is required for Flash TTS."))?;
    let voice = request
        .tts_voice
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(GEMINI_TTS_DEFAULT_VOICE);
    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_TTS_MODEL}:generateContent"
    );
    let body = json!({
        "contents": [{
            "parts": [{ "text": request.text }],
        }],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": { "voiceName": voice },
                },
            },
        },
    });
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|error| HostError::state(format!("TTS client failed: {error}")))?;
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
        .map_err(|error| HostError::state(format!("Gemini TTS request failed: {error}")))?;
    let status = response.status();
    let decoded: Value = response
        .json()
        .await
        .map_err(|error| HostError::state(format!("Gemini TTS response failed: {error}")))?;
    if !status.is_success() {
        return Err(HostError::state(format!(
            "Gemini TTS returned HTTP {}{}",
            status.as_u16(),
            provider_error_suffix(&decoded)
        )));
    }
    let encoded = decoded
        .pointer("/candidates/0/content/parts/0/inlineData/data")
        .and_then(Value::as_str)
        .ok_or_else(|| HostError::format("Gemini TTS returned no audio."))?;
    let pcm = decode_audio(encoded)?;
    if pcm.is_empty() {
        return Err(HostError::format("Gemini TTS returned no audio."));
    }
    Ok(ensure_wav(pcm, GEMINI_TTS_SAMPLE_RATE))
}

async fn synthesize_openai(request: SynthesizeRequest<'_>) -> HostResult<Vec<u8>> {
    let token = request
        .openai_token
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| HostError::state("An OpenAI API key is required for OpenAI TTS."))?;
    let voice = request
        .tts_voice
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(OPENAI_TTS_DEFAULT_VOICE);
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|error| HostError::state(format!("TTS client failed: {error}")))?;
    let response = client
        .post("https://api.openai.com/v1/audio/speech")
        .bearer_auth(token)
        .json(&json!({
            "model": OPENAI_TTS_MODEL,
            "voice": voice,
            "input": request.text,
            "response_format": "wav",
        }))
        .send()
        .await
        .map_err(|error| HostError::state(format!("OpenAI TTS request failed: {error}")))?;
    let status = response.status();
    let bytes = response
        .bytes()
        .await
        .map_err(|error| HostError::state(format!("OpenAI TTS response failed: {error}")))?;
    if !status.is_success() {
        let suffix = serde_json::from_slice::<Value>(&bytes)
            .ok()
            .map(|decoded| provider_error_suffix(&decoded))
            .unwrap_or_default();
        return Err(HostError::state(format!(
            "OpenAI TTS returned HTTP {}{suffix}",
            status.as_u16()
        )));
    }
    Ok(bytes.to_vec())
}

fn decode_audio(encoded: &str) -> HostResult<Vec<u8>> {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD
        .decode(encoded.trim())
        .map_err(|_| HostError::format("Gemini TTS returned invalid audio."))
}

fn ensure_wav(audio: Vec<u8>, sample_rate: u32) -> Vec<u8> {
    if audio.len() >= 12 && audio.starts_with(b"RIFF") && audio[8..12] == *b"WAVE" {
        return audio;
    }
    pcm16_to_wav(&audio, sample_rate)
}

fn pcm16_to_wav(pcm: &[u8], sample_rate: u32) -> Vec<u8> {
    let mut header = [0_u8; 44];
    header[0..4].copy_from_slice(b"RIFF");
    let chunk_size = 36 + pcm.len() as u32;
    header[4..8].copy_from_slice(&chunk_size.to_le_bytes());
    header[8..12].copy_from_slice(b"WAVE");
    header[12..16].copy_from_slice(b"fmt ");
    header[16..20].copy_from_slice(&16_u32.to_le_bytes());
    header[20..22].copy_from_slice(&1_u16.to_le_bytes());
    header[22..24].copy_from_slice(&1_u16.to_le_bytes());
    header[24..28].copy_from_slice(&sample_rate.to_le_bytes());
    let byte_rate = sample_rate * 2;
    header[28..32].copy_from_slice(&byte_rate.to_le_bytes());
    header[32..34].copy_from_slice(&2_u16.to_le_bytes());
    header[34..36].copy_from_slice(&16_u16.to_le_bytes());
    header[36..40].copy_from_slice(b"data");
    header[40..44].copy_from_slice(&(pcm.len() as u32).to_le_bytes());
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(&header);
    wav.extend_from_slice(pcm);
    wav
}

fn provider_error_suffix(decoded: &Value) -> String {
    decoded
        .pointer("/error/message")
        .and_then(Value::as_str)
        .or_else(|| decoded.get("message").and_then(Value::as_str))
        .map(str::trim)
        .filter(|message| !message.is_empty())
        .map(|message| format!(": {message}"))
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::decode_audio;

    #[test]
    fn decodes_standard_base64_pcm() {
        let audio = decode_audio("AAAA").unwrap();
        assert_eq!(audio, vec![0, 0, 0]);
    }

    #[test]
    fn wraps_raw_pcm_as_mono_24k_wav() {
        let wav = super::ensure_wav(vec![0, 0, 1, 0], 24_000);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 24_000);
        assert_eq!(u16::from_le_bytes(wav[22..24].try_into().unwrap()), 1);
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 4);
        assert_eq!(&wav[44..], &[0, 0, 1, 0]);
    }

    #[test]
    fn leaves_existing_wav_bytes_alone() {
        let wav = super::pcm16_to_wav(&[9, 9], 16_000);
        assert_eq!(super::ensure_wav(wav.clone(), 24_000), wav);
    }
}
