use std::time::Duration;

use alera_core::runtime::{
    is_voice_home_workspace_id, RuntimeVoiceSettings, VOICE_HOME_WORKSPACE_ID,
};
use serde_json::{json, Value};

use super::ai_dictation_credentials::AiDictationCredentialStore;
use super::ai_dictation_openai::OpenAiDictationRequest;
use super::host_service_requests::required_non_blank;
use super::server_command::ServerCommand;
use super::voice_credentials::VoiceCredentialStore;
use super::voice_realtime::{
    config_for_provider, looks_like_home_cancel, RealtimeClientMessage, VoiceRealtimeEvent,
};
use super::voice_realtime_session::spawn_voice_realtime;
use super::voice_session::{PendingVoiceTurn, VoiceSessionPhase};
use super::voice_stt::transcribe_gemini;
use super::voice_tts::{synthesize, SynthesizeRequest};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_prompt_injection::{
    build_agent_prompt_paste_bytes, AGENT_PROMPT_SUBMIT,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS;
use crate::terminal_host::protocol::event;
use crate::terminal_host::protocol::{error_response, ok_response};
use crate::terminal_host::session::{PtyWriteCompletion, Session};

impl ServerActor {
    pub(super) async fn voice_ensure_request(&mut self) -> HostResult<Value> {
        self.ensure_voice_home().await?;
        self.voice_status_payload().await
    }

    pub(super) async fn voice_status_request(&mut self) -> HostResult<Value> {
        if self.voice.home.is_none() {
            let _ = self.ensure_voice_home().await;
        }
        self.voice_status_payload().await
    }

    pub(super) async fn voice_speak_request(&mut self, payload: &Value) -> HostResult<Value> {
        self.ensure_voice_home().await?;
        if self.voice.capture_owner_client_id.is_none()
            || self.voice.phase == VoiceSessionPhase::Idle
        {
            return Err(HostError::state("Start a voice session before speaking."));
        }
        let text = required_non_blank(payload, "text")?;
        let utterance = self.voice.enqueue_speak(text);
        if let Some(handle) = self.voice.realtime.as_ref() {
            if self.voice.speak_queue.len() == 1 {
                self.voice.expecting_speech = true;
                handle.send(RealtimeClientMessage::Speak {
                    text: utterance.text.clone(),
                    utterance_id: Some(utterance.id),
                });
            }
        }
        self.broadcast_voice_owner(event(
            "voice.utterance",
            json!({
                "id": utterance.id,
                "text": utterance.text,
                "queued": self.voice.speak_queue.len(),
                "realtime": self.voice.realtime.is_some(),
            }),
        ));
        self.broadcast_voice_session().await;
        Ok(json!({
            "queued": true,
            "text": utterance.text,
            "message": utterance.text,
            "queuedSpeakCount": self.voice.speak_queue.len(),
        }))
    }

    pub(super) async fn voice_start_request(&mut self, client_id: u64) -> HostResult<Value> {
        self.ensure_voice_home().await?;
        self.voice.claim_capture(client_id)?;
        let started = async {
            self.ensure_home_agent().await?;
            self.voice.phase = VoiceSessionPhase::Listening;
            self.voice.last_error = None;
            self.maybe_start_realtime().await
        }
        .await;
        if let Err(error) = started {
            self.voice.release_capture(Some(client_id));
            self.voice.phase = VoiceSessionPhase::Idle;
            self.voice.stop_realtime();
            return Err(error);
        }
        self.broadcast_voice_session().await;
        self.voice_status_payload().await
    }

    pub(super) async fn voice_stop_request(&mut self, client_id: u64) -> HostResult<Value> {
        if self
            .voice
            .capture_owner_client_id
            .is_some_and(|owner| owner != client_id)
        {
            return Err(HostError::state(
                "Voice capture is already owned by another client. Stop that session first.",
            ));
        }
        self.stop_voice_session("stop").await
    }

    pub(super) async fn release_voice_capture_for_client(&mut self, client_id: u64) {
        if self.voice.capture_owner_client_id != Some(client_id) {
            return;
        }
        let _ = self.stop_voice_session("disconnect").await;
    }

    async fn stop_voice_session(&mut self, reason: &str) -> HostResult<Value> {
        let owner = self.voice.capture_owner_client_id;
        self.voice.cancel_jobs();
        self.voice.interrupt_playback();
        if let Some(inject) = self.voice.home_inject.as_mut() {
            inject.turns.clear();
        }
        self.voice.home_interrupt_pending = false;
        self.voice.pending_user_turns.clear();
        self.voice.in_flight_turn_jobs.clear();
        let cancelled = std::mem::take(&mut self.voice.completed_turn_jobs);
        for completed in cancelled.into_values() {
            self.client_write(
                completed.client_id,
                error_response(
                    completed.request_id,
                    &HostError::state("Voice turn was cancelled."),
                ),
            );
        }
        self.voice.stop_realtime();
        self.voice.phase = VoiceSessionPhase::Idle;
        if let Some(client_id) = owner {
            self.client_write(
                client_id,
                event("voice.interrupt", json!({ "reason": reason })),
            );
            let _ = self.voice.release_capture(Some(client_id));
        }
        self.broadcast_voice_session().await;
        self.voice_status_payload().await
    }

    pub(super) async fn voice_turn_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.ensure_voice_home().await?;
        self.require_voice_capture_owner(client_id)?;
        let from_realtime = payload
            .get("fromRealtime")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if payload.get("audioBase64").is_some() {
            return Err(HostError::state(
                "voice.turn audio must be started as a deferred request.",
            ));
        }
        let text = required_non_blank(payload, "text")?;
        self.accept_voice_turn(text, payload, from_realtime).await
    }

    pub(super) fn start_voice_turn(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        if self.voice.phase == VoiceSessionPhase::Idle {
            return Err(HostError::state(
                "Start a voice session before sending a turn.",
            ));
        }
        self.require_voice_capture_owner(client_id)?;
        if payload.get("audioBase64").is_none() {
            return Ok(());
        }
        let pcm = decode_pcm(payload)?;
        let from_realtime = payload
            .get("fromRealtime")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let cancel_home = payload.get("cancelHome").and_then(Value::as_bool);
        let job_id = self.voice.next_job_id();
        self.voice.in_flight_turn_jobs.push_back(job_id);
        let session_generation = self.voice.session_generation;
        let cancel_rx = self.voice.push_job_cancel();
        let inbox = self.inbox.clone();
        let runtime_dir = self.runtime_dir.clone();
        let runtime_id = self.account_push.service.runtime_id().to_string();
        let runtime_store = self.runtime_store.clone();
        let credentials_store = self.voice_credential_store();
        tokio::spawn(async move {
            let request_id_for_stt = format!("voice-turn-{job_id}");
            let transcription = transcribe_chained_job(
                pcm,
                runtime_dir,
                runtime_id,
                runtime_store,
                credentials_store,
                request_id_for_stt.clone(),
            );
            tokio::pin!(transcription);
            let result = tokio::select! {
                _ = cancel_rx => {
                    let _ = super::ai_dictation_requests::cancel(&json!({
                        "requestId": request_id_for_stt,
                    }));
                    Err(HostError::state("Voice turn was cancelled."))
                }
                result = &mut transcription => result,
            };
            let _ = inbox.send(ServerCommand::VoiceTurnFinished {
                client_id,
                request_id,
                job_id,
                session_generation,
                from_realtime,
                cancel_home,
                result,
            });
        });
        Ok(())
    }

    pub(super) fn start_voice_synthesize(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        self.require_voice_capture_owner(client_id)?;
        let text = required_non_blank(payload, "text")?;
        let provider = payload
            .get("provider")
            .and_then(Value::as_str)
            .map(str::to_string);
        let voice = payload
            .get("voice")
            .and_then(Value::as_str)
            .map(str::to_string);
        let job_id = self.voice.next_job_id();
        let session_generation = self.voice.session_generation;
        let cancel_rx = self.voice.push_job_cancel();
        let inbox = self.inbox.clone();
        let runtime_store = self.runtime_store.clone();
        let credentials_store = self.voice_credential_store();
        tokio::spawn(async move {
            let result = tokio::select! {
                _ = cancel_rx => Err(HostError::state("Voice synthesis was cancelled.")),
                result = synthesize_job(text, provider, voice, runtime_store, credentials_store) => result,
            };
            let _ = inbox.send(ServerCommand::VoiceSynthesizeFinished {
                client_id,
                request_id,
                job_id,
                session_generation,
                result,
            });
        });
        Ok(())
    }

    pub(super) async fn handle_voice_turn_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        job_id: u64,
        session_generation: u64,
        from_realtime: bool,
        cancel_home: Option<bool>,
        result: HostResult<String>,
    ) {
        if self.voice.session_generation != session_generation
            || self.voice.phase == VoiceSessionPhase::Idle
        {
            self.voice.in_flight_turn_jobs.retain(|id| *id != job_id);
            self.voice.completed_turn_jobs.remove(&job_id);
            self.client_write(
                client_id,
                error_response(request_id, &HostError::state("Voice turn was cancelled.")),
            );
            return;
        }
        self.voice.completed_turn_jobs.insert(
            job_id,
            super::voice_session::CompletedVoiceTurn {
                client_id,
                request_id,
                from_realtime,
                cancel_home,
                result,
            },
        );
        self.flush_completed_voice_turns().await;
    }

    async fn flush_completed_voice_turns(&mut self) {
        while let Some(job_id) = self.voice.in_flight_turn_jobs.front().copied() {
            let Some(completed) = self.voice.completed_turn_jobs.remove(&job_id) else {
                return;
            };
            self.voice.in_flight_turn_jobs.pop_front();
            let super::voice_session::CompletedVoiceTurn {
                client_id,
                request_id,
                from_realtime,
                cancel_home,
                result,
            } = completed;
            self.deliver_voice_turn_result(
                client_id,
                request_id,
                from_realtime,
                cancel_home,
                result,
            )
            .await;
        }
    }

    async fn deliver_voice_turn_result(
        &mut self,
        client_id: u64,
        request_id: i64,
        from_realtime: bool,
        cancel_home: Option<bool>,
        result: HostResult<String>,
    ) {
        match result {
            Ok(text) if text.trim().is_empty() => {
                self.client_write(
                    client_id,
                    ok_response(
                        request_id,
                        json!({
                            "accepted": false,
                            "text": "",
                            "queuedTurnCount": self.voice.pending_user_turns.len(),
                            "phase": self.voice.phase,
                        }),
                    ),
                );
            }
            Ok(text) => {
                let mut payload = json!({});
                if let Some(cancel_home) = cancel_home {
                    payload["cancelHome"] = json!(cancel_home);
                }
                match self.accept_voice_turn(text, &payload, from_realtime).await {
                    Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
                    Err(error) => self.client_write(client_id, error_response(request_id, &error)),
                }
            }
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }

    pub(super) fn handle_voice_synthesize_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        job_id: u64,
        session_generation: u64,
        result: HostResult<Value>,
    ) {
        let _ = job_id;
        if self.voice.session_generation != session_generation
            || self.voice.phase == VoiceSessionPhase::Idle
        {
            self.client_write(
                client_id,
                error_response(
                    request_id,
                    &HostError::state("Voice synthesis was cancelled."),
                ),
            );
            return;
        }
        match result {
            Ok(value) => self.client_write(client_id, ok_response(request_id, value)),
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
    }

    pub(super) async fn voice_audio_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_voice_capture_owner(client_id)?;
        let Some(handle) = self.voice.realtime.as_ref() else {
            return Err(HostError::state(
                "Realtime speech is not running. Start a realtime voice session first.",
            ));
        };
        let pcm = decode_pcm(payload)?;
        if pcm.is_empty() {
            return Ok(json!({ "accepted": true, "bytes": 0 }));
        }
        if !self.voice.gemini_held_activities.is_empty() {
            self.voice.hold_gemini_activity_audio(&pcm);
            return Ok(json!({ "accepted": true, "bytes": pcm.len(), "held": true }));
        }
        handle.send(RealtimeClientMessage::Audio { pcm16k: pcm });
        Ok(json!({ "accepted": true }))
    }

    pub(super) async fn voice_activity_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_voice_capture_owner(client_id)?;
        let phase = payload
            .get("phase")
            .and_then(Value::as_str)
            .unwrap_or("end");
        if self.voice.realtime.is_none() && phase != "start" {
            return Err(HostError::state(
                "Realtime speech is not running. Start a realtime voice session first.",
            ));
        }
        match phase {
            "start" => {
                let cancelled = self.voice.interrupt_playback();
                if let Some(handle) = self.voice.realtime.as_ref() {
                    handle.send(RealtimeClientMessage::Interrupt);
                }
                if self.voice.realtime_kind
                    == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                    && self.voice.holding_gemini_activity()
                {
                    self.voice.hold_gemini_activity_start();
                } else {
                    if self.voice.realtime_kind
                        == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                    {
                        self.voice.reset_gemini_utterance();
                    }
                    if let Some(handle) = self.voice.realtime.as_ref() {
                        handle.send(RealtimeClientMessage::ActivityStart);
                    }
                }
                self.broadcast_voice_owner(event(
                    "voice.interrupt",
                    json!({
                        "reason": "bargeIn",
                        "cancelHome": false,
                        "id": cancelled.first().map(|utterance| utterance.id),
                    }),
                ));
            }
            _ => {
                if !self.voice.gemini_held_activities.is_empty() {
                    self.voice.hold_gemini_activity_end();
                    return Ok(json!({ "accepted": true, "phase": phase, "held": true }));
                }
                self.voice.gemini_activity_ended = true;
                if let Some(handle) = self.voice.realtime.as_ref() {
                    handle.send(RealtimeClientMessage::ActivityEnd);
                }
                if self.voice.realtime_kind
                    == Some(super::voice_realtime::VoiceRealtimeKind::Gemini)
                {
                    if self.voice.gemini_transcript_final {
                        self.voice.gemini_transcript_token =
                            self.voice.gemini_transcript_token.saturating_add(1);
                        self.voice.gemini_settling = false;
                        self.flush_realtime_transcript(true).await;
                    } else {
                        self.schedule_gemini_transcript_settle();
                    }
                }
            }
        }
        Ok(json!({ "accepted": true, "phase": phase }))
    }

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
            VoiceRealtimeEvent::Closed => {
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
                    self.schedule_realtime_reconnect(generation);
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
                self.voice.last_error = Some(error.to_string());
                self.schedule_realtime_reconnect(generation);
                self.broadcast_voice_session().await;
            }
        }
    }

    fn schedule_gemini_transcript_settle(&mut self) {
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

    fn schedule_realtime_reconnect(&self, generation: u64) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(2)).await;
            let _ = inbox.send(ServerCommand::VoiceRealtimeReconnect { generation });
        });
    }

    async fn flush_realtime_transcript(&mut self, retire: bool) {
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
        let Some((next_flushed, dispatch)) = super::voice_session::transcript_dispatch(
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

    fn release_held_gemini_activity(&mut self) {
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

    async fn flush_openai_committed_transcripts(&mut self) {
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

    async fn maybe_start_realtime(&mut self) -> HostResult<()> {
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

    pub(super) async fn voice_spoken_request(
        &mut self,
        client_id: u64,
        payload: &Value,
    ) -> HostResult<Value> {
        self.require_voice_capture_owner(client_id)?;
        let id = payload.get("id").and_then(Value::as_u64);
        let failed = payload
            .get("failed")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let text = if failed {
            payload
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string()
        } else {
            required_non_blank(payload, "text")?
        };
        let retired = if failed {
            let error = payload
                .get("error")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("Voice playback failed.")
                .to_string();
            self.voice.fail_speak(&text, id, error)
        } else {
            self.voice.finish_speak(text.clone(), id)
        };
        if !retired {
            return self.voice_status_payload().await;
        }
        if let Some(handle) = self.voice.realtime.as_ref() {
            if !self.voice.speak_queue.is_empty() {
                self.voice.expecting_speech = true;
                if let Some(next) = self.voice.speak_queue.front() {
                    handle.send(RealtimeClientMessage::Speak {
                        text: next.text.clone(),
                        utterance_id: Some(next.id),
                    });
                }
            } else {
                self.voice.expecting_speech = false;
            }
        }
        self.broadcast_voice_session().await;
        self.voice_status_payload().await
    }

    pub(super) async fn voice_credential_status_request(&self) -> HostResult<Value> {
        let credentials = self.voice_credential_store().load().await?;
        Ok(json!({
            "geminiConfigured": credentials
                .gemini_token
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
            "openaiConfigured": credentials
                .openai_token
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
        }))
    }

    pub(super) async fn voice_credential_save_request(&self, payload: &Value) -> HostResult<Value> {
        let mut credentials = self.voice_credential_store().load().await?;
        if let Some(token) = optional_credential(payload, "geminiToken")? {
            credentials.gemini_token = token;
        }
        if let Some(token) = optional_credential(payload, "openaiToken")? {
            credentials.openai_token = token;
        }
        self.voice_credential_store().save(credentials).await?;
        self.voice_credential_status_request().await
    }

    pub(super) async fn voice_credential_clear_request(
        &self,
        payload: &Value,
    ) -> HostResult<Value> {
        let provider = payload.get("provider").and_then(Value::as_str);
        match provider {
            Some("gemini") => {
                let mut credentials = self.voice_credential_store().load().await?;
                credentials.gemini_token = None;
                self.voice_credential_store().save(credentials).await?;
            }
            Some("openai") => {
                let mut credentials = self.voice_credential_store().load().await?;
                credentials.openai_token = None;
                self.voice_credential_store().save(credentials).await?;
            }
            Some(other) => {
                return Err(HostError::format(format!(
                    "unknown voice credential provider: {other}"
                )));
            }
            None => self.voice_credential_store().delete().await?,
        }
        self.voice_credential_status_request().await
    }

    pub(super) async fn flush_voice_turns_if_ready(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() != Some(session_id) {
            return;
        }
        if self.voice.home_inject.is_some() {
            return;
        }
        if self.orchestration_delivery_in_flight.contains(session_id) {
            return;
        }
        if let Err(error) = self.flush_voice_turns().await {
            tracing::warn!("voice home turn flush failed: {error}");
            self.voice.last_error = Some(error.to_string());
        }
    }

    pub(super) async fn deliver_home_ready_queues(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() == Some(session_id) {
            self.voice.home_needs_fresh_ready = false;
        }
        let had_startup = self.home_has_pending_startup_prompt(session_id).await;
        self.deliver_pending_agent_prompt(session_id).await;
        if had_startup {
            return;
        }
        if self.voice.home_session_id.as_deref() == Some(session_id)
            && !self.voice.pending_user_turns.is_empty()
        {
            self.flush_voice_turns_if_ready(session_id).await;
            return;
        }
        self.deliver_pending_messages(session_id).await;
        if self.voice.home_session_id.as_deref() == Some(session_id) {
            self.flush_voice_turns_if_ready(session_id).await;
        }
    }

    async fn home_has_pending_startup_prompt(&self, session_id: &str) -> bool {
        let Some(session) = self.sessions.get(session_id) else {
            return false;
        };
        if session.initial_agent_prompt_delivered {
            return false;
        }
        let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&session.tab_id).await else {
            return false;
        };
        tab.payload
            .get("pendingAgentPrompt")
            .and_then(|pending| pending.get("prompt"))
            .and_then(Value::as_str)
            .is_some_and(|prompt| !prompt.is_empty())
    }

    pub(super) fn abandon_home_inject(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() != Some(session_id) {
            return;
        }
        if let Some(inject) = self.voice.home_inject.take() {
            for turn in inject.turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
        }
        self.voice.home_needs_fresh_ready = false;
        self.voice.home_session_id = None;
        self.voice.home_tab_id = None;
    }

    pub(super) fn finish_voice_home_inject(
        &mut self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
        error: Option<String>,
    ) {
        let Some(inject) = self.voice.home_inject.as_ref() else {
            return;
        };
        let current_instance = self.sessions.get(session_id).map(Session::instance_id);
        if self.voice.home_session_id.as_deref() != Some(session_id)
            || inject.session_instance_id != session_instance_id
            || inject.generation != generation
            || current_instance != Some(session_instance_id)
        {
            return;
        }
        let inject = self.voice.home_inject.take().expect("checked above");
        if let Some(message) = error {
            for turn in inject.turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
            self.voice.last_error = Some(message);
            return;
        }
        self.voice.home_needs_fresh_ready = true;
    }

    async fn ensure_voice_home(&mut self) -> HostResult<()> {
        let home = self
            .runtime_store
            .ensure_voice_home(&self.runtime_dir)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let created = home.created;
        let project_id = home.project.id.clone();
        self.voice.home = Some(home);
        if created {
            self.broadcast_workspaces_changed(Some(&project_id));
        }
        Ok(())
    }

    async fn ensure_home_agent(&mut self) -> HostResult<()> {
        self.ensure_voice_home().await?;
        if let Some(session_id) = self.voice.home_session_id.clone() {
            let running = self.sessions.get(&session_id).is_some_and(Session::running);
            if running && !self.voice.home_cli_exited {
                return Ok(());
            }
            self.abandon_home_inject(&session_id);
        }
        if self.voice.home_cli_exited {
            self.voice.home_cli_exited = false;
            self.retire_abandoned_home_sessions().await;
        } else if let Some((tab_id, session_id)) = self.find_running_home_session() {
            self.voice.home_tab_id = Some(tab_id);
            self.voice.home_session_id = Some(session_id);
            return Ok(());
        }
        let profile_id = self.resolve_home_profile_id().await?;
        let response = self
            .launch_agent_profile(
                None,
                &json!({
                    "workspaceId": VOICE_HOME_WORKSPACE_ID,
                    "profileId": profile_id,
                    "prompt": home_agent_startup_prompt(),
                }),
            )
            .await?;
        let tab = response
            .get("tab")
            .ok_or_else(|| HostError::state("voice home launch returned no tab"))?;
        let tab_id = tab
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::state("voice home launch returned no tab id"))?;
        let session_id = tab
            .get("payload")
            .and_then(|value| value.get("terminalSessionId"))
            .and_then(Value::as_str)
            .unwrap_or(tab_id)
            .to_string();
        self.voice.home_tab_id = Some(tab_id.to_string());
        self.voice.home_session_id = Some(session_id);
        Ok(())
    }

    fn find_running_home_session(&self) -> Option<(String, String)> {
        self.sessions.iter().find_map(|(session_id, session)| {
            if session.running() && is_voice_home_workspace_id(&session.workspace_id) {
                Some((session.tab_id.clone(), session_id.clone()))
            } else {
                None
            }
        })
    }

    async fn retire_abandoned_home_sessions(&mut self) {
        let mut tab_ids: Vec<String> = self
            .sessions
            .values()
            .filter(|session| is_voice_home_workspace_id(&session.workspace_id))
            .map(|session| session.tab_id.clone())
            .collect();
        tab_ids.sort();
        tab_ids.dedup();
        if tab_ids.is_empty() {
            return;
        }
        for tab_id in &tab_ids {
            self.terminate_sessions_for_tab(tab_id).await;
            if let Err(error) = self.runtime_store.remove_workspace_tab(tab_id).await {
                tracing::error!("failed to retire abandoned voice home tab {tab_id}: {error}");
            }
        }
        self.broadcast_workspace_tabs_changed(Some(VOICE_HOME_WORKSPACE_ID));
    }

    async fn resolve_home_profile_id(&self) -> HostResult<String> {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        if let Some(profile_id) = settings
            .home_agent_profile_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Ok(profile_id.to_string());
        }
        if let Some(profile_id) = self
            .runtime_store
            .default_agent_profile_id()
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            return Ok(profile_id);
        }
        let profiles = self
            .runtime_store
            .list_agent_profiles()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        profiles
            .into_iter()
            .next()
            .map(|profile| profile.id)
            .ok_or_else(|| {
                HostError::state("Create an agent profile before starting the voice home agent.")
            })
    }

    async fn accept_voice_turn(
        &mut self,
        text: String,
        payload: &Value,
        _from_realtime: bool,
    ) -> HostResult<Value> {
        if self.voice.phase == VoiceSessionPhase::Idle {
            return Err(HostError::state(
                "Start a voice session before sending a turn.",
            ));
        }
        let cancel_home = payload
            .get("cancelHome")
            .and_then(Value::as_bool)
            .unwrap_or_else(|| looks_like_home_cancel(&text));
        let cancelled = self.voice.interrupt_playback();
        if !cancelled.is_empty() {
            if let Some(handle) = self.voice.realtime.as_ref() {
                handle.send(RealtimeClientMessage::Interrupt);
            }
            self.broadcast_voice_owner(event(
                "voice.interrupt",
                json!({
                    "reason": "bargeIn",
                    "cancelHome": cancel_home,
                    "id": cancelled.first().map(|utterance| utterance.id),
                }),
            ));
        }
        self.voice.enqueue_user_turn(text.clone(), cancel_home);
        self.ensure_home_agent().await?;
        self.flush_voice_turns().await?;
        self.broadcast_voice_session().await;
        Ok(json!({
            "accepted": true,
            "text": text,
            "queuedTurnCount": self.voice.pending_user_turns.len(),
            "phase": self.voice.phase,
        }))
    }

    fn matches_speak_head(&self, utterance_id: Option<u64>) -> bool {
        match (utterance_id, self.voice.speak_queue.front()) {
            (Some(id), Some(head)) => head.id == id,
            _ => false,
        }
    }

    fn require_voice_capture_owner(&self, client_id: u64) -> HostResult<()> {
        match self.voice.capture_owner_client_id {
            Some(owner) if owner == client_id => Ok(()),
            Some(_) => Err(HostError::state(
                "Voice capture is already owned by another client. Stop that session first.",
            )),
            None => Err(HostError::state(
                "Start a voice session before sending audio.",
            )),
        }
    }

    async fn flush_voice_turns(&mut self) -> HostResult<()> {
        let Some(session_id) = self.voice.home_session_id.clone() else {
            return Ok(());
        };
        if self.voice.pending_user_turns.is_empty() {
            return Ok(());
        }
        if self.voice.home_interrupt_pending {
            self.voice.home_interrupt_pending = false;
            self.interrupt_home_agent(&session_id)?;
        }
        if self.voice.home_inject.is_some() {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if self.voice.home_needs_fresh_ready {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if self.orchestration_delivery_in_flight.contains(&session_id) {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if !self.agent_presence.is_injection_ready(&session_id) {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        let turns = self.voice.take_ready_turns();
        if turns.is_empty() {
            return Ok(());
        }
        let prompt = compose_home_turns(&turns);
        if let Err(error) = self.inject_home_prompt(&session_id, &prompt, turns) {
            return Err(error);
        }
        self.voice.phase = VoiceSessionPhase::Thinking;
        self.maybe_ack_while_thinking().await;
        Ok(())
    }

    async fn maybe_ack_while_thinking(&mut self) {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        if !settings.ack_while_thinking {
            return;
        }
        let ack = "On it.";
        let utterance = self.voice.enqueue_speak(ack.to_string());
        if let Some(handle) = self.voice.realtime.as_ref() {
            if self.voice.speak_queue.len() == 1 {
                self.voice.expecting_speech = true;
                handle.send(RealtimeClientMessage::Speak {
                    text: utterance.text.clone(),
                    utterance_id: Some(utterance.id),
                });
            }
        }
        self.broadcast_voice_owner(event(
            "voice.utterance",
            json!({
                "id": utterance.id,
                "text": utterance.text,
                "queued": self.voice.speak_queue.len(),
                "realtime": self.voice.realtime.is_some(),
            }),
        ));
        self.broadcast_voice_session().await;
    }

    fn interrupt_home_agent(&mut self, session_id: &str) -> HostResult<()> {
        let Some(agent_type) = self
            .agent_presence
            .agent_type(session_id)
            .map(str::to_string)
        else {
            return Ok(());
        };
        if let Some(adapter) = adapter_for(&agent_type) {
            self.queue_orchestration_control(session_id, adapter.interrupt_bytes)?;
        }
        Ok(())
    }

    fn inject_home_prompt(
        &mut self,
        session_id: &str,
        prompt: &str,
        turns: Vec<PendingVoiceTurn>,
    ) -> HostResult<()> {
        let bytes = build_agent_prompt_paste_bytes(prompt);
        let session = self.sessions.get_mut(session_id).ok_or_else(|| {
            HostError::state(format!("voice home terminal is not running: {session_id}"))
        })?;
        let session_instance_id = session.instance_id();
        self.voice.home_inject_generation = self.voice.home_inject_generation.saturating_add(1);
        let generation = self.voice.home_inject_generation;
        if let Err(error) = session.queue_write_deferred(
            PtyWriteCompletion::VoiceHomePrompt {
                session_instance_id,
                generation,
            },
            &bytes,
            Duration::from_millis(DEFERRED_ENTER_DELAY_MS),
            AGENT_PROMPT_SUBMIT,
        ) {
            for turn in turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
            return Err(error);
        }
        self.voice.home_inject = Some(super::voice_session::VoiceHomeInject {
            session_instance_id,
            generation,
            turns,
        });
        Ok(())
    }

    async fn voice_status_payload(&self) -> HostResult<Value> {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        let settings =
            serde_json::to_value(settings).map_err(|error| HostError::state(error.to_string()))?;
        Ok(self.voice.status_payload(settings))
    }

    async fn broadcast_voice_session(&mut self) {
        if let Ok(payload) = self.voice_status_payload().await {
            self.broadcast_authenticated(event("voice.session", payload));
        }
    }

    fn broadcast_voice_owner(&self, message: Value) {
        if let Some(client_id) = self.voice.capture_owner_client_id {
            self.client_write(client_id, message);
        }
    }

    fn voice_credential_store(&self) -> VoiceCredentialStore {
        VoiceCredentialStore::new(&self.runtime_dir, self.account_push.service.runtime_id())
    }
}

fn home_agent_startup_prompt() -> String {
    "You are Alera's global voice home agent. Wait for the next spoken turn. Speak to the human only with `alera voice speak --text \"...\"`. Keep those sentences short. Do not patch product code from this folder. Delegate with `alera orchestration delegate`.".to_string()
}

fn compose_home_turns(turns: &[PendingVoiceTurn]) -> String {
    let interrupted = turns.iter().any(|turn| turn.cancel_home);
    let body = turns
        .iter()
        .map(|turn| turn.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    if interrupted {
        format!(
            "The human interrupted you and did not hear the previous spoken message. Drop that oral plan.\n\n{body}"
        )
    } else {
        body
    }
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

fn decode_pcm(payload: &Value) -> HostResult<Vec<u8>> {
    let encoded = payload
        .get("audioBase64")
        .and_then(Value::as_str)
        .ok_or_else(|| HostError::format("audioBase64 is required."))?;
    use base64::Engine as _;
    let pcm = base64::engine::general_purpose::STANDARD
        .decode(encoded.trim())
        .map_err(|_| HostError::format("audioBase64 is not valid base64."))?;
    if pcm.len() % 2 != 0 {
        return Err(HostError::format("PCM audio must be 16-bit little-endian."));
    }
    Ok(pcm)
}

async fn transcribe_chained_job(
    pcm: Vec<u8>,
    runtime_dir: std::path::PathBuf,
    runtime_id: String,
    runtime_store: alera_core::runtime::RuntimeStore,
    credentials_store: VoiceCredentialStore,
    request_id: String,
) -> HostResult<String> {
    let wav = pcm16_to_wav(&pcm, 16_000);
    let settings = runtime_store
        .voice_settings()
        .await
        .unwrap_or_else(|_| RuntimeVoiceSettings::default());
    match settings.stt_provider {
        alera_core::runtime::RuntimeVoiceSttProvider::GeminiTranscribeLive => {
            let credentials = credentials_store.load().await?;
            let token = credentials
                .gemini_token
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| {
                    HostError::state("A Gemini API key is required for Gemini transcribe.")
                })?;
            transcribe_gemini(&wav, token).await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::LocalWhisper => {
            let model_id = dictation_model_id(&runtime_store).await;
            super::ai_dictation_requests::transcribe_wav_bytes_with_model_id(
                &wav,
                &runtime_dir,
                &model_id,
                request_id,
            )
            .await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::OpenAiCompatible => {
            transcribe_openai_compatible(&wav, &runtime_dir, &runtime_id, &runtime_store).await
        }
        alera_core::runtime::RuntimeVoiceSttProvider::CodexRealtime => Err(HostError::state(
            "Codex realtime speech-to-text is not available from a mobile voice turn. Use desktop chained STT or a realtime pipeline.",
        )),
    }
}

async fn dictation_model_id(runtime_store: &alera_core::runtime::RuntimeStore) -> String {
    runtime_store
        .configuration_settings()
        .await
        .ok()
        .and_then(|settings| {
            settings
                .get("aiDictation")
                .and_then(|section| section.get("localModelId"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
        })
        .unwrap_or_else(|| "whisper-base".to_string())
}

async fn transcribe_openai_compatible(
    wav: &[u8],
    runtime_dir: &std::path::Path,
    runtime_id: &str,
    runtime_store: &alera_core::runtime::RuntimeStore,
) -> HostResult<String> {
    let settings = runtime_store
        .configuration_settings()
        .await
        .unwrap_or(Value::Null);
    let section = settings.get("aiDictation");
    let base_url = section
        .and_then(|value| value.get("remoteBaseUrl"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("https://api.openai.com/v1");
    let model = section
        .and_then(|value| value.get("remoteModel"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("gpt-4o-mini-transcribe");
    let origin = super::ai_dictation_openai::provider_origin(base_url)?;
    let token = token_for_dictation_origin(runtime_dir, runtime_id, &origin).await?;
    let path = std::env::temp_dir().join(format!("alera-voice-stt-{}.wav", uuid::Uuid::new_v4()));
    struct TempWav(std::path::PathBuf);
    impl Drop for TempWav {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
        }
    }
    let wav = wav.to_vec();
    let write_path = path.clone();
    let _temp = tokio::task::spawn_blocking(move || {
        use std::io::Write as _;
        let temp = TempWav(write_path.clone());
        let mut file = alera_core::runtime::create_private_runtime_file(&write_path)?;
        file.write_all(&wav)?;
        file.sync_all()?;
        Ok::<TempWav, std::io::Error>(temp)
    })
    .await
    .map_err(|error| HostError::state(format!("audio could not be stored: {error}")))?
    .map_err(|error| HostError::state(format!("audio could not be stored: {error}")))?;
    let result = super::ai_dictation_openai::transcribe(OpenAiDictationRequest {
        audio_path: &path,
        base_url,
        model,
        token: token.as_deref(),
        language: None,
        prompt: None,
        timeout: Duration::from_secs(60),
    })
    .await;
    let decoded = result?;
    Ok(decoded
        .get("text")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string())
}

async fn token_for_dictation_origin(
    runtime_dir: &std::path::Path,
    runtime_id: &str,
    origin: &str,
) -> HostResult<Option<String>> {
    let store = AiDictationCredentialStore::new(runtime_dir, runtime_id);
    match store.load().await? {
        Some(credential) if credential.origin.as_deref() == Some(origin) => {
            Ok(Some(credential.token))
        }
        Some(_) => Err(HostError::state(
            "The saved AI Dictation token belongs to a different API origin. Replace or remove it before transcribing.",
        )),
        None => Err(HostError::state(
            "Save an OpenAI-compatible AI Dictation token before using that speech-to-text engine.",
        )),
    }
}

async fn synthesize_job(
    text: String,
    provider: Option<String>,
    voice: Option<String>,
    runtime_store: alera_core::runtime::RuntimeStore,
    credentials_store: VoiceCredentialStore,
) -> HostResult<Value> {
    let settings = runtime_store
        .voice_settings()
        .await
        .unwrap_or_else(|_| RuntimeVoiceSettings::default());
    let credentials = credentials_store.load().await?;
    let provider = provider.unwrap_or_else(|| match settings.tts_provider {
        alera_core::runtime::RuntimeVoiceTtsProvider::OpenAiTts => "openAiTts".to_string(),
        alera_core::runtime::RuntimeVoiceTtsProvider::GeminiFlashTts => {
            "geminiFlashTts".to_string()
        }
    });
    let audio = synthesize(SynthesizeRequest {
        text: &text,
        gemini_token: credentials.gemini_token.as_deref(),
        openai_token: credentials.openai_token.as_deref(),
        tts_provider: &provider,
        tts_voice: voice.as_deref().or(settings.tts_voice.as_deref()),
    })
    .await?;
    use base64::Engine as _;
    Ok(json!({
        "text": text,
        "audioBase64": base64::engine::general_purpose::STANDARD.encode(audio),
        "mimeType": "audio/wav",
    }))
}

fn optional_credential(payload: &Value, key: &str) -> HostResult<Option<Option<String>>> {
    match payload.get(key) {
        None => Ok(None),
        Some(Value::Null) => Ok(Some(None)),
        Some(Value::String(value)) => {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                Ok(Some(None))
            } else {
                Ok(Some(Some(trimmed.to_string())))
            }
        }
        Some(_) => Err(HostError::format(format!("{key} must be a string."))),
    }
}

#[cfg(test)]
mod tests {
    use super::super::voice_session::VoiceSessionState;
    use super::{compose_home_turns, PendingVoiceTurn};

    #[test]
    fn interrupt_clears_the_speak_queue() {
        let mut session = VoiceSessionState::default();
        session.enqueue_speak("one".into());
        session.enqueue_speak("two".into());
        let drained = session.interrupt_playback();
        assert_eq!(drained.len(), 2);
        assert!(session.speak_queue.is_empty());
        assert!(!session.speaking);
    }

    #[test]
    fn interrupt_head_keeps_later_speak_items() {
        let mut session = VoiceSessionState::default();
        let first = session.enqueue_speak("one".into());
        let second = session.enqueue_speak("two".into());
        let drained = session.interrupt_playback_head(Some(first.id));
        assert_eq!(drained.len(), 1);
        assert_eq!(
            session.speak_queue.front().map(|item| item.id),
            Some(second.id)
        );
    }

    #[test]
    fn composed_turns_mark_an_interrupt() {
        let prompt = compose_home_turns(&[PendingVoiceTurn {
            text: "stop that".into(),
            cancel_home: true,
        }]);
        assert!(prompt.contains("interrupted"));
        assert!(prompt.contains("stop that"));
    }

    #[test]
    fn pcm_payload_must_be_even_base64() {
        assert!(super::decode_pcm(&serde_json::json!({ "audioBase64": "AQ" })).is_err());
        assert_eq!(
            super::decode_pcm(&serde_json::json!({ "audioBase64": "AAA=" })).unwrap(),
            vec![0, 0]
        );
    }

    #[test]
    fn wav_header_uses_the_pcm_length() {
        let wav = super::pcm16_to_wav(&[0, 0, 0, 0], 16_000);
        assert_eq!(&wav[0..4], b"RIFF");
        assert_eq!(&wav[8..12], b"WAVE");
        assert_eq!(u32::from_le_bytes(wav[40..44].try_into().unwrap()), 4);
    }

    #[test]
    fn late_delta_plus_cumulative_final_dispatches_only_the_suffix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and run tests");
        session.merge_pending_transcript("open the repo and run tests");
        let text = session.take_pending_transcript().unwrap();
        let previous = session.last_flushed_transcript.as_deref().unwrap();
        assert!(super::super::voice_session::is_transcript_prefix(
            previous, &text
        ));
        assert_eq!(text[previous.len()..].trim(), "and run tests");
        let first =
            super::super::voice_session::transcript_dispatch(Some(previous), &text).unwrap();
        assert_eq!(first.1, "and run tests");
        assert_eq!(first.0, "open the repo and run tests");
        assert!(super::super::voice_session::transcript_dispatch(
            Some(first.0.as_str()),
            "open the repo and run tests"
        )
        .is_none());
    }

    #[test]
    fn failed_inject_requeues_turns() {
        let mut session = VoiceSessionState::default();
        session.enqueue_user_turn("hello".into(), false);
        let turns = session.take_ready_turns();
        assert!(session.pending_user_turns.is_empty());
        for turn in turns.into_iter().rev() {
            session.pending_user_turns.push_front(turn);
        }
        assert_eq!(session.pending_user_turns.len(), 1);
        assert_eq!(session.pending_user_turns[0].text, "hello");
    }
}
