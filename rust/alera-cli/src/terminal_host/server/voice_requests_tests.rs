use super::voice_home_agent::compose_home_turns;
use super::voice_session::{PendingVoiceTurn, VoiceSessionState};

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
    assert!(
        super::voice_requests::decode_pcm(&serde_json::json!({ "audioBase64": "AQ" })).is_err()
    );
    assert_eq!(
        super::voice_requests::decode_pcm(&serde_json::json!({ "audioBase64": "AAA=" })).unwrap(),
        vec![0, 0]
    );
}

#[test]
fn wav_header_uses_the_pcm_length() {
    let wav = super::voice_chained_jobs::pcm16_to_wav(&[0, 0, 0, 0], 16_000);
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
    assert!(super::voice_transcript::is_transcript_prefix(
        previous, &text
    ));
    assert_eq!(text[previous.len()..].trim(), "and run tests");
    let first = super::voice_transcript::transcript_dispatch(Some(previous), &text).unwrap();
    assert_eq!(first.1, "and run tests");
    assert_eq!(first.0, "open the repo and run tests");
    assert!(super::voice_transcript::transcript_dispatch(
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

#[test]
fn mobile_gateway_allows_every_voice_verb() {
    use super::mobile_gateway_surface::{mobile_request_allowed, MOBILE_HELLO_CAPABILITIES};
    assert!(MOBILE_HELLO_CAPABILITIES
        .contains(&crate::terminal_host::protocol::RUNTIME_HOST_VOICE_HOME_AGENT_CAPABILITY));
    for verb in [
        "ensure",
        "status",
        "start",
        "stop",
        "turn",
        "synthesize",
        "spoken",
        "audio",
        "activity",
        "credentials.status",
        "credentials.save",
        "credentials.clear",
    ] {
        assert!(
            mobile_request_allowed(&format!("mobile.voice.{verb}")),
            "{verb}"
        );
    }
}
