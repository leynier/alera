//! Realtime socket I/O: connecting, framing, and applying client commands.

use std::collections::{HashMap, HashSet, VecDeque};

use futures_util::SinkExt;
use serde_json::Value;
use tokio::sync::mpsc::UnboundedSender;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        self,
        client::IntoClientRequest,
        http::{header, HeaderValue},
        protocol::{frame::coding::CloseCode, CloseFrame},
        Message,
    },
};

use super::server_command::ServerCommand;
use super::voice_realtime::{
    gemini_activity_end, gemini_activity_start, gemini_audio_message, gemini_speak_frames,
    gemini_ws_url, openai_append_audio, openai_cancel_response, openai_commit_audio,
    openai_speak_message, openai_ws_url, resample_pcm16_16k_to_24k, RealtimeClientMessage,
    VoiceRealtimeConfig, VoiceRealtimeEvent, VoiceRealtimeKind,
};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) async fn connect_provider(
    config: &VoiceRealtimeConfig,
) -> HostResult<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
> {
    let request = match config.kind {
        VoiceRealtimeKind::Gemini => gemini_ws_url(&config.token)?
            .as_str()
            .into_client_request()
            .map_err(|error| HostError::state(format!("Gemini Live request failed: {error}")))?,
        VoiceRealtimeKind::OpenAi => {
            let mut request = openai_ws_url(&config.model)?
                .as_str()
                .into_client_request()
                .map_err(|error| {
                    HostError::state(format!("OpenAI realtime request failed: {error}"))
                })?;
            let auth = HeaderValue::from_str(&format!("Bearer {}", config.token))
                .map_err(|_| HostError::format("OpenAI API key is invalid."))?;
            request.headers_mut().insert(header::AUTHORIZATION, auth);
            request
        }
    };
    let (socket, _) = connect_async(request).await.map_err(|error| match error {
        tungstenite::Error::Http(response) => HostError::state(format!(
            "realtime handshake refused: HTTP {}",
            response.status()
        )),
        error => HostError::state(format!("realtime connect failed: {error}")),
    })?;
    Ok(socket)
}

/// A provider close other than a normal or going-away close carries the reason
/// the socket was refused (for example an invalid API key), so surface it.
pub(super) fn abnormal_close_message(frame: Option<&CloseFrame>) -> Option<String> {
    let frame = frame?;
    if matches!(frame.code, CloseCode::Normal | CloseCode::Away) {
        return None;
    }
    let reason = frame.reason.trim();
    let reason = if reason.is_empty() {
        "no reason given"
    } else {
        reason
    };
    Some(format!(
        "realtime socket closed ({}): {reason}",
        u16::from(frame.code)
    ))
}

#[allow(clippy::too_many_arguments)]
pub(super) async fn apply_client_message<S>(
    write: &mut S,
    config: &VoiceRealtimeConfig,
    command: RealtimeClientMessage,
    response_active: &mut bool,
    speak_busy: &mut bool,
    pending_speak: &mut VecDeque<(String, Option<u64>)>,
    active_response_id: &mut Option<String>,
    active_utterance_id: &mut Option<u64>,
    requested_utterance_id: &mut Option<u64>,
    cancel_pending: &mut bool,
    cancelled_response_ids: &mut HashSet<String>,
    _response_utterances: &mut HashMap<String, u64>,
    gemini_input_busy: &mut bool,
    gemini_input_generation: &mut u64,
    gemini_completing_generations: &mut VecDeque<u64>,
) -> HostResult<()>
where
    S: SinkExt<Message> + Unpin,
    <S as futures_util::Sink<Message>>::Error: std::fmt::Display,
{
    match command {
        RealtimeClientMessage::Speak { text, utterance_id } => {
            if should_queue_gemini_speak(*speak_busy, *gemini_input_busy) {
                pending_speak.push_back((text, utterance_id));
                return Ok(());
            }
            *speak_busy = true;
            *response_active = true;
            *requested_utterance_id = utterance_id;
            if active_utterance_id.is_none() {
                *active_utterance_id = utterance_id;
            }
            send_frames(write, speak_frames(config, &text)).await
        }
        RealtimeClientMessage::ActivityStart => {
            if config.kind == VoiceRealtimeKind::Gemini {
                *gemini_input_busy = true;
                *speak_busy = true;
                *gemini_input_generation = gemini_input_generation.saturating_add(1);
            }
            send_frames(write, other_frames(config, command)).await
        }
        RealtimeClientMessage::ActivityEnd => {
            if config.kind == VoiceRealtimeKind::Gemini {
                *gemini_input_busy = true;
                *speak_busy = true;
                if *gemini_input_generation > 0 {
                    gemini_completing_generations.push_back(*gemini_input_generation);
                }
            }
            send_frames(write, other_frames(config, command)).await
        }
        RealtimeClientMessage::Interrupt => {
            pending_speak.clear();
            *cancel_pending = config.kind == VoiceRealtimeKind::OpenAi
                && active_response_id.is_none()
                && *response_active;
            cancel_active_response(
                write,
                config,
                response_active,
                speak_busy,
                active_response_id,
                cancelled_response_ids,
            )
            .await
        }
        other => send_frames(write, other_frames(config, other)).await,
    }
}

pub(super) async fn cancel_active_response<S>(
    write: &mut S,
    config: &VoiceRealtimeConfig,
    response_active: &mut bool,
    speak_busy: &mut bool,
    active_response_id: &mut Option<String>,
    cancelled_response_ids: &mut HashSet<String>,
) -> HostResult<()>
where
    S: SinkExt<Message> + Unpin,
    <S as futures_util::Sink<Message>>::Error: std::fmt::Display,
{
    if config.kind == VoiceRealtimeKind::OpenAi {
        if let Some(id) = active_response_id.clone() {
            cancelled_response_ids.insert(id.clone());
            *speak_busy = true;
            return send_frames(write, interrupt_frames(config, Some(&id))).await;
        }
        if *response_active {
            *speak_busy = true;
            return Ok(());
        }
        *speak_busy = false;
        return Ok(());
    }
    if !*response_active {
        *speak_busy = false;
        return Ok(());
    }
    *speak_busy = true;
    send_frames(write, interrupt_frames(config, None)).await
}

#[allow(clippy::too_many_arguments)]
pub(super) async fn flush_pending_speak<S>(
    write: &mut S,
    config: &VoiceRealtimeConfig,
    response_active: &mut bool,
    speak_busy: &mut bool,
    pending_speak: &mut VecDeque<(String, Option<u64>)>,
    active_response_id: &mut Option<String>,
    active_utterance_id: &mut Option<u64>,
    requested_utterance_id: &mut Option<u64>,
    cancel_pending: &mut bool,
    cancelled_response_ids: &mut HashSet<String>,
    response_utterances: &mut HashMap<String, u64>,
    gemini_input_busy: &mut bool,
    gemini_input_generation: &mut u64,
    gemini_completing_generations: &mut VecDeque<u64>,
) -> HostResult<()>
where
    S: SinkExt<Message> + Unpin,
    <S as futures_util::Sink<Message>>::Error: std::fmt::Display,
{
    let Some((text, utterance_id)) = pending_speak.pop_front() else {
        return Ok(());
    };
    apply_client_message(
        write,
        config,
        RealtimeClientMessage::Speak { text, utterance_id },
        response_active,
        speak_busy,
        pending_speak,
        active_response_id,
        active_utterance_id,
        requested_utterance_id,
        cancel_pending,
        cancelled_response_ids,
        response_utterances,
        gemini_input_busy,
        gemini_input_generation,
        gemini_completing_generations,
    )
    .await
}

pub(super) fn is_cancelled_response(
    cancelled: &HashSet<String>,
    response_id: Option<&str>,
) -> bool {
    response_id.is_some_and(|id| cancelled.contains(id))
}

pub(super) fn utterance_for_response(
    response_utterances: &HashMap<String, u64>,
    response_id: Option<&str>,
    active_utterance_id: Option<u64>,
) -> Option<u64> {
    if let Some(id) = response_id {
        return response_utterances.get(id).copied();
    }
    active_utterance_id
}

pub(super) fn should_queue_gemini_speak(speak_busy: bool, gemini_input_busy: bool) -> bool {
    speak_busy || gemini_input_busy
}

pub(super) fn finish_unowned_gemini_input(
    speak_busy: &mut bool,
    gemini_input_busy: &mut bool,
    current_generation: u64,
    completing_generations: &mut VecDeque<u64>,
) -> bool {
    let Some(completing_generation) = completing_generations.pop_front() else {
        return false;
    };
    if current_generation != completing_generation {
        return false;
    }
    *gemini_input_busy = false;
    *speak_busy = false;
    true
}

pub(super) fn retire_stale_gemini_input_generation(completing_generations: &mut VecDeque<u64>) {
    let _ = completing_generations.pop_front();
}

#[cfg(test)]
pub(super) fn delayed_input_completion_releases_current(
    current_generation: u64,
    completing_generations: &mut VecDeque<u64>,
) -> bool {
    let mut speak_busy = true;
    let mut gemini_input_busy = true;
    finish_unowned_gemini_input(
        &mut speak_busy,
        &mut gemini_input_busy,
        current_generation,
        completing_generations,
    )
}

pub(super) fn suppress_unowned_gemini_audio(
    gemini_input_busy: bool,
    kind: VoiceRealtimeKind,
    response_utterances: &HashMap<String, u64>,
    response_id: Option<&str>,
    active_utterance_id: Option<u64>,
) -> bool {
    gemini_input_busy
        && kind == VoiceRealtimeKind::Gemini
        && utterance_for_response(response_utterances, response_id, active_utterance_id).is_none()
}

pub(super) fn speak_frames(config: &VoiceRealtimeConfig, text: &str) -> Vec<Value> {
    match config.kind {
        VoiceRealtimeKind::Gemini => gemini_speak_frames(text),
        VoiceRealtimeKind::OpenAi => vec![openai_speak_message(text)],
    }
}

pub(super) fn interrupt_frames(
    config: &VoiceRealtimeConfig,
    response_id: Option<&str>,
) -> Vec<Value> {
    match config.kind {
        VoiceRealtimeKind::Gemini => vec![gemini_activity_start()],
        VoiceRealtimeKind::OpenAi => vec![openai_cancel_response(response_id)],
    }
}

pub(super) fn other_frames(
    config: &VoiceRealtimeConfig,
    command: RealtimeClientMessage,
) -> Vec<Value> {
    match (config.kind, command) {
        (VoiceRealtimeKind::Gemini, RealtimeClientMessage::ActivityStart) => {
            vec![gemini_activity_start()]
        }
        (VoiceRealtimeKind::Gemini, RealtimeClientMessage::Audio { pcm16k }) => {
            vec![gemini_audio_message(&pcm16k)]
        }
        (VoiceRealtimeKind::Gemini, RealtimeClientMessage::ActivityEnd) => {
            vec![gemini_activity_end()]
        }
        (VoiceRealtimeKind::OpenAi, RealtimeClientMessage::Audio { pcm16k }) => {
            vec![openai_append_audio(&resample_pcm16_16k_to_24k(&pcm16k))]
        }
        (VoiceRealtimeKind::OpenAi, RealtimeClientMessage::ActivityEnd) => {
            vec![openai_commit_audio()]
        }
        (_, RealtimeClientMessage::ActivityStart | RealtimeClientMessage::Close) => Vec::new(),
        (_, RealtimeClientMessage::Speak { .. } | RealtimeClientMessage::Interrupt) => Vec::new(),
    }
}

pub(super) async fn send_frames<S>(write: &mut S, frames: Vec<Value>) -> HostResult<()>
where
    S: SinkExt<Message> + Unpin,
    <S as futures_util::Sink<Message>>::Error: std::fmt::Display,
{
    for frame in frames {
        write
            .send(json_message(&frame))
            .await
            .map_err(|error| HostError::state(format!("realtime send failed: {error}")))?;
    }
    Ok(())
}

pub(super) fn is_recoverable_realtime_error(message: &str) -> bool {
    let lowered = message.to_ascii_lowercase();
    lowered.contains("cancellation")
        || lowered.contains("no active response")
        || lowered.contains("response already")
        || lowered.contains("already has an active response")
        || lowered.contains("conversation already has")
        || lowered.contains("in_progress")
}

pub(super) fn json_message(value: &Value) -> Message {
    Message::text(value.to_string())
}

pub(super) fn decode_realtime_json(text: Option<&str>, binary: Option<&[u8]>) -> Value {
    if let Some(text) = text {
        return serde_json::from_str(text).unwrap_or(Value::Null);
    }
    if let Some(bytes) = binary {
        if let Ok(parsed) = serde_json::from_slice::<Value>(bytes) {
            return parsed;
        }
        if let Ok(text) = std::str::from_utf8(bytes) {
            return serde_json::from_str(text).unwrap_or(Value::Null);
        }
    }
    Value::Null
}

pub(super) fn interrupted_speak_drain_keeps_microphone(
    gemini_input_busy: bool,
    speak_busy: &mut bool,
) -> bool {
    if gemini_input_busy {
        *speak_busy = true;
        true
    } else {
        false
    }
}

pub(super) fn report(
    inbox: &UnboundedSender<ServerCommand>,
    generation: u64,
    event: VoiceRealtimeEvent,
) {
    let _ = inbox.send(ServerCommand::VoiceRealtime { generation, event });
}

#[cfg(test)]
#[path = "voice_realtime_socket_tests.rs"]
mod tests;
