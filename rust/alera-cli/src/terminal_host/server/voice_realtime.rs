use base64::Engine as _;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

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
    Closed,
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

pub(super) fn parse_gemini_message(value: &Value) -> Vec<RealtimeParsed> {
    let mut events = Vec::new();
    if value.get("setupComplete").is_some() {
        events.push(RealtimeParsed::SetupComplete);
    }
    if let Some(message) = value
        .pointer("/error/message")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|message| !message.is_empty())
    {
        events.push(RealtimeParsed::Error {
            message: message.to_string(),
        });
    }
    let Some(content) = value.get("serverContent") else {
        return events;
    };
    if content.get("interrupted").and_then(Value::as_bool) == Some(true) {
        events.push(RealtimeParsed::Interrupted { response_id: None });
    }
    let transcript_text = content
        .pointer("/inputTranscription/text")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string);
    let finished = content
        .pointer("/inputTranscription/finished")
        .and_then(Value::as_bool)
        == Some(true);
    if let Some(text) = transcript_text {
        events.push(RealtimeParsed::InputTranscript {
            text,
            is_final: finished,
            item_id: None,
        });
    } else if finished {
        events.push(RealtimeParsed::InputTranscript {
            text: String::new(),
            is_final: true,
            item_id: None,
        });
    }
    if let Some(parts) = content
        .pointer("/modelTurn/parts")
        .and_then(Value::as_array)
    {
        for part in parts {
            if let Some(data) = part.pointer("/inlineData/data").and_then(Value::as_str) {
                let sample_rate = sample_rate_from_mime(
                    part.pointer("/inlineData/mimeType").and_then(Value::as_str),
                    GEMINI_OUTPUT_SAMPLE_RATE,
                );
                if let Ok(pcm) = decode(data) {
                    events.push(RealtimeParsed::Audio {
                        pcm,
                        sample_rate,
                        response_id: None,
                    });
                }
            }
        }
    }
    if content.get("generationComplete").and_then(Value::as_bool) == Some(true) {
        events.push(RealtimeParsed::AudioDone { response_id: None });
    }
    if content.get("turnComplete").and_then(Value::as_bool) == Some(true) {
        events.push(RealtimeParsed::TurnComplete);
        events.push(RealtimeParsed::ResponseFinished { response_id: None });
    }
    events
}

pub(super) fn parse_openai_message(value: &Value) -> Vec<RealtimeParsed> {
    let mut events = Vec::new();
    let kind = value.get("type").and_then(Value::as_str).unwrap_or("");
    match kind {
        "session.created" | "session.updated" => events.push(RealtimeParsed::SetupComplete),
        "response.created" => {
            let id = value
                .pointer("/response/id")
                .and_then(Value::as_str)
                .or_else(|| value.get("response_id").and_then(Value::as_str))
                .map(str::to_string);
            events.push(RealtimeParsed::ResponseCreated { id });
        }
        "conversation.item.input_audio_transcription.completed"
        | "conversation.item.input_audio_transcription.done" => {
            events.push(RealtimeParsed::InputTranscript {
                text: openai_transcript(value).unwrap_or_default(),
                is_final: true,
                item_id: openai_item_id(value),
            });
        }
        "conversation.item.input_audio_transcription.failed" => {
            let message = value
                .pointer("/error/message")
                .and_then(Value::as_str)
                .or_else(|| value.get("message").and_then(Value::as_str))
                .unwrap_or("OpenAI input transcription failed");
            events.push(RealtimeParsed::InputTranscriptionFailed {
                item_id: openai_item_id(value),
                message: message.to_string(),
            });
        }
        "conversation.item.input_audio_transcription.delta" => {}
        "response.output_audio.delta" | "response.audio.delta" => {
            if let Some(delta) = value.get("delta").and_then(Value::as_str) {
                if let Ok(pcm) = decode(delta) {
                    events.push(RealtimeParsed::Audio {
                        pcm,
                        sample_rate: OPENAI_SAMPLE_RATE,
                        response_id: openai_event_response_id(value),
                    });
                }
            }
        }
        "response.output_audio.done" | "response.audio.done" => {
            events.push(RealtimeParsed::AudioDone {
                response_id: openai_event_response_id(value),
            });
        }
        "response.done" | "response.completed" => {
            let response_id = openai_event_response_id(value);
            if openai_response_cancelled(value) {
                events.push(RealtimeParsed::Interrupted { response_id });
            } else {
                events.push(RealtimeParsed::TurnComplete);
                events.push(RealtimeParsed::ResponseFinished { response_id });
            }
        }
        "response.cancelled" => {
            events.push(RealtimeParsed::Interrupted {
                response_id: openai_event_response_id(value),
            });
        }
        "input_audio_buffer.committed" => {
            if let Some(item_id) = openai_item_id(value) {
                events.push(RealtimeParsed::InputCommitted { item_id });
            }
        }
        "input_audio_buffer.speech_started" => {
            events.push(RealtimeParsed::Interrupted { response_id: None });
        }
        "error" => {
            let message = value
                .pointer("/error/message")
                .and_then(Value::as_str)
                .or_else(|| value.get("message").and_then(Value::as_str))
                .unwrap_or("OpenAI realtime error");
            events.push(RealtimeParsed::Error {
                message: message.to_string(),
            });
        }
        _ => {}
    }
    events
}

pub(super) fn resample_pcm16_16k_to_24k(input: &[u8]) -> Vec<u8> {
    let sample_count = input.len() / 2;
    if sample_count == 0 {
        return Vec::new();
    }
    let out_count = sample_count * 3 / 2;
    let mut output = Vec::with_capacity(out_count * 2);
    for index in 0..out_count {
        let src = index as f32 * 16.0 / 24.0;
        let left = src.floor() as usize;
        let frac = src - left as f32;
        let s0 = sample_at(input, left.min(sample_count - 1));
        let s1 = sample_at(input, (left + 1).min(sample_count - 1));
        let mixed = s0 + (s1 - s0) * frac;
        let value = mixed.round().clamp(i16::MIN as f32, i16::MAX as f32) as i16;
        output.extend_from_slice(&value.to_le_bytes());
    }
    output
}

pub(super) fn looks_like_home_cancel(text: &str) -> bool {
    matches!(
        normalize_home_cancel(text).as_str(),
        "para"
            | "stop"
            | "cancel"
            | "cancela"
            | "cancelar"
            | "cállate"
            | "callate"
            | "silencio"
            | "basta"
    )
}

fn normalize_home_cancel(text: &str) -> String {
    let mut normalized = text.trim().to_string();
    const MARKS: &[char] = &[
        '¡', '!', '¿', '?', '.', ',', ';', ':', '…', '"', '\'', '“', '”', '(', ')', '[', ']', '{',
        '}',
    ];
    loop {
        let next = normalized
            .trim_matches(|ch: char| ch.is_ascii_punctuation() || MARKS.contains(&ch))
            .trim()
            .to_string();
        if next == normalized {
            break;
        }
        normalized = next;
    }
    normalized.to_lowercase()
}

fn openai_event_response_id(value: &Value) -> Option<String> {
    value
        .pointer("/response/id")
        .and_then(Value::as_str)
        .or_else(|| value.get("response_id").and_then(Value::as_str))
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn openai_response_cancelled(value: &Value) -> bool {
    value
        .pointer("/response/status")
        .and_then(Value::as_str)
        .is_some_and(|status| {
            status.eq_ignore_ascii_case("cancelled") || status.eq_ignore_ascii_case("failed")
        })
}

fn openai_item_id(value: &Value) -> Option<String> {
    value
        .get("item_id")
        .and_then(Value::as_str)
        .or_else(|| value.pointer("/item/id").and_then(Value::as_str))
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .map(ToOwned::to_owned)
}

fn openai_transcript(value: &Value) -> Option<String> {
    value
        .get("transcript")
        .and_then(Value::as_str)
        .or_else(|| {
            value
                .pointer("/item/content/0/transcript")
                .and_then(Value::as_str)
        })
        .map(str::trim)
        .map(ToOwned::to_owned)
}

fn sample_rate_from_mime(mime: Option<&str>, fallback: u32) -> u32 {
    mime.and_then(|value| {
        value.split("rate=").nth(1).and_then(|tail| {
            tail.chars()
                .take_while(|ch| ch.is_ascii_digit())
                .collect::<String>()
                .parse()
                .ok()
        })
    })
    .unwrap_or(fallback)
}

fn sample_at(input: &[u8], index: usize) -> f32 {
    let offset = index * 2;
    if offset + 1 >= input.len() {
        return 0.0;
    }
    i16::from_le_bytes([input[offset], input[offset + 1]]) as f32
}

fn encode(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn decode(encoded: &str) -> Result<Vec<u8>, ()> {
    base64::engine::general_purpose::STANDARD
        .decode(encoded.trim())
        .map_err(|_| ())
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
mod tests {
    use super::{
        config_for_provider, gemini_setup_message, gemini_speak_message, looks_like_home_cancel,
        openai_session_update, parse_gemini_message, parse_openai_message,
        resample_pcm16_16k_to_24k, RealtimeParsed, GEMINI_LIVE_MODEL, OPENAI_REALTIME_MINI_MODEL,
        SPEECH_IO_INSTRUCTIONS,
    };
    use serde_json::json;

    #[test]
    fn gemini_is_the_default_realtime_provider() {
        let config = config_for_provider("geminiFlashLive", Some("gk"), None, None).unwrap();
        assert_eq!(config.model, GEMINI_LIVE_MODEL);
        let setup = gemini_setup_message(&config);
        assert_eq!(
            setup["setup"]["realtimeInputConfig"]["automaticActivityDetection"]["disabled"],
            true
        );
        assert!(setup["setup"].get("proactivity").is_none());
        assert!(setup["setup"]["generationConfig"]["thinkingConfig"]
            .get("thinkingBudget")
            .is_none());
        assert_eq!(
            setup["setup"]["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "minimal"
        );
        assert_eq!(
            setup["setup"]["generationConfig"]["thinkingConfig"]["includeThoughts"],
            false
        );
        assert!(setup["setup"]["systemInstruction"]["parts"][0]["text"]
            .as_str()
            .unwrap()
            .contains("not an assistant"));
    }

    #[test]
    fn openai_mini_maps_to_gpt_realtime_mini() {
        let config =
            config_for_provider("gptRealtimeMini", None, Some("sk"), Some("marin")).unwrap();
        assert_eq!(config.model, OPENAI_REALTIME_MINI_MODEL);
        let update = openai_session_update(&config);
        assert_eq!(
            update["session"]["audio"]["input"]["turn_detection"],
            json!(null)
        );
        assert_eq!(update["session"]["audio"]["output"]["voice"], "marin");
        assert!(update["session"]["instructions"]
            .as_str()
            .unwrap()
            .contains("stay silent"));
    }

    #[test]
    fn gemini_parses_transcription_and_pcm() {
        let events = parse_gemini_message(&json!({
            "serverContent": {
                "inputTranscription": { "text": "open the repo" },
                "modelTurn": {
                    "parts": [{
                        "inlineData": {
                            "mimeType": "audio/pcm;rate=24000",
                            "data": "AAAA",
                        }
                    }]
                },
                "turnComplete": true,
            }
        }));
        assert!(events.iter().any(|event| matches!(
            event,
            RealtimeParsed::InputTranscript { text, is_final: false, .. } if text == "open the repo"
        )));
        assert!(events.iter().any(|event| matches!(
            event,
            RealtimeParsed::Audio {
                sample_rate: 24_000,
                ..
            }
        )));
        assert!(events
            .iter()
            .any(|event| matches!(event, RealtimeParsed::TurnComplete)));
        let later = parse_gemini_message(&json!({
            "serverContent": {
                "inputTranscription": { "text": "repository" },
                "turnComplete": true,
            }
        }));
        assert!(later.iter().any(|event| matches!(
            event,
            RealtimeParsed::InputTranscript { text, is_final: false, .. } if text == "repository"
        )));

        let finished = parse_gemini_message(&json!({
            "serverContent": {
                "inputTranscription": { "text": "open the repository", "finished": true },
            }
        }));
        assert!(finished.iter().any(|event| matches!(
            event,
            RealtimeParsed::InputTranscript { text, is_final: true, .. } if text == "open the repository"
        )));
        let textless = parse_gemini_message(&json!({
            "serverContent": {
                "inputTranscription": { "finished": true },
            }
        }));
        assert!(textless.iter().any(|event| matches!(
            event,
            RealtimeParsed::InputTranscript { text, is_final: true, .. } if text.is_empty()
        )));
    }

    #[test]
    fn openai_parses_final_transcript_and_audio_delta() {
        let transcript = parse_openai_message(&json!({
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item_a",
            "transcript": "stop",
        }));
        assert_eq!(
            transcript,
            vec![RealtimeParsed::InputTranscript {
                text: "stop".into(),
                is_final: true,
                item_id: Some("item_a".into()),
            }]
        );
        let delta = parse_openai_message(&json!({
            "type": "conversation.item.input_audio_transcription.delta",
            "delta": "delete",
        }));
        assert!(delta.is_empty());
        let empty = parse_openai_message(&json!({
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "item_empty",
            "transcript": "",
        }));
        assert_eq!(
            empty,
            vec![RealtimeParsed::InputTranscript {
                text: String::new(),
                is_final: true,
                item_id: Some("item_empty".into()),
            }]
        );
        let failed = parse_openai_message(&json!({
            "type": "conversation.item.input_audio_transcription.failed",
            "item_id": "item_a",
            "error": { "code": "audio_unintelligible", "message": "unintelligible" },
        }));
        assert_eq!(
            failed,
            vec![RealtimeParsed::InputTranscriptionFailed {
                item_id: Some("item_a".into()),
                message: "unintelligible".into(),
            }]
        );
        let committed = parse_openai_message(&json!({
            "type": "input_audio_buffer.committed",
            "item_id": "item_a",
        }));
        assert_eq!(
            committed,
            vec![RealtimeParsed::InputCommitted {
                item_id: "item_a".into(),
            }]
        );
        let audio = parse_openai_message(&json!({
            "type": "response.output_audio.delta",
            "delta": "AAAA",
        }));
        assert!(matches!(
            audio.as_slice(),
            [RealtimeParsed::Audio {
                sample_rate: 24_000,
                ..
            }]
        ));
    }

    #[test]
    fn cancel_words_match_the_client_list() {
        assert!(looks_like_home_cancel("Para"));
        assert!(looks_like_home_cancel("  cállate "));
        assert!(looks_like_home_cancel("Stop."));
        assert!(looks_like_home_cancel("¡Para!"));
        assert!(looks_like_home_cancel("(Stop)"));
        assert!(!looks_like_home_cancel("please stop the build"));
    }

    #[test]
    fn resamples_two_16k_samples_into_three_24k_samples() {
        let pcm = resample_pcm16_16k_to_24k(&[0, 0, 0, 64]);
        assert_eq!(pcm.len(), 6);
    }

    #[test]
    fn instructions_forbid_tools() {
        assert!(SPEECH_IO_INSTRUCTIONS.contains("Never call tools"));
    }

    #[test]
    fn gemini_speak_uses_realtime_input_text() {
        let message = gemini_speak_message("On it.");
        assert!(message.get("clientContent").is_none());
        assert_eq!(
            message["realtimeInput"]["text"]
                .as_str()
                .unwrap()
                .contains("On it."),
            true
        );
        let frames = super::gemini_speak_frames("On it.");
        assert_eq!(frames.len(), 3);
        assert!(frames[0].pointer("/realtimeInput/activityStart").is_some());
        assert!(frames[2].pointer("/realtimeInput/activityEnd").is_some());
    }
}
