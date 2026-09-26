use super::super::voice_transcript::transcript_dispatch;
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
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
    session.merge_pending_transcript("and run tests");
    session.merge_pending_transcript("open the");
    assert_eq!(session.pending_transcript, "open the repo and run tests");
}

#[test]
fn duplicate_flushed_prefix_keeps_pending_suffix() {
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        pending_transcript: "open the repo".into(),
        gemini_settling: true,
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        gemini_activity_ended: true,
        gemini_settling: true,
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        gemini_activity_ended: true,
        gemini_settling: true,
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        gemini_transcript_final: true,
        ..VoiceSessionState::default()
    };
    assert!(session.gemini_transcript_final);
    session.reset_gemini_utterance();
    assert!(!session.gemini_transcript_final);
    session.gemini_transcript_final = true;
    session.stop_realtime();
    assert!(!session.gemini_transcript_final);
}

#[test]
fn openai_item_change_keeps_full_second_transcript() {
    let mut session = VoiceSessionState {
        openai_item_id: Some("a".into()),
        last_flushed_transcript: Some("yes".into()),
        pending_transcript: "yes".into(),
        ..VoiceSessionState::default()
    };
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
    let mut session = VoiceSessionState {
        last_flushed_transcript: Some("open the repo".into()),
        ..VoiceSessionState::default()
    };
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
