use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) use super::voice_realtime_parse::{
    looks_like_home_cancel, parse_gemini_message, parse_openai_message, resample_pcm16_16k_to_24k,
};

pub(super) const GEMINI_LIVE_MODEL: &str = "gemini-3.1-flash-live-preview";
pub(super) const OPENAI_REALTIME_MINI_MODEL: &str = "gpt-realtime-mini";
pub(super) const OPENAI_REALTIME_MODEL: &str = "gpt-realtime-2.1";
pub(super) const OPENAI_LIVE_MODEL: &str = "gpt-realtime-1.5";
pub(super) const OPENAI_TRANSCRIBE_MODEL: &str = "gpt-4o-mini-transcribe";
pub(super) const GEMINI_LIVE_DEFAULT_VOICE: &str = "Kore";
pub(super) const OPENAI_LIVE_DEFAULT_VOICE: &str = "alloy";
pub(super) const GEMINI_OUTPUT_SAMPLE_RATE: u32 = 24_000;
pub(super) const OPENAI_SAMPLE_RATE: u32 = 24_000;

pub(super) const SPEECH_IO_INSTRUCTIONS: &str =
    "You are Alera's speech I/O layer, not an assistant.\n\
Never answer questions. Never reason. Never call tools. Never add extra words.\n\
When the user speaks, stay silent. The host transcribes their words.\n\
When the host asks you to speak text, say that text verbatim in a natural voice and then stop.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VoiceRealtimeKind {
    Gemini,
    OpenAi,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct VoiceRealtimeConfig {
    pub kind: VoiceRealtimeKind,
    pub model: String,
    pub voice: String,
    pub token: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum RealtimeParsed {
    SetupComplete,
    InputTranscript {
        text: String,
        is_final: bool,
        item_id: Option<String>,
    },
    Audio {
        pcm: Vec<u8>,
        sample_rate: u32,
        response_id: Option<String>,
    },
    AudioDone {
        response_id: Option<String>,
    },
    ResponseCreated {
        id: Option<String>,
    },
    ResponseFinished {
        response_id: Option<String>,
    },
    Interrupted {
        response_id: Option<String>,
    },
    TurnComplete,
    InputCommitted {
        item_id: String,
    },
    InputTranscriptionFailed {
        item_id: Option<String>,
        message: String,
    },
    Error {
        message: String,
    },
}

#[derive(Debug)]
pub(super) enum RealtimeClientMessage {
    Audio {
        pcm16k: Vec<u8>,
    },
    ActivityStart,
    ActivityEnd,
    Speak {
        text: String,
        utterance_id: Option<u64>,
    },
    Interrupt,
    Close,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum VoiceRealtimeEvent {
    Ready,
    UserTranscript {
        text: String,
        is_final: bool,
        item_id: Option<String>,
    },
    InputCommitted {
        item_id: String,
    },
    Audio {
        pcm: Vec<u8>,
        sample_rate: u32,
        utterance_id: Option<u64>,
    },
    AudioDone {
        utterance_id: Option<u64>,
    },
    Interrupted {
        utterance_id: Option<u64>,
    },
    Error {
        message: String,
    },
    Closed {
        error: Option<String>,
    },
}

pub(super) fn config_for_provider(
    provider: &str,
    gemini_token: Option<&str>,
    openai_token: Option<&str>,
    tts_voice: Option<&str>,
) -> HostResult<VoiceRealtimeConfig> {
    match provider {
        "gptRealtimeMini" | "gptRealtime" | "gptLive1" => {
            let token = require_token(
                openai_token,
                "An OpenAI API key is required for realtime speech.",
            )?;
            let (kind_model, default_voice) = match provider {
                "gptRealtimeMini" => (OPENAI_REALTIME_MINI_MODEL, OPENAI_LIVE_DEFAULT_VOICE),
                "gptLive1" => (OPENAI_LIVE_MODEL, OPENAI_LIVE_DEFAULT_VOICE),
                _ => (OPENAI_REALTIME_MODEL, OPENAI_LIVE_DEFAULT_VOICE),
            };
            Ok(VoiceRealtimeConfig {
                kind: VoiceRealtimeKind::OpenAi,
                model: kind_model.to_string(),
                voice: voice_or(tts_voice, default_voice),
                token,
            })
        }
        _ => {
            let token = require_token(
                gemini_token,
                "A Gemini API key is required for Live speech.",
            )?;
            Ok(VoiceRealtimeConfig {
                kind: VoiceRealtimeKind::Gemini,
                model: GEMINI_LIVE_MODEL.to_string(),
                voice: voice_or(tts_voice, GEMINI_LIVE_DEFAULT_VOICE),
                token,
            })
        }
    }
}

pub(super) fn gemini_ws_url(token: &str) -> HostResult<url::Url> {
    let mut url = url::Url::parse(
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
    )
    .map_err(|error| HostError::state(format!("Gemini Live URL is invalid: {error}")))?;
    url.query_pairs_mut().append_pair("key", token);
    Ok(url)
}

pub(super) fn openai_ws_url(model: &str) -> HostResult<url::Url> {
    let mut url = url::Url::parse("wss://api.openai.com/v1/realtime")
        .map_err(|error| HostError::state(format!("OpenAI realtime URL is invalid: {error}")))?;
    url.query_pairs_mut().append_pair("model", model);
    Ok(url)
}

pub(super) fn gemini_setup_message(config: &VoiceRealtimeConfig) -> Value {
    json!({
        "setup": {
            "model": format!("models/{}", config.model),
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {
                    "voiceConfig": {
                        "prebuiltVoiceConfig": { "voiceName": config.voice },
                    },
                },
                "thinkingConfig": {
                    "thinkingLevel": "minimal",
                    "includeThoughts": false,
                },
            },
            "systemInstruction": {
                "parts": [{ "text": SPEECH_IO_INSTRUCTIONS }],
            },
            "inputAudioTranscription": {},
            "outputAudioTranscription": {},
            "realtimeInputConfig": {
                "automaticActivityDetection": { "disabled": true },
                "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
            },
            "tools": [],
        }
    })
}

pub(super) fn openai_session_update(config: &VoiceRealtimeConfig) -> Value {
    json!({
        "type": "session.update",
        "session": {
            "type": "realtime",
            "model": config.model,
            "instructions": SPEECH_IO_INSTRUCTIONS,
            "output_modalities": ["audio"],
            "audio": {
                "input": {
                    "format": { "type": "audio/pcm", "rate": OPENAI_SAMPLE_RATE },
                    "transcription": { "model": OPENAI_TRANSCRIBE_MODEL },
                    "turn_detection": Value::Null,
                },
                "output": {
                    "format": { "type": "audio/pcm" },
                    "voice": config.voice,
                },
            },
        }
    })
}

pub(super) fn gemini_audio_message(pcm: &[u8]) -> Value {
    json!({
        "realtimeInput": {
            "audio": {
                "data": encode(pcm),
                "mimeType": "audio/pcm;rate=16000",
            }
        }
    })
}

pub(super) fn gemini_activity_start() -> Value {
    json!({ "realtimeInput": { "activityStart": {} } })
}

pub(super) fn gemini_activity_end() -> Value {
    json!({ "realtimeInput": { "activityEnd": {} } })
}

pub(super) fn gemini_speak_message(text: &str) -> Value {
    json!({
        "realtimeInput": {
            "text": format!(
                "Speak exactly this text and nothing else. Do not answer it. Do not add words.\n\n{text}"
            )
        }
    })
}

pub(super) fn gemini_speak_frames(text: &str) -> Vec<Value> {
    vec![
        gemini_activity_start(),
        gemini_speak_message(text),
        gemini_activity_end(),
    ]
}

pub(super) fn openai_append_audio(pcm24k: &[u8]) -> Value {
    json!({
        "type": "input_audio_buffer.append",
        "audio": encode(pcm24k),
    })
}

pub(super) fn openai_commit_audio() -> Value {
    json!({ "type": "input_audio_buffer.commit" })
}

pub(super) fn openai_cancel_response(response_id: Option<&str>) -> Value {
    match response_id {
        Some(id) if !id.is_empty() => json!({ "type": "response.cancel", "response_id": id }),
        _ => json!({ "type": "response.cancel" }),
    }
}

pub(super) fn openai_speak_message(text: &str) -> Value {
    json!({
        "type": "response.create",
        "response": {
            "conversation": "none",
            "output_modalities": ["audio"],
            "instructions": format!(
                "Say exactly the following, word for word, in the same language. Do not add anything.\n\n{text}"
            ),
        }
    })
}

fn encode(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn require_token(token: Option<&str>, message: &str) -> HostResult<String> {
    token
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| HostError::state(message.to_string()))
}

fn voice_or(value: Option<&str>, fallback: &str) -> String {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(fallback)
        .to_string()
}

#[cfg(test)]
#[path = "voice_realtime_tests.rs"]
mod tests;
