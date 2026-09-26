//! Parsing Gemini Live and OpenAI Realtime server frames, plus PCM resampling.

use base64::Engine as _;
use serde_json::Value;

use super::voice_realtime::{RealtimeParsed, GEMINI_OUTPUT_SAMPLE_RATE, OPENAI_SAMPLE_RATE};

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

fn decode(encoded: &str) -> Result<Vec<u8>, ()> {
    base64::engine::general_purpose::STANDARD
        .decode(encoded.trim())
        .map_err(|_| ())
}
