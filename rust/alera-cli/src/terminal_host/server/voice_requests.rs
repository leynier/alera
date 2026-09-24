//! Voice session RPCs: lifecycle, capture ownership, realtime audio input, and status.

use alera_core::runtime::RuntimeVoiceSettings;
use serde_json::{json, Value};

use super::host_service_requests::required_non_blank;
use super::voice_realtime::{looks_like_home_cancel, RealtimeClientMessage};
use super::voice_session::VoiceSessionPhase;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::error_response;
use crate::terminal_host::protocol::event;

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
            self.voice.realtime_reconnect_attempts = 0;
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

    pub(super) async fn stop_voice_session(&mut self, reason: &str) -> HostResult<Value> {
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

    pub(super) async fn accept_voice_turn(
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

    pub(super) fn matches_speak_head(&self, utterance_id: Option<u64>) -> bool {
        match (utterance_id, self.voice.speak_queue.front()) {
            (Some(id), Some(head)) => head.id == id,
            _ => false,
        }
    }

    pub(super) fn require_voice_capture_owner(&self, client_id: u64) -> HostResult<()> {
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

    pub(super) async fn voice_status_payload(&self) -> HostResult<Value> {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        let settings =
            serde_json::to_value(settings).map_err(|error| HostError::state(error.to_string()))?;
        Ok(self.voice.status_payload(settings))
    }

    pub(super) async fn broadcast_voice_session(&mut self) {
        if let Ok(payload) = self.voice_status_payload().await {
            self.broadcast_authenticated(event("voice.session", payload));
        }
    }

    pub(super) fn broadcast_voice_owner(&self, message: Value) {
        if let Some(client_id) = self.voice.capture_owner_client_id {
            self.client_write(client_id, message);
        }
    }
}

pub(super) fn decode_pcm(payload: &Value) -> HostResult<Vec<u8>> {
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
