//! Realtime socket events, transcript settling, and reconnects.

use std::time::Duration;

use alera_core::runtime::RuntimeVoiceSettings;
use serde_json::json;

use super::server_command::ServerCommand;
use super::voice_realtime::{
    config_for_provider, looks_like_home_cancel, RealtimeClientMessage, VoiceRealtimeEvent,
};
use super::voice_realtime_reconnect::{plan_realtime_reconnect, RealtimeReconnectPlan};
use super::voice_realtime_session::spawn_voice_realtime;
use super::voice_session::VoiceSessionPhase;
use super::ServerActor;
use crate::terminal_host::host_error::HostResult;
use crate::terminal_host::protocol::event;

impl ServerActor {
    pub(super) async fn handle_voice_realtime_event(
        &mut self,
        generation: u64,
        realtime_event: VoiceRealtimeEvent,
    ) {
        if self.voice.realtime_generation != generation {
            return;
        }
        match realtime_event {
            VoiceRealtimeEvent::Ready => {
                self.voice.last_error = None;
                self.voice.realtime_reconnect_attempts = 0;
                self.broadcast_voice_session().await;
            }
            VoiceRealtimeEvent::InputCommitted { item_id } => {
                if !item_id.is_empty() && !self.voice.openai_committed_items.contains(&item_id) {
                    self.voice.openai_committed_items.push_back(item_id);
                }
            }
            VoiceRealtimeEvent::UserTranscript {
                text,
                is_final,
                item_id,
            } => {
                if self.voice.realtime_kind
                    == Some(super::voice_realtime::VoiceRealtimeKind::OpenAi)
                {
                    if is_final {
                        if let Some(item_id) = item_id.filter(|id| !id.is_empty()) {
                            if !self.voice.openai_committed_items.contains(&item_id) {
                                self.voice.openai_committed_items.push_back(item_id.clone());
                            }
                            self.voice
                                .openai_completed_transcripts
                                .insert(item_id, text);
                        } else {
                            let trimmed = text.trim();
                            if !trimmed.is_empty() {
                                self.voice.last_flushed_transcript = None;
                                self.voice.pending_transcript = trimmed.to_string();
                                self.flush_realtime_transcript(true).await;
                            }
                        }
                        self.flush_openai_committed_transcripts().await;
                    }
                    return;
                }
                if !text.is_empty() {
                    self.voice.merge_pending_transcript(&text);
                    if self.voice.realtime_kind
                        == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                    {
                        self.voice.gemini_transcript_final = false;
                    }
                }
                if is_final {
                    if self.voice.realtime_kind
                        == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                    {
                        self.voice.gemini_transcript_final = true;
                    }
                    if self.voice.realtime_kind
                        == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                        && !self.voice.gemini_activity_ended
                    {
                        self.schedule_gemini_transcript_settle();
                    } else {
                        self.voice.gemini_transcript_token =
                            self.voice.gemini_transcript_token.saturating_add(1);
                        self.voice.gemini_settling = false;
                        self.flush_realtime_transcript(true).await;
                    }
                } else if self.voice.realtime_kind
                    == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                {
                    self.schedule_gemini_transcript_settle();
                }
            }
            VoiceRealtimeEvent::Audio {
                pcm,
                sample_rate,
                utterance_id,
            } => {
                if !self.voice.expecting_speech {
                    return;
                }
                if !self.matches_speak_head(utterance_id) {
                    return;
                }
                use base64::Engine as _;
                self.broadcast_voice_owner(event(
                    "voice.audio",
                    json!({
                        "id": utterance_id.or_else(|| self.voice.speak_queue.front().map(|utterance| utterance.id)),
                        "audioBase64": base64::engine::general_purpose::STANDARD.encode(pcm),
                        "sampleRate": sample_rate,
                        "mimeType": format!("audio/pcm;rate={sample_rate}"),
                    }),
                ));
            }
            VoiceRealtimeEvent::AudioDone { utterance_id } => {
                if !self.voice.expecting_speech {
                    return;
                }
                if !self.matches_speak_head(utterance_id) {
                    return;
                }
                let head = self.voice.speak_queue.front();
                self.broadcast_voice_owner(event(
                    "voice.audioDone",
                    json!({
                        "id": utterance_id.or_else(|| head.map(|utterance| utterance.id)),
                        "text": head.map(|utterance| utterance.text.clone()),
                    }),
                ));
            }
            VoiceRealtimeEvent::Interrupted { utterance_id } => {
                let cancelled = self.voice.interrupt_playback_head(utterance_id);
                if cancelled.is_empty() {
                    return;
                }
                self.broadcast_voice_owner(event(
                    "voice.interrupt",
                    json!({
                        "reason": "realtime",
                        "id": cancelled.first().map(|utterance| utterance.id),
                    }),
                ));
                if let Some(handle) = self.voice.realtime.as_ref() {
                    if let Some(next) = self.voice.speak_queue.front() {
                        self.voice.expecting_speech = true;
                        handle.send(RealtimeClientMessage::Speak {
                            text: next.text.clone(),
                            utterance_id: Some(next.id),
                        });
                    }
                }
                self.broadcast_voice_session().await;
            }
            VoiceRealtimeEvent::Error { message } => {
                self.voice.last_error = Some(message);
                self.broadcast_voice_session().await;
            }
            VoiceRealtimeEvent::Closed { error } => {
                if let Some(message) = error.as_ref() {
                    self.voice.last_error = Some(message.clone());
                }
                if self
                    .voice
                    .realtime
                    .as_ref()
                    .is_some_and(|handle| handle.generation == generation)
                {
                    self.voice.realtime = None;
                }
                self.voice.expecting_speech = false;
                self.voice.reset_gemini_utterance();
                self.voice.reset_openai_input_order();
                self.voice.gemini_settling = false;
                if let Some((old_id, utterance)) = self.voice.refresh_speak_head_identity() {
                    self.broadcast_voice_owner(event(
                        "voice.interrupt",
                        json!({
                            "reason": "realtime-reconnect",
                            "id": old_id,
                        }),
                    ));
                    self.broadcast_voice_owner(event(
                        "voice.utterance",
                        json!({
                            "id": utterance.id,
                            "text": utterance.text,
                            "queued": self.voice.speak_queue.len(),
                            "realtime": true,
                        }),
                    ));
                }
                if self.voice.phase != VoiceSessionPhase::Idle {
                    self.schedule_realtime_reconnect(generation, error.as_deref());
                }
                self.broadcast_voice_session().await;
            }
        }
    }

    pub(super) async fn handle_voice_realtime_reconnect(&mut self, generation: u64) {
        if self.voice.phase == VoiceSessionPhase::Idle {
            return;
        }
        if self.voice.realtime.is_some() {
            return;
        }
        if self.voice.realtime_generation != generation {
            return;
        }
        match self.maybe_start_realtime().await {
            Ok(()) => {
                self.voice.last_error = None;
                if let Some(handle) = self.voice.realtime.as_ref() {
                    if let Some(next) = self.voice.speak_queue.front() {
                        self.voice.expecting_speech = true;
                        handle.send(RealtimeClientMessage::Speak {
                            text: next.text.clone(),
                            utterance_id: Some(next.id),
                        });
                    }
                }
                self.broadcast_voice_session().await;
            }
            Err(error) => {
                // Settings or credential failures: retrying cannot fix them.
                self.voice.last_error = Some(format!("Realtime speech stopped: {error}"));
                self.broadcast_voice_session().await;
            }
        }
    }

    pub(super) fn schedule_gemini_transcript_settle(&mut self) {
        self.voice.gemini_settling = true;
        self.voice.gemini_transcript_token = self.voice.gemini_transcript_token.saturating_add(1);
        let token = self.voice.gemini_transcript_token;
        let generation = self.voice.realtime_generation;
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(350)).await;
            let _ = inbox.send(ServerCommand::VoiceGeminiTranscriptSettle { generation, token });
        });
    }

    pub(super) async fn handle_voice_gemini_transcript_settle(
        &mut self,
        generation: u64,
        token: u64,
    ) {
        if self.voice.realtime_generation != generation {
            return;
        }
        if self.voice.gemini_transcript_token != token {
            return;
        }
        if self.voice.pending_transcript.trim().is_empty() {
            // Keep gemini_settling so a later ActivityStart stays held until
            // this activity's delayed transcript is flushed or the session resets.
            return;
        }
        if self.voice.realtime_kind == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
            && !self.voice.gemini_activity_ended
        {
            return;
        }
        self.flush_realtime_transcript(false).await;
        self.voice.gemini_settling = true;
    }

    pub(super) fn schedule_realtime_reconnect(&mut self, generation: u64, failure: Option<&str>) {
        let delay = match plan_realtime_reconnect(self.voice.realtime_reconnect_attempts, failure) {
            RealtimeReconnectPlan::Retry { delay } => delay,
            RealtimeReconnectPlan::GiveUp { message } => {
                self.voice.last_error = Some(message);
                return;
            }
        };
        self.voice.realtime_reconnect_attempts =
            self.voice.realtime_reconnect_attempts.saturating_add(1);
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = inbox.send(ServerCommand::VoiceRealtimeReconnect { generation });
        });
    }

    pub(super) async fn flush_realtime_transcript(&mut self, retire: bool) {
        if self.voice.realtime_kind == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
            && !self.voice.gemini_activity_ended
        {
            return;
        }
        let Some(text) = self.voice.take_pending_transcript() else {
            if retire {
                self.release_held_gemini_activity();
            }
            return;
        };
        let Some((next_flushed, dispatch)) = super::voice_transcript::transcript_dispatch(
            self.voice.last_flushed_transcript.as_deref(),
            &text,
        ) else {
            if retire {
                self.release_held_gemini_activity();
            } else {
                self.voice.pending_transcript = text;
            }
            return;
        };
        self.voice.last_flushed_transcript = Some(next_flushed.clone());
        if let Err(error) = self
            .accept_voice_turn(
                dispatch.clone(),
                &json!({ "cancelHome": looks_like_home_cancel(&dispatch) }),
                true,
            )
            .await
        {
            self.voice.last_error = Some(error.to_string());
            self.broadcast_voice_session().await;
        }
        if retire {
            self.release_held_gemini_activity();
        } else {
            self.voice.pending_transcript = next_flushed;
        }
    }

    pub(super) fn release_held_gemini_activity(&mut self) {
        let Some(activity) = self.voice.gemini_held_activities.pop_front() else {
            return;
        };
        self.voice.pending_transcript.clear();
        self.voice.last_flushed_transcript = None;
        self.voice.gemini_settling = false;
        self.voice.gemini_activity_ended = false;
        self.voice.gemini_transcript_final = false;
        let Some(handle) = self.voice.realtime.as_ref() else {
            return;
        };
        handle.send(RealtimeClientMessage::ActivityStart);
        if !activity.pcm.is_empty() {
            handle.send(RealtimeClientMessage::Audio {
                pcm16k: activity.pcm,
            });
        }
        if activity.ended {
            self.voice.gemini_activity_ended = true;
            handle.send(RealtimeClientMessage::ActivityEnd);
            if self.voice.gemini_transcript_final {
                self.voice.gemini_transcript_token =
                    self.voice.gemini_transcript_token.saturating_add(1);
                self.voice.gemini_settling = false;
            } else {
                self.schedule_gemini_transcript_settle();
            }
        }
    }

    pub(super) async fn flush_openai_committed_transcripts(&mut self) {
        while let Some(item_id) = self.voice.openai_committed_items.front().cloned() {
            let Some(text) = self.voice.openai_completed_transcripts.remove(&item_id) else {
                break;
            };
            self.voice.openai_committed_items.pop_front();
            let trimmed = text.trim();
            if trimmed.is_empty() {
                continue;
            }
            self.voice.openai_item_id = Some(item_id);
            self.voice.pending_transcript = trimmed.to_string();
            self.voice.last_flushed_transcript = None;
            self.flush_realtime_transcript(true).await;
        }
    }

    pub(super) async fn maybe_start_realtime(&mut self) -> HostResult<()> {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        if settings.pipeline != alera_core::runtime::RuntimeVoicePipeline::Realtime {
            self.voice.stop_realtime();
            return Ok(());
        }
        if self.voice.realtime.is_some() {
            return Ok(());
        }
        let credentials = self.voice_credential_store().load().await?;
        let provider = match settings.realtime_provider {
            alera_core::runtime::RuntimeVoiceRealtimeProvider::GptRealtimeMini => "gptRealtimeMini",
            alera_core::runtime::RuntimeVoiceRealtimeProvider::GptRealtime => "gptRealtime",
            alera_core::runtime::RuntimeVoiceRealtimeProvider::GptLive1 => "gptLive1",
            alera_core::runtime::RuntimeVoiceRealtimeProvider::GeminiFlashLive => "geminiFlashLive",
        };
        let config = config_for_provider(
            provider,
            credentials.gemini_token.as_deref(),
            credentials.openai_token.as_deref(),
            settings.tts_voice.as_deref(),
        )?;
        self.voice.realtime_generation = self.voice.realtime_generation.saturating_add(1);
        let generation = self.voice.realtime_generation;
        self.voice.realtime_kind = Some(config.kind);
        self.voice.realtime = Some(spawn_voice_realtime(config, generation, self.inbox.clone()));
        Ok(())
    }
}
