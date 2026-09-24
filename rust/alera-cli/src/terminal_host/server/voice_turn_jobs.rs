//! Deferred chained STT turn and TTS synthesize jobs and their completion.

use serde_json::{json, Value};

use super::host_service_requests::required_non_blank;
use super::server_command::ServerCommand;
use super::voice_chained_jobs::{synthesize_job, transcribe_chained_job};
use super::voice_requests::decode_pcm;
use super::voice_session::VoiceSessionPhase;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

impl ServerActor {
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

    #[allow(clippy::too_many_arguments)]
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

    pub(super) async fn flush_completed_voice_turns(&mut self) {
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

    pub(super) async fn deliver_voice_turn_result(
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
}
