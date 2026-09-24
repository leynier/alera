use std::collections::{HashMap, VecDeque};

use tokio::sync::oneshot;

use alera_core::runtime::VoiceHomeEnsureResult;
use serde::Serialize;
use serde_json::{json, Value};

use super::voice_realtime_session::VoiceRealtimeHandle;
use super::voice_transcript::merge_pending_transcript;
use crate::terminal_host::host_error::{HostError, HostResult};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum VoiceSessionPhase {
    Idle,
    Listening,
    Thinking,
    Speaking,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct VoiceUtterance {
    pub id: u64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct PendingVoiceTurn {
    pub text: String,
    pub cancel_home: bool,
}

pub(super) struct CompletedVoiceTurn {
    pub client_id: u64,
    pub request_id: i64,
    pub from_realtime: bool,
    pub cancel_home: Option<bool>,
    pub result: HostResult<String>,
}

pub(super) struct VoiceHomeInject {
    pub session_instance_id: u64,
    pub generation: u64,
    pub turns: Vec<PendingVoiceTurn>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct HeldGeminiActivity {
    pub pcm: Vec<u8>,
    pub ended: bool,
}

pub(super) struct VoiceSessionState {
    pub home: Option<VoiceHomeEnsureResult>,
    pub home_tab_id: Option<String>,
    pub home_session_id: Option<String>,
    pub home_cli_exited: bool,
    pub phase: VoiceSessionPhase,
    pub speaking: bool,
    pub speak_queue: VecDeque<VoiceUtterance>,
    pub pending_user_turns: VecDeque<PendingVoiceTurn>,
    pub last_spoken: Option<String>,
    pub last_error: Option<String>,
    pub realtime: Option<VoiceRealtimeHandle>,
    pub realtime_generation: u64,
    /// Reconnects scheduled since the realtime socket last finished setup.
    pub realtime_reconnect_attempts: u32,
    pub session_generation: u64,
    pub capture_owner_client_id: Option<u64>,
    pub pending_transcript: String,
    pub expecting_speech: bool,
    pub next_job_id: u64,
    pub next_utterance_id: u64,
    pub in_flight_turn_jobs: VecDeque<u64>,
    pub completed_turn_jobs: std::collections::HashMap<u64, CompletedVoiceTurn>,
    pub home_inject: Option<VoiceHomeInject>,
    pub home_inject_generation: u64,
    pub home_needs_fresh_ready: bool,
    pub home_interrupt_pending: bool,
    pub gemini_transcript_token: u64,
    pub gemini_settling: bool,
    pub gemini_activity_ended: bool,
    pub gemini_transcript_final: bool,
    pub last_flushed_transcript: Option<String>,
    pub openai_item_id: Option<String>,
    pub openai_committed_items: VecDeque<String>,
    pub openai_completed_transcripts: HashMap<String, String>,
    pub gemini_held_activities: VecDeque<HeldGeminiActivity>,
    pub realtime_kind: Option<super::voice_realtime::VoiceRealtimeKind>,
    job_cancels: Vec<oneshot::Sender<()>>,
}

impl Default for VoiceSessionState {
    fn default() -> Self {
        Self {
            home: None,
            home_tab_id: None,
            home_session_id: None,
            home_cli_exited: false,
            phase: VoiceSessionPhase::Idle,
            speaking: false,
            speak_queue: VecDeque::new(),
            pending_user_turns: VecDeque::new(),
            last_spoken: None,
            last_error: None,
            realtime: None,
            realtime_generation: 0,
            realtime_reconnect_attempts: 0,
            session_generation: 0,
            capture_owner_client_id: None,
            pending_transcript: String::new(),
            expecting_speech: false,
            next_job_id: 0,
            next_utterance_id: 0,
            in_flight_turn_jobs: VecDeque::new(),
            completed_turn_jobs: std::collections::HashMap::new(),
            home_inject: None,
            home_inject_generation: 0,
            home_needs_fresh_ready: false,
            home_interrupt_pending: false,
            gemini_transcript_token: 0,
            gemini_settling: false,
            gemini_activity_ended: true,
            gemini_transcript_final: false,
            last_flushed_transcript: None,
            openai_item_id: None,
            openai_committed_items: VecDeque::new(),
            openai_completed_transcripts: HashMap::new(),
            gemini_held_activities: VecDeque::new(),
            realtime_kind: None,
            job_cancels: Vec::new(),
        }
    }
}

impl VoiceSessionState {
    pub(super) fn status_payload(&self, settings: Value) -> Value {
        json!({
            "homeWorkspaceId": self.home.as_ref().map(|home| home.workspace.id.clone()),
            "homeProjectId": self.home.as_ref().map(|home| home.project.id.clone()),
            "homeDir": self.home.as_ref().map(|home| home.home_dir.display().to_string()),
            "homeTabId": self.home_tab_id,
            "homeSessionId": self.home_session_id,
            "phase": self.phase,
            "speaking": self.speaking,
            "queuedSpeakCount": self.speak_queue.len(),
            "queuedTurnCount": self.pending_user_turns.len(),
            "lastSpoken": self.last_spoken,
            "lastError": self.last_error,
            "realtime": self.realtime.is_some(),
            "sessionGeneration": self.session_generation,
            "captureOwnerClientId": self.capture_owner_client_id,
            "settings": settings,
        })
    }

    pub(super) fn claim_capture(&mut self, client_id: u64) -> HostResult<u64> {
        if let Some(owner) = self.capture_owner_client_id {
            if owner != client_id {
                return Err(HostError::state(
                    "Voice capture is already owned by another client. Stop that session first.",
                ));
            }
            return Ok(self.session_generation);
        }
        self.session_generation = self.session_generation.saturating_add(1);
        self.capture_owner_client_id = Some(client_id);
        Ok(self.session_generation)
    }

    pub(super) fn release_capture(&mut self, client_id: Option<u64>) -> bool {
        match (self.capture_owner_client_id, client_id) {
            (Some(owner), Some(id)) if owner != id => false,
            (None, _) => false,
            _ => {
                self.capture_owner_client_id = None;
                true
            }
        }
    }

    pub(super) fn next_job_id(&mut self) -> u64 {
        self.next_job_id = self.next_job_id.saturating_add(1);
        self.next_job_id
    }

    pub(super) fn push_job_cancel(&mut self) -> oneshot::Receiver<()> {
        self.job_cancels.retain(|sender| !sender.is_closed());
        let (tx, rx) = oneshot::channel();
        self.job_cancels.push(tx);
        rx
    }

    pub(super) fn cancel_jobs(&mut self) {
        for sender in self.job_cancels.drain(..) {
            let _ = sender.send(());
        }
    }

    pub(super) fn enqueue_speak(&mut self, text: String) -> VoiceUtterance {
        self.next_utterance_id = self.next_utterance_id.saturating_add(1);
        let utterance = VoiceUtterance {
            id: self.next_utterance_id,
            text,
        };
        self.speak_queue.push_back(utterance.clone());
        self.speaking = true;
        self.phase = VoiceSessionPhase::Speaking;
        utterance
    }

    pub(super) fn finish_speak(&mut self, text: String, id: Option<u64>) -> bool {
        if !self.pop_matching_speak_head(&text, id) {
            return false;
        }
        self.last_spoken = Some(text);
        self.after_speak_head_retired();
        true
    }

    pub(super) fn fail_speak(&mut self, text: &str, id: Option<u64>, error: String) -> bool {
        if !self.pop_matching_speak_head(text, id) {
            return false;
        }
        self.last_error = Some(error);
        self.after_speak_head_retired();
        true
    }

    fn pop_matching_speak_head(&mut self, text: &str, id: Option<u64>) -> bool {
        let matches_head = match (self.speak_queue.front(), id) {
            (Some(head), Some(id)) => head.id == id,
            (Some(head), None) => head.text == text,
            (None, _) => false,
        };
        if !matches_head {
            return false;
        }
        self.speak_queue.pop_front();
        true
    }

    fn after_speak_head_retired(&mut self) {
        if self.speak_queue.is_empty() {
            self.speaking = false;
            self.phase = if self.pending_user_turns.is_empty() {
                VoiceSessionPhase::Listening
            } else {
                VoiceSessionPhase::Thinking
            };
        }
    }

    pub(super) fn refresh_speak_head_identity(&mut self) -> Option<(u64, VoiceUtterance)> {
        let head = self.speak_queue.front_mut()?;
        let old_id = head.id;
        self.next_utterance_id = self.next_utterance_id.saturating_add(1);
        head.id = self.next_utterance_id;
        Some((old_id, head.clone()))
    }

    pub(super) fn interrupt_playback(&mut self) -> Vec<VoiceUtterance> {
        self.speaking = false;
        self.expecting_speech = false;
        self.speak_queue.drain(..).collect()
    }

    pub(super) fn interrupt_playback_head(
        &mut self,
        utterance_id: Option<u64>,
    ) -> Vec<VoiceUtterance> {
        let Some(head) = self.speak_queue.front() else {
            self.speaking = false;
            self.expecting_speech = false;
            return Vec::new();
        };
        if utterance_id != Some(head.id) {
            return Vec::new();
        }
        let cancelled = self.speak_queue.pop_front().into_iter().collect::<Vec<_>>();
        self.expecting_speech = false;
        if self.speak_queue.is_empty() {
            self.speaking = false;
            self.phase = if self.pending_user_turns.is_empty() {
                VoiceSessionPhase::Listening
            } else {
                VoiceSessionPhase::Thinking
            };
        }
        cancelled
    }

    pub(super) fn take_pending_transcript(&mut self) -> Option<String> {
        let text = std::mem::take(&mut self.pending_transcript);
        let trimmed = text.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    }

    pub(super) fn merge_pending_transcript(&mut self, incoming: &str) {
        self.pending_transcript = merge_pending_transcript(
            self.last_flushed_transcript.as_deref().unwrap_or(""),
            &self.pending_transcript,
            incoming,
        );
    }

    pub(super) fn reset_gemini_utterance(&mut self) {
        self.gemini_transcript_token = self.gemini_transcript_token.saturating_add(1);
        self.gemini_settling = false;
        self.gemini_activity_ended = false;
        self.gemini_transcript_final = false;
        self.pending_transcript.clear();
        self.last_flushed_transcript = None;
        self.gemini_held_activities.clear();
    }

    pub(super) fn holding_gemini_activity(&self) -> bool {
        !self.gemini_held_activities.is_empty()
            || (!self.pending_transcript.trim().is_empty() || self.gemini_settling)
    }

    pub(super) fn hold_gemini_activity_start(&mut self) {
        self.gemini_held_activities.push_back(HeldGeminiActivity {
            pcm: Vec::new(),
            ended: false,
        });
    }

    pub(super) fn hold_gemini_activity_audio(&mut self, pcm: &[u8]) {
        if let Some(activity) = self.gemini_held_activities.back_mut() {
            activity.pcm.extend_from_slice(pcm);
        } else {
            self.gemini_held_activities.push_back(HeldGeminiActivity {
                pcm: pcm.to_vec(),
                ended: false,
            });
        }
    }

    pub(super) fn hold_gemini_activity_end(&mut self) {
        if let Some(activity) = self.gemini_held_activities.back_mut() {
            activity.ended = true;
        }
    }

    pub(super) fn reset_openai_input_order(&mut self) {
        self.openai_item_id = None;
        self.openai_committed_items.clear();
        self.openai_completed_transcripts.clear();
        self.last_flushed_transcript = None;
        self.pending_transcript.clear();
    }

    pub(super) fn stop_realtime(&mut self) {
        self.realtime_generation = self.realtime_generation.saturating_add(1);
        self.realtime_reconnect_attempts = 0;
        if let Some(handle) = self.realtime.take() {
            handle.abort();
        }
        self.pending_transcript.clear();
        self.expecting_speech = false;
        self.realtime_kind = None;
        self.gemini_held_activities.clear();
        self.reset_openai_input_order();
        self.gemini_settling = false;
        self.gemini_transcript_final = false;
        self.gemini_activity_ended = false;
    }

    pub(super) fn enqueue_user_turn(&mut self, text: String, cancel_home: bool) {
        if cancel_home {
            self.home_interrupt_pending = true;
        }
        self.pending_user_turns
            .push_back(PendingVoiceTurn { text, cancel_home });
        if self.phase != VoiceSessionPhase::Speaking {
            self.phase = VoiceSessionPhase::Thinking;
        }
    }

    pub(super) fn take_ready_turns(&mut self) -> Vec<PendingVoiceTurn> {
        self.pending_user_turns.drain(..).collect()
    }
}

#[cfg(test)]
#[path = "voice_session_tests.rs"]
mod tests;
