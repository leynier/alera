use super::{
    config_for_provider, gemini_setup_message, gemini_speak_message, looks_like_home_cancel,
    openai_session_update, parse_gemini_message, parse_openai_message, resample_pcm16_16k_to_24k,
    RealtimeParsed, GEMINI_LIVE_MODEL, OPENAI_REALTIME_MINI_MODEL, SPEECH_IO_INSTRUCTIONS,
};
use serde_json::json;

#[test]
fn gemini_is_the_default_realtime_provider() {
    let config = config_for_provider("geminiFlashLive", Some("gk"), None, None).unwrap();
    assert_eq!(config.model, GEMINI_LIVE_MODEL);
    let setup = gemini_setup_message(&config);
    assert_eq!(
        setup["setup"]["realtimeInputConfig"]["automaticActivityDetection"]["disabled"],
        true
    );
    assert!(setup["setup"].get("proactivity").is_none());
    assert!(setup["setup"]["generationConfig"]["thinkingConfig"]
        .get("thinkingBudget")
        .is_none());
    assert_eq!(
        setup["setup"]["generationConfig"]["thinkingConfig"]["thinkingLevel"],
        "minimal"
    );
    assert_eq!(
        setup["setup"]["generationConfig"]["thinkingConfig"]["includeThoughts"],
        false
    );
    assert!(setup["setup"]["systemInstruction"]["parts"][0]["text"]
        .as_str()
        .unwrap()
        .contains("not an assistant"));
}

#[test]
fn openai_mini_maps_to_gpt_realtime_mini() {
    let config = config_for_provider("gptRealtimeMini", None, Some("sk"), Some("marin")).unwrap();
    assert_eq!(config.model, OPENAI_REALTIME_MINI_MODEL);
    let update = openai_session_update(&config);
    assert_eq!(
        update["session"]["audio"]["input"]["turn_detection"],
        json!(null)
    );
    assert_eq!(update["session"]["audio"]["output"]["voice"], "marin");
    assert!(update["session"]["instructions"]
        .as_str()
        .unwrap()
        .contains("stay silent"));
}

#[test]
fn gemini_parses_transcription_and_pcm() {
    let events = parse_gemini_message(&json!({
        "serverContent": {
            "inputTranscription": { "text": "open the repo" },
            "modelTurn": {
                "parts": [{
                    "inlineData": {
                        "mimeType": "audio/pcm;rate=24000",
                        "data": "AAAA",
                    }
                }]
            },
            "turnComplete": true,
        }
    }));
    assert!(events.iter().any(|event| matches!(
        event,
        RealtimeParsed::InputTranscript { text, is_final: false, .. } if text == "open the repo"
    )));
    assert!(events.iter().any(|event| matches!(
        event,
        RealtimeParsed::Audio {
            sample_rate: 24_000,
            ..
        }
    )));
    assert!(events
        .iter()
        .any(|event| matches!(event, RealtimeParsed::TurnComplete)));
    let later = parse_gemini_message(&json!({
        "serverContent": {
            "inputTranscription": { "text": "repository" },
            "turnComplete": true,
        }
    }));
    assert!(later.iter().any(|event| matches!(
        event,
        RealtimeParsed::InputTranscript { text, is_final: false, .. } if text == "repository"
    )));

    let finished = parse_gemini_message(&json!({
        "serverContent": {
            "inputTranscription": { "text": "open the repository", "finished": true },
        }
    }));
    assert!(finished.iter().any(|event| matches!(
        event,
        RealtimeParsed::InputTranscript { text, is_final: true, .. } if text == "open the repository"
    )));
    let textless = parse_gemini_message(&json!({
        "serverContent": {
            "inputTranscription": { "finished": true },
        }
    }));
    assert!(textless.iter().any(|event| matches!(
        event,
        RealtimeParsed::InputTranscript { text, is_final: true, .. } if text.is_empty()
    )));
}

#[test]
fn openai_parses_final_transcript_and_audio_delta() {
    let transcript = parse_openai_message(&json!({
        "type": "conversation.item.input_audio_transcription.completed",
        "item_id": "item_a",
        "transcript": "stop",
    }));
    assert_eq!(
        transcript,
        vec![RealtimeParsed::InputTranscript {
            text: "stop".into(),
            is_final: true,
            item_id: Some("item_a".into()),
        }]
    );
    let delta = parse_openai_message(&json!({
        "type": "conversation.item.input_audio_transcription.delta",
        "delta": "delete",
    }));
    assert!(delta.is_empty());
    let empty = parse_openai_message(&json!({
        "type": "conversation.item.input_audio_transcription.completed",
        "item_id": "item_empty",
        "transcript": "",
    }));
    assert_eq!(
        empty,
        vec![RealtimeParsed::InputTranscript {
            text: String::new(),
            is_final: true,
            item_id: Some("item_empty".into()),
        }]
    );
    let failed = parse_openai_message(&json!({
        "type": "conversation.item.input_audio_transcription.failed",
        "item_id": "item_a",
        "error": { "code": "audio_unintelligible", "message": "unintelligible" },
    }));
    assert_eq!(
        failed,
        vec![RealtimeParsed::InputTranscriptionFailed {
            item_id: Some("item_a".into()),
            message: "unintelligible".into(),
        }]
    );
    let committed = parse_openai_message(&json!({
        "type": "input_audio_buffer.committed",
        "item_id": "item_a",
    }));
    assert_eq!(
        committed,
        vec![RealtimeParsed::InputCommitted {
            item_id: "item_a".into(),
        }]
    );
    let audio = parse_openai_message(&json!({
        "type": "response.output_audio.delta",
        "delta": "AAAA",
    }));
    assert!(matches!(
        audio.as_slice(),
        [RealtimeParsed::Audio {
            sample_rate: 24_000,
            ..
        }]
    ));
}

#[test]
fn cancel_words_match_the_client_list() {
    assert!(looks_like_home_cancel("Para"));
    assert!(looks_like_home_cancel("  cállate "));
    assert!(looks_like_home_cancel("Stop."));
    assert!(looks_like_home_cancel("¡Para!"));
    assert!(looks_like_home_cancel("(Stop)"));
    assert!(!looks_like_home_cancel("please stop the build"));
}

#[test]
fn resamples_two_16k_samples_into_three_24k_samples() {
    let pcm = resample_pcm16_16k_to_24k(&[0, 0, 0, 64]);
    assert_eq!(pcm.len(), 6);
}

#[test]
fn instructions_forbid_tools() {
    assert!(SPEECH_IO_INSTRUCTIONS.contains("Never call tools"));
}

#[test]
fn gemini_speak_uses_realtime_input_text() {
    let message = gemini_speak_message("On it.");
    assert!(message.get("clientContent").is_none());
    assert!(message["realtimeInput"]["text"]
        .as_str()
        .unwrap()
        .contains("On it."));
    let frames = super::gemini_speak_frames("On it.");
    assert_eq!(frames.len(), 3);
    assert!(frames[0].pointer("/realtimeInput/activityStart").is_some());
    assert!(frames[2].pointer("/realtimeInput/activityEnd").is_some());
}
