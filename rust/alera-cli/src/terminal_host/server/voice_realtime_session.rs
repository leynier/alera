use std::collections::{HashMap, HashSet, VecDeque};

use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};
use tokio_tungstenite::tungstenite::Message;

use super::server_command::ServerCommand;
use super::voice_realtime::{
    gemini_setup_message, openai_session_update, parse_gemini_message, parse_openai_message,
    RealtimeClientMessage, RealtimeParsed, VoiceRealtimeConfig, VoiceRealtimeEvent,
    VoiceRealtimeKind,
};
use super::voice_realtime_socket::{
    abnormal_close_message, apply_client_message, cancel_active_response, connect_provider,
    decode_realtime_json, finish_unowned_gemini_input, flush_pending_speak,
    interrupted_speak_drain_keeps_microphone, is_cancelled_response, is_recoverable_realtime_error,
    json_message, report, retire_stale_gemini_input_generation, suppress_unowned_gemini_audio,
    utterance_for_response,
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
        let _ = inbox.send(ServerCommand::VoiceRealtime {
            generation,
            event: VoiceRealtimeEvent::Closed {
                error: result.err().map(|error| error.to_string()),
            },
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
                    Message::Close(frame) => {
                        if let Some(message) = abnormal_close_message(frame.as_ref()) {
                            return Err(HostError::state(message));
                        }
                        break;
                    }
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
