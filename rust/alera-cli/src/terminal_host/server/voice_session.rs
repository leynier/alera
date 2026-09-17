use std::collections::{HashMap, VecDeque};

use tokio::sync::oneshot;

use alera_core::runtime::VoiceHomeEnsureResult;
use serde::Serialize;
use serde_json::{json, Value};

use super::voice_realtime_session::VoiceRealtimeHandle;
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
        let Some(head) = self.speak_queue.front_mut() else {
            return None;
        };
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

pub(super) fn merge_pending_transcript(flushed: &str, pending: &str, incoming: &str) -> String {
    let incoming = normalize_transcript(incoming);
    let flushed = normalize_transcript(flushed);
    let pending = normalize_transcript(pending);
    if incoming.is_empty() {
        return pending;
    }
    if is_transcript_prefix(&incoming, &flushed) && incoming != flushed {
        return pending;
    }
    if incoming == flushed {
        return pending;
    }
    if !pending.is_empty() && is_transcript_prefix(&incoming, &pending) && incoming != pending {
        return pending;
    }
    if !flushed.is_empty() && is_transcript_prefix(&flushed, &incoming) {
        return incoming;
    }
    if pending.is_empty() {
        return if flushed.is_empty() {
            incoming
        } else {
            join_transcript(&flushed, &incoming)
        };
    }
    let pending_already_includes_flushed =
        flushed.is_empty() || is_transcript_prefix(&flushed, &pending);
    let full = if pending_already_includes_flushed {
        pending.clone()
    } else {
        join_transcript(&flushed, &pending)
    };
    if is_transcript_prefix(&full, &incoming) {
        return incoming;
    }
    if is_transcript_prefix(&incoming, &full) {
        return pending;
    }
    if is_transcript_prefix(&pending, &incoming) {
        return if pending_already_includes_flushed {
            incoming
        } else {
            join_transcript(&flushed, &incoming)
        };
    }
    if is_transcript_prefix(&incoming, &pending) {
        return pending;
    }
    if pending_already_includes_flushed {
        join_transcript(&pending, &incoming)
    } else {
        join_transcript(&full, &incoming)
    }
}

pub(super) fn transcript_dispatch(
    flushed: Option<&str>,
    pending: &str,
) -> Option<(String, String)> {
    let pending = normalize_transcript(pending);
    if pending.is_empty() {
        return None;
    }
    let flushed = flushed.map(normalize_transcript).unwrap_or_default();
    if pending == flushed {
        return None;
    }
    if !flushed.is_empty() && is_transcript_prefix(&pending, &flushed) && pending != flushed {
        return None;
    }
    if !flushed.is_empty() && is_transcript_prefix(&flushed, &pending) {
        let extra = pending[flushed.len()..].trim().to_string();
        if extra.is_empty() {
            return None;
        }
        return Some((pending, extra));
    }
    Some((join_transcript(&flushed, &pending), pending))
}

fn normalize_transcript(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn join_transcript(left: &str, right: &str) -> String {
    match (left.is_empty(), right.is_empty()) {
        (true, true) => String::new(),
        (true, false) => right.to_string(),
        (false, true) => left.to_string(),
        (false, false) => format!("{left} {right}"),
    }
}

pub(super) fn is_transcript_prefix(prefix: &str, full: &str) -> bool {
    if prefix.is_empty() || full == prefix {
        return true;
    }
    full.starts_with(prefix) && full[prefix.len()..].starts_with(' ')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn second_client_cannot_take_capture() {
        let mut session = VoiceSessionState::default();
        assert_eq!(session.claim_capture(1).unwrap(), 1);
        assert!(session.claim_capture(2).is_err());
        assert!(!session.release_capture(Some(2)));
        assert!(session.release_capture(Some(1)));
        assert!(session.capture_owner_client_id.is_none());
    }

    #[test]
    fn stop_realtime_invalidates_generation() {
        let mut session = VoiceSessionState::default();
        let before = session.realtime_generation;
        session.stop_realtime();
        assert_eq!(session.realtime_generation, before.saturating_add(1));
        assert!(session.realtime.is_none());
        assert!(session.realtime_kind.is_none());
        let after_stop = session.realtime_generation;
        session.stop_realtime();
        assert_eq!(session.realtime_generation, after_stop.saturating_add(1));
    }

    #[test]
    fn refresh_speak_head_identity_keeps_text_and_later_items() {
        let mut session = VoiceSessionState::default();
        let first = session.enqueue_speak("one".into());
        let second = session.enqueue_speak("two".into());
        let refreshed = session.refresh_speak_head_identity().unwrap();
        assert_eq!(refreshed.0, first.id);
        assert_ne!(refreshed.1.id, first.id);
        assert_eq!(refreshed.1.text, "one");
        assert_eq!(
            session.speak_queue.front().map(|item| item.id),
            Some(refreshed.1.id)
        );
        assert_eq!(
            session.speak_queue.back().map(|item| item.id),
            Some(second.id)
        );
        assert!(session.refresh_speak_head_identity().is_some());
        session.interrupt_playback();
        assert!(session.refresh_speak_head_identity().is_none());
    }

    #[test]
    fn fail_speak_retires_head_without_updating_last_spoken() {
        let mut session = VoiceSessionState::default();
        session.enqueue_speak("A".into());
        session.enqueue_speak("B".into());
        assert!(session.fail_speak("A", Some(1), "playback failed".into()));
        assert_eq!(session.last_spoken, None);
        assert_eq!(session.last_error.as_deref(), Some("playback failed"));
        assert_eq!(
            session.speak_queue.front().map(|item| item.text.as_str()),
            Some("B")
        );
        assert!(session.finish_speak("B".into(), Some(2)));
        assert_eq!(session.last_spoken.as_deref(), Some("B"));
        assert!(session.speak_queue.is_empty());
    }

    #[test]
    fn finish_speak_pops_only_the_matching_head() {
        let mut session = VoiceSessionState::default();
        let first = session.enqueue_speak("On it.".into());
        let _second = session.enqueue_speak("Done.".into());
        let third = session.enqueue_speak("On it.".into());
        assert!(session.finish_speak(first.text.clone(), Some(first.id)));
        assert_eq!(session.speak_queue.len(), 2);
        assert_eq!(
            session.speak_queue.front().map(|item| item.id),
            Some(third.id - 1)
        );
        assert!(!session.finish_speak("On it.".into(), Some(first.id)));
        assert_eq!(session.speak_queue.len(), 2);
    }

    #[test]
    fn interrupt_playback_head_keeps_later_utterances() {
        let mut session = VoiceSessionState::default();
        let first = session.enqueue_speak("one".into());
        let second = session.enqueue_speak("two".into());
        let cancelled = session.interrupt_playback_head(Some(first.id));
        assert_eq!(cancelled.len(), 1);
        assert_eq!(cancelled[0].id, first.id);
        assert_eq!(session.speak_queue.len(), 1);
        assert_eq!(
            session.speak_queue.front().map(|item| item.id),
            Some(second.id)
        );
        assert!(session.speaking);
        assert!(!session.expecting_speech);
        assert!(session.interrupt_playback_head(Some(first.id)).is_empty());
        assert_eq!(session.speak_queue.len(), 1);
    }

    #[test]
    fn late_delta_plus_cumulative_final_keeps_dispatched_prefix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and run tests");
        session.merge_pending_transcript("open the repo and run tests");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
        let extra = session
            .pending_transcript
            .strip_prefix(session.last_flushed_transcript.as_deref().unwrap())
            .unwrap()
            .trim();
        assert_eq!(extra, "and run tests");
    }

    #[test]
    fn shorter_late_prefix_does_not_replace_pending_suffix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and run tests");
        session.merge_pending_transcript("open the");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
    }

    #[test]
    fn duplicate_flushed_prefix_keeps_pending_suffix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and run tests");
        session.merge_pending_transcript("open the repo");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
        assert_eq!(
            transcript_dispatch(
                session.last_flushed_transcript.as_deref(),
                &session.pending_transcript,
            )
            .unwrap()
            .1,
            "and run tests"
        );
    }

    #[test]
    fn settle_then_cumulative_final_extends_dispatched_prefix() {
        let flushed = Some("open the repo");
        let first = transcript_dispatch(flushed, "and run tests").unwrap();
        assert_eq!(first.0, "open the repo and run tests");
        assert_eq!(first.1, "and run tests");
        let second = transcript_dispatch(Some(first.0.as_str()), "open the repo and run tests");
        assert!(second.is_none());
    }

    #[test]
    fn cumulative_then_delta_does_not_replay_flushed_prefix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("open the repo and run");
        session.merge_pending_transcript("tests");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
        let dispatch = transcript_dispatch(
            session.last_flushed_transcript.as_deref(),
            &session.pending_transcript,
        )
        .unwrap();
        assert_eq!(dispatch.1, "and run tests");
    }

    #[test]
    fn shorter_than_pending_cumulative_keeps_later_words() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and run tests");
        session.merge_pending_transcript("open the repo and run");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
        assert_eq!(
            transcript_dispatch(
                session.last_flushed_transcript.as_deref(),
                &session.pending_transcript,
            )
            .unwrap()
            .1,
            "and run tests"
        );
    }

    #[test]
    fn held_gemini_activity_keeps_pending_until_flush() {
        let mut session = VoiceSessionState::default();
        session.pending_transcript = "open the repo".into();
        session.gemini_settling = true;
        session.hold_gemini_activity_start();
        session.hold_gemini_activity_audio(&[1, 2, 3, 4]);
        session.hold_gemini_activity_end();
        session.hold_gemini_activity_start();
        session.hold_gemini_activity_audio(&[5, 6]);
        assert_eq!(session.gemini_held_activities.len(), 2);
        assert!(session.gemini_held_activities[0].ended);
        assert!(!session.gemini_held_activities[1].ended);
        assert_eq!(session.gemini_held_activities[0].pcm, vec![1, 2, 3, 4]);
        assert_eq!(session.gemini_held_activities[1].pcm, vec![5, 6]);
        session.reset_gemini_utterance();
        assert!(session.pending_transcript.is_empty());
        assert!(!session.gemini_settling);
        assert!(session.gemini_held_activities.is_empty());
        assert!(!session.gemini_transcript_final);
    }

    #[test]
    fn empty_gemini_settle_keeps_held_next_activity() {
        let mut session = VoiceSessionState::default();
        session.gemini_activity_ended = true;
        session.gemini_settling = true;
        session.hold_gemini_activity_start();
        session.hold_gemini_activity_audio(&[1, 2]);
        session.hold_gemini_activity_end();
        assert!(session.pending_transcript.trim().is_empty());
        assert!(session.holding_gemini_activity());
        assert_eq!(session.gemini_held_activities.len(), 1);
        assert!(session.gemini_held_activities[0].ended);
        assert!(session.gemini_settling);
    }

    #[test]
    fn empty_gemini_settle_keeps_reservation_for_later_activity() {
        let mut session = VoiceSessionState::default();
        session.gemini_activity_ended = true;
        session.gemini_settling = true;
        assert!(session.pending_transcript.trim().is_empty());
        assert!(session.holding_gemini_activity());
        session.hold_gemini_activity_start();
        session.hold_gemini_activity_audio(&[9, 8]);
        session.hold_gemini_activity_end();
        assert!(session.holding_gemini_activity());
        assert_eq!(session.gemini_held_activities.len(), 1);
        assert!(session.gemini_settling);
    }

    #[test]
    fn early_gemini_final_stays_until_reset() {
        let mut session = VoiceSessionState::default();
        session.gemini_transcript_final = true;
        assert!(session.gemini_transcript_final);
        session.reset_gemini_utterance();
        assert!(!session.gemini_transcript_final);
        session.gemini_transcript_final = true;
        session.stop_realtime();
        assert!(!session.gemini_transcript_final);
    }

    #[test]
    fn openai_item_change_keeps_full_second_transcript() {
        let mut session = VoiceSessionState::default();
        session.openai_item_id = Some("a".into());
        session.last_flushed_transcript = Some("yes".into());
        session.pending_transcript = "yes".into();
        session.openai_item_id = Some("b".into());
        session.last_flushed_transcript = None;
        session.pending_transcript = "yes".into();
        let dispatch = transcript_dispatch(
            session.last_flushed_transcript.as_deref(),
            &session.pending_transcript,
        )
        .unwrap();
        assert_eq!(dispatch.1, "yes");
    }

    #[test]
    fn successive_suffix_deltas_do_not_replay_flushed_prefix() {
        let mut session = VoiceSessionState::default();
        session.last_flushed_transcript = Some("open the repo".into());
        session.merge_pending_transcript("and");
        session.merge_pending_transcript("run");
        session.merge_pending_transcript("tests");
        assert_eq!(session.pending_transcript, "open the repo and run tests");
        let dispatch = transcript_dispatch(
            session.last_flushed_transcript.as_deref(),
            &session.pending_transcript,
        )
        .unwrap();
        assert_eq!(dispatch.1, "and run tests");
    }
}
