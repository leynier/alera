use std::collections::{HashMap, HashSet, VecDeque};

use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        client::IntoClientRequest,
        http::{header, HeaderValue},
        Message,
    },
};

use super::server_command::ServerCommand;
use super::voice_realtime::{
    gemini_activity_end, gemini_activity_start, gemini_audio_message, gemini_setup_message,
    gemini_speak_frames, gemini_ws_url, openai_append_audio, openai_cancel_response,
    openai_commit_audio, openai_session_update, openai_speak_message, openai_ws_url,
    parse_gemini_message, parse_openai_message, resample_pcm16_16k_to_24k, RealtimeClientMessage,
    RealtimeParsed, VoiceRealtimeConfig, VoiceRealtimeEvent, VoiceRealtimeKind,
};
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) struct VoiceRealtimeHandle {
    pub generation: u64,
    pub tx: UnboundedSender<RealtimeClientMessage>,
    pub task: tokio::task::JoinHandle<()>,
}

impl VoiceRealtimeHandle {
    pub(super) fn send(&self, message: RealtimeClientMessage) {
        let _ = self.tx.send(message);
    }

    pub(super) fn abort(self) {
        let _ = self.tx.send(RealtimeClientMessage::Close);
        self.task.abort();
    }
}

pub(super) fn spawn_voice_realtime(
    config: VoiceRealtimeConfig,
    generation: u64,
    inbox: UnboundedSender<ServerCommand>,
) -> VoiceRealtimeHandle {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(async move {
        let result = run_voice_realtime(config, generation, rx, inbox.clone()).await;
        if let Err(error) = result {
            let _ = inbox.send(ServerCommand::VoiceRealtime {
                generation,
                event: VoiceRealtimeEvent::Error {
                    message: error.to_string(),
                },
            });
        }
        let _ = inbox.send(ServerCommand::VoiceRealtime {
            generation,
            event: VoiceRealtimeEvent::Closed,
        });
    });
    VoiceRealtimeHandle {
        generation,
        tx,
        task,
    }
}

async fn run_voice_realtime(
    config: VoiceRealtimeConfig,
    generation: u64,
    mut rx: UnboundedReceiver<RealtimeClientMessage>,
    inbox: UnboundedSender<ServerCommand>,
) -> HostResult<()> {
    let (mut write, mut read) = connect_provider(&config).await?.split();
    let setup = match config.kind {
        VoiceRealtimeKind::Gemini => gemini_setup_message(&config),
        VoiceRealtimeKind::OpenAi => openai_session_update(&config),
    };
    write
        .send(json_message(&setup))
        .await
        .map_err(|error| HostError::state(format!("realtime setup failed: {error}")))?;

    let mut ready = false;
    let mut pending: Vec<RealtimeClientMessage> = Vec::new();
    let mut response_active = false;
    let mut speak_busy = false;
    let mut pending_speak: VecDeque<(String, Option<u64>)> = VecDeque::new();
    let mut active_response_id: Option<String> = None;
    let mut active_utterance_id: Option<u64> = None;
    let mut requested_utterance_id: Option<u64> = None;
    let mut cancel_pending = false;
    let mut cancelled_response_ids: HashSet<String> = HashSet::new();
    let mut response_utterances: HashMap<String, u64> = HashMap::new();
    let mut gemini_drain = false;
    let mut gemini_drain_input = false;
    let mut gemini_input_busy = false;
    let mut gemini_input_generation: u64 = 0;
    let mut gemini_completing_generations: VecDeque<u64> = VecDeque::new();
    loop {
        tokio::select! {
            inbound = read.next() => {
                let Some(frame) = inbound else {
                    break;
                };
                let frame = frame.map_err(|error| {
                    HostError::state(format!("realtime socket failed: {error}"))
                })?;
                let parsed = match &frame {
                    Message::Text(text) => Some(decode_realtime_json(Some(text.as_str()), None)),
                    Message::Binary(bytes) => Some(decode_realtime_json(None, Some(bytes))),
                    Message::Ping(payload) => {
                        let _ = write.send(Message::Pong(payload.clone())).await;
                        None
                    }
                    Message::Close(_) => break,
                    _ => None,
                };
                let Some(parsed) = parsed else {
                    continue;
                };
                let events = match config.kind {
                    VoiceRealtimeKind::Gemini => parse_gemini_message(&parsed),
                    VoiceRealtimeKind::OpenAi => parse_openai_message(&parsed),
                };
                for event in events {
                            match event {
                                RealtimeParsed::SetupComplete => {
                                    if !ready {
                                        ready = true;
                                        report(&inbox, generation, VoiceRealtimeEvent::Ready);
                                        for queued in pending.drain(..) {
                                            apply_client_message(
                                                &mut write,
                                                &config,
                                                queued,
                                                &mut response_active,
                                                &mut speak_busy,
                                                &mut pending_speak,
                                                &mut active_response_id,
                                                &mut active_utterance_id,
                                                &mut requested_utterance_id,
                                                &mut cancel_pending,
                                                &mut cancelled_response_ids,
                                                &mut response_utterances,
                                                &mut gemini_input_busy,
                                                &mut gemini_input_generation,
                                                &mut gemini_completing_generations,
                                            )
                                            .await?;
                                        }
                                    }
                                }
                                RealtimeParsed::InputTranscript { text, is_final, item_id } => {
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::UserTranscript { text, is_final, item_id },
                                    );
                                }
                                RealtimeParsed::Audio { pcm, sample_rate, response_id } => {
                                    if is_cancelled_response(&cancelled_response_ids, response_id.as_deref()) {
                                        continue;
                                    }
                                    if suppress_unowned_gemini_audio(
                                        gemini_input_busy,
                                        config.kind,
                                        &response_utterances,
                                        response_id.as_deref(),
                                        active_utterance_id,
                                    ) {
                                        continue;
                                    }
                                    response_active = true;
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::Audio {
                                            pcm,
                                            sample_rate,
                                            utterance_id: utterance_for_response(
                                                &response_utterances,
                                                response_id.as_deref(),
                                                active_utterance_id,
                                            ),
                                        },
                                    );
                                }
                                RealtimeParsed::ResponseCreated { id } => {
                                    if let Some(id) = id.clone() {
                                        if let Some(utterance_id) = requested_utterance_id {
                                            response_utterances.insert(id.clone(), utterance_id);
                                            active_utterance_id = Some(utterance_id);
                                        }
                                        active_response_id = Some(id);
                                    } else if let Some(utterance_id) = requested_utterance_id {
                                        active_utterance_id = Some(utterance_id);
                                    }
                                    response_active = true;
                                    if cancel_pending {
                                        cancel_pending = false;
                                        cancel_active_response(
                                            &mut write,
                                            &config,
                                            &mut response_active,
                                            &mut speak_busy,
                                            &mut active_response_id,
                                            &mut cancelled_response_ids,
                                        )
                                        .await?;
                                    }
                                }
                                RealtimeParsed::AudioDone { response_id } => {
                                    if is_cancelled_response(&cancelled_response_ids, response_id.as_deref()) {
                                        continue;
                                    }
                                    if suppress_unowned_gemini_audio(
                                        gemini_input_busy,
                                        config.kind,
                                        &response_utterances,
                                        response_id.as_deref(),
                                        active_utterance_id,
                                    ) {
                                        continue;
                                    }
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::AudioDone {
                                            utterance_id: utterance_for_response(
                                                &response_utterances,
                                                response_id.as_deref(),
                                                active_utterance_id,
                                            ),
                                        },
                                    );
                                }
                                RealtimeParsed::ResponseFinished { response_id } => {
                                    if gemini_drain && config.kind == VoiceRealtimeKind::Gemini {
                                        gemini_drain = false;
                                        if gemini_drain_input {
                                            gemini_drain_input = false;
                                            retire_stale_gemini_input_generation(
                                                &mut gemini_completing_generations,
                                            );
                                        }
                                        response_active = false;
                                        speak_busy = false;
                                        active_response_id = None;
                                        active_utterance_id = None;
                                        requested_utterance_id = None;
                                        if interrupted_speak_drain_keeps_microphone(
                                            gemini_input_busy,
                                            &mut speak_busy,
                                        ) {
                                            continue;
                                        }
                                        flush_pending_speak(
                                            &mut write,
                                            &config,
                                            &mut response_active,
                                            &mut speak_busy,
                                            &mut pending_speak,
                                            &mut active_response_id,
                                            &mut active_utterance_id,
                                            &mut requested_utterance_id,
                                            &mut cancel_pending,
                                            &mut cancelled_response_ids,
                                            &mut response_utterances,
                                            &mut gemini_input_busy,
                                            &mut gemini_input_generation,
                                            &mut gemini_completing_generations,
                                        )
                                        .await?;
                                        continue;
                                    }
                                    if suppress_unowned_gemini_audio(
                                        gemini_input_busy,
                                        config.kind,
                                        &response_utterances,
                                        response_id.as_deref(),
                                        active_utterance_id,
                                    ) {
                                        if !finish_unowned_gemini_input(
                                            &mut speak_busy,
                                            &mut gemini_input_busy,
                                            gemini_input_generation,
                                            &mut gemini_completing_generations,
                                        ) {
                                            continue;
                                        }
                                        response_active = false;
                                        flush_pending_speak(
                                            &mut write,
                                            &config,
                                            &mut response_active,
                                            &mut speak_busy,
                                            &mut pending_speak,
                                            &mut active_response_id,
                                            &mut active_utterance_id,
                                            &mut requested_utterance_id,
                                            &mut cancel_pending,
                                            &mut cancelled_response_ids,
                                            &mut response_utterances,
                                            &mut gemini_input_busy,
                                            &mut gemini_input_generation,
                                            &mut gemini_completing_generations,
                                        )
                                        .await?;
                                        continue;
                                    }
                                    response_active = false;
                                    speak_busy = false;
                                    if let Some(id) = response_id.as_deref() {
                                        response_utterances.remove(id);
                                        cancelled_response_ids.remove(id);
                                    }
                                    active_response_id = None;
                                    active_utterance_id = None;
                                    requested_utterance_id = None;
                                    flush_pending_speak(
                                        &mut write,
                                        &config,
                                        &mut response_active,
                                        &mut speak_busy,
                                        &mut pending_speak,
                                        &mut active_response_id,
                                        &mut active_utterance_id,
                                        &mut requested_utterance_id,
                                        &mut cancel_pending,
                                        &mut cancelled_response_ids,
                                        &mut response_utterances,
                                        &mut gemini_input_busy,
                                        &mut gemini_input_generation,
                                        &mut gemini_completing_generations,
                                    )
                                    .await?;
                                }
                                RealtimeParsed::Interrupted { response_id } => {
                                    let interrupted_utterance = utterance_for_response(
                                        &response_utterances,
                                        response_id.as_deref(),
                                        active_utterance_id,
                                    );
                                    if let Some(id) = response_id.clone() {
                                        cancelled_response_ids.insert(id.clone());
                                        if active_response_id.as_ref() != Some(&id) {
                                            continue;
                                        }
                                    } else if active_response_id.is_none()
                                        && config.kind != VoiceRealtimeKind::Gemini
                                    {
                                        continue;
                                    }
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::Interrupted {
                                            utterance_id: interrupted_utterance,
                                        },
                                    );
                                    if config.kind == VoiceRealtimeKind::Gemini {
                                        gemini_drain = true;
                                        gemini_drain_input = interrupted_utterance.is_none();
                                        response_active = true;
                                        speak_busy = true;
                                        continue;
                                    }
                                    active_response_id = None;
                                    response_active = false;
                                    speak_busy = false;
                                    active_utterance_id = None;
                                    requested_utterance_id = None;
                                    flush_pending_speak(
                                        &mut write,
                                        &config,
                                        &mut response_active,
                                        &mut speak_busy,
                                        &mut pending_speak,
                                        &mut active_response_id,
                                        &mut active_utterance_id,
                                        &mut requested_utterance_id,
                                        &mut cancel_pending,
                                        &mut cancelled_response_ids,
                                        &mut response_utterances,
                                        &mut gemini_input_busy,
                                        &mut gemini_input_generation,
                                        &mut gemini_completing_generations,
                                    )
                                    .await?;
                                }
                                RealtimeParsed::TurnComplete => {}
                                RealtimeParsed::InputCommitted { item_id } => {
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::InputCommitted { item_id },
                                    );
                                }
                                RealtimeParsed::InputTranscriptionFailed { item_id, message } => {
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::Error { message },
                                    );
                                    report(
                                        &inbox,
                                        generation,
                                        VoiceRealtimeEvent::UserTranscript {
                                            text: String::new(),
                                            is_final: true,
                                            item_id,
                                        },
                                    );
                                }
                                RealtimeParsed::Error { message } => {
                                    if is_recoverable_realtime_error(&message) {
                                        report(
                                            &inbox,
                                            generation,
                                            VoiceRealtimeEvent::Error { message },
                                        );
                                        continue;
                                    }
                                    return Err(HostError::state(message));
                                }
                            }
                }
            }
            command = rx.recv() => {
                let Some(command) = command else {
                    break;
                };
                if matches!(command, RealtimeClientMessage::Close) {
                    let _ = write.close().await;
                    break;
                }
                if !ready {
                    pending.push(command);
                    continue;
                }
                apply_client_message(
                    &mut write,
                    &config,
                    command,
                    &mut response_active,
                    &mut speak_busy,
                    &mut pending_speak,
                    &mut active_response_id,
                    &mut active_utterance_id,
                    &mut requested_utterance_id,
                    &mut cancel_pending,
                    &mut cancelled_response_ids,
                    &mut response_utterances,
                    &mut gemini_input_busy,
                    &mut gemini_input_generation,
                    &mut gemini_completing_generations,
                )
                .await?;
            }
        }
    }
    Ok(())
}

async fn connect_provider(
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
    let (socket, _) = connect_async(request)
        .await
        .map_err(|error| HostError::state(format!("realtime connect failed: {error}")))?;
    Ok(socket)
}

async fn apply_client_message<S>(
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
            if config.kind == VoiceRealtimeKind::OpenAi
                && active_response_id.is_none()
                && *response_active
            {
                *cancel_pending = true;
            } else {
                *cancel_pending = false;
            }
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

async fn cancel_active_response<S>(
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

async fn flush_pending_speak<S>(
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

fn is_cancelled_response(cancelled: &HashSet<String>, response_id: Option<&str>) -> bool {
    response_id.is_some_and(|id| cancelled.contains(id))
}

fn utterance_for_response(
    response_utterances: &HashMap<String, u64>,
    response_id: Option<&str>,
    active_utterance_id: Option<u64>,
) -> Option<u64> {
    if let Some(id) = response_id {
        return response_utterances.get(id).copied();
    }
    active_utterance_id
}

fn should_queue_gemini_speak(speak_busy: bool, gemini_input_busy: bool) -> bool {
    speak_busy || gemini_input_busy
}

fn finish_unowned_gemini_input(
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

fn retire_stale_gemini_input_generation(completing_generations: &mut VecDeque<u64>) {
    let _ = completing_generations.pop_front();
}

fn delayed_input_completion_releases_current(
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

fn suppress_unowned_gemini_audio(
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

fn speak_frames(config: &VoiceRealtimeConfig, text: &str) -> Vec<Value> {
    match config.kind {
        VoiceRealtimeKind::Gemini => gemini_speak_frames(text),
        VoiceRealtimeKind::OpenAi => vec![openai_speak_message(text)],
    }
}

fn interrupt_frames(config: &VoiceRealtimeConfig, response_id: Option<&str>) -> Vec<Value> {
    match config.kind {
        VoiceRealtimeKind::Gemini => vec![gemini_activity_start()],
        VoiceRealtimeKind::OpenAi => vec![openai_cancel_response(response_id)],
    }
}

fn other_frames(config: &VoiceRealtimeConfig, command: RealtimeClientMessage) -> Vec<Value> {
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

async fn send_frames<S>(write: &mut S, frames: Vec<Value>) -> HostResult<()>
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

fn is_recoverable_realtime_error(message: &str) -> bool {
    let lowered = message.to_ascii_lowercase();
    lowered.contains("cancellation")
        || lowered.contains("no active response")
        || lowered.contains("response already")
        || lowered.contains("already has an active response")
        || lowered.contains("conversation already has")
        || lowered.contains("in_progress")
}

fn json_message(value: &Value) -> Message {
    Message::text(value.to_string())
}

fn decode_realtime_json(text: Option<&str>, binary: Option<&[u8]>) -> Value {
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

fn interrupted_speak_drain_keeps_microphone(
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

fn report(inbox: &UnboundedSender<ServerCommand>, generation: u64, event: VoiceRealtimeEvent) {
    let _ = inbox.send(ServerCommand::VoiceRealtime { generation, event });
}

#[cfg(test)]
mod tests {
    use super::is_recoverable_realtime_error;

    #[test]
    fn cancellation_without_active_response_is_recoverable() {
        assert!(is_recoverable_realtime_error(
            "Cancellation failed: no active response to cancel"
        ));
        assert!(!is_recoverable_realtime_error("invalid_api_key"));
    }

    #[test]
    fn gemini_input_completion_releases_queued_speak() {
        let mut speak_busy = true;
        let mut gemini_input_busy = true;
        let mut pending: std::collections::VecDeque<(String, Option<u64>)> =
            std::collections::VecDeque::from([("On it.".into(), Some(7u64))]);
        assert!(super::should_queue_gemini_speak(
            speak_busy,
            gemini_input_busy
        ));
        let mut completing = std::collections::VecDeque::from([1u64]);
        super::finish_unowned_gemini_input(
            &mut speak_busy,
            &mut gemini_input_busy,
            1,
            &mut completing,
        );
        assert!(!speak_busy);
        assert!(!gemini_input_busy);
        assert!(!super::should_queue_gemini_speak(
            speak_busy,
            gemini_input_busy
        ));
        let released = pending.pop_front().unwrap();
        assert_eq!(released, ("On it.".into(), Some(7)));
        assert!(pending.is_empty());
    }

    #[test]
    fn gemini_speak_during_microphone_start_stays_queued() {
        assert!(super::should_queue_gemini_speak(true, true));
        let mut speak_busy = true;
        let mut gemini_input_busy = true;
        let mut completing = std::collections::VecDeque::from([1u64]);
        super::finish_unowned_gemini_input(
            &mut speak_busy,
            &mut gemini_input_busy,
            1,
            &mut completing,
        );
        assert!(!super::should_queue_gemini_speak(
            speak_busy,
            gemini_input_busy
        ));
    }

    #[test]
    fn interrupted_input_completion_consumes_stale_generation_without_releasing_newer() {
        let mut completing = std::collections::VecDeque::from([1u64, 2]);
        super::retire_stale_gemini_input_generation(&mut completing);
        assert_eq!(completing.front().copied(), Some(2));
        let mut speak_busy = true;
        let mut gemini_input_busy = true;
        assert!(super::finish_unowned_gemini_input(
            &mut speak_busy,
            &mut gemini_input_busy,
            2,
            &mut completing
        ));
        assert!(!speak_busy);
        assert!(!gemini_input_busy);
        assert!(completing.is_empty());
    }

    #[test]
    fn interrupted_speak_does_not_consume_input_generation() {
        let mut completing = std::collections::VecDeque::from([2u64]);
        let drain_input = false;
        if drain_input {
            super::retire_stale_gemini_input_generation(&mut completing);
        }
        assert_eq!(completing.front().copied(), Some(2));
    }

    #[test]
    fn stale_gemini_input_completion_does_not_release_newer_reservation() {
        let mut speak_busy = true;
        let mut gemini_input_busy = true;
        let mut completing = std::collections::VecDeque::from([1u64]);
        assert!(!super::delayed_input_completion_releases_current(
            2,
            &mut completing
        ));
        assert!(completing.is_empty());
        assert!(!super::finish_unowned_gemini_input(
            &mut speak_busy,
            &mut gemini_input_busy,
            2,
            &mut completing
        ));
        assert!(speak_busy);
        assert!(gemini_input_busy);
    }

    #[test]
    fn gemini_speak_after_input_completion_sends_immediately() {
        let mut speak_busy = true;
        let mut gemini_input_busy = true;
        let mut completing = std::collections::VecDeque::from([1u64]);
        super::finish_unowned_gemini_input(
            &mut speak_busy,
            &mut gemini_input_busy,
            1,
            &mut completing,
        );
        assert!(!super::should_queue_gemini_speak(
            speak_busy,
            gemini_input_busy
        ));
    }

    #[test]
    fn binary_setup_complete_decodes_as_json() {
        let json = br#"{"setupComplete":{}}"#;
        let parsed = super::decode_realtime_json(None, Some(json));
        assert!(parsed.get("setupComplete").is_some());
        let text = super::decode_realtime_json(Some(r#"{"setupComplete":{}}"#), None);
        assert!(text.get("setupComplete").is_some());
    }

    #[test]
    fn interrupted_speak_drain_preserves_newer_microphone_reservation() {
        let mut speak_busy = false;
        assert!(super::interrupted_speak_drain_keeps_microphone(
            true,
            &mut speak_busy
        ));
        assert!(speak_busy);
        let mut speak_busy = true;
        assert!(!super::interrupted_speak_drain_keeps_microphone(
            false,
            &mut speak_busy
        ));
        assert!(speak_busy);
    }

    #[test]
    fn unowned_gemini_input_audio_is_suppressed_until_speak_is_submitted() {
        let mapped = std::collections::HashMap::new();
        assert!(super::suppress_unowned_gemini_audio(
            true,
            super::VoiceRealtimeKind::Gemini,
            &mapped,
            None,
            None,
        ));
        assert!(!super::suppress_unowned_gemini_audio(
            true,
            super::VoiceRealtimeKind::Gemini,
            &mapped,
            None,
            Some(7),
        ));
        assert!(!super::suppress_unowned_gemini_audio(
            false,
            super::VoiceRealtimeKind::Gemini,
            &mapped,
            None,
            None,
        ));
    }
}
