use tokio_tungstenite::tungstenite::protocol::{frame::coding::CloseCode, CloseFrame};

use super::{abnormal_close_message, is_recoverable_realtime_error};

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
    super::finish_unowned_gemini_input(&mut speak_busy, &mut gemini_input_busy, 1, &mut completing);
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
    super::finish_unowned_gemini_input(&mut speak_busy, &mut gemini_input_busy, 1, &mut completing);
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
    super::finish_unowned_gemini_input(&mut speak_busy, &mut gemini_input_busy, 1, &mut completing);
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

#[test]
fn abnormal_close_reports_the_provider_reason() {
    let refused = CloseFrame {
        code: CloseCode::Policy,
        reason: "API key not valid.".into(),
    };
    assert_eq!(
        abnormal_close_message(Some(&refused)).as_deref(),
        Some("realtime socket closed (1008): API key not valid.")
    );
    let normal = CloseFrame {
        code: CloseCode::Normal,
        reason: "".into(),
    };
    assert!(abnormal_close_message(Some(&normal)).is_none());
    assert!(abnormal_close_message(None).is_none());
}
