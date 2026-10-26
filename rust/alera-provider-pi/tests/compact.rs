use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{
    Attachment, EventKind, Provider, ProviderEvent, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};

fn state() -> Value {
    json!({
        "sessionFile": "/tmp/pi/session.jsonl",
        "sessionId": "session-1",
        "model": { "provider": "anthropic", "id": "claude-sonnet" },
        "isStreaming": false,
        "isCompacting": false
    })
}

fn state_response(id: &str) -> Value {
    json!({ "type": "response", "id": id, "command": "get_state", "success": true, "data": state() })
}

fn compact_response(success: bool, error: Option<&str>) -> Value {
    let mut response = json!({ "type": "response", "command": "compact", "success": success });
    if success {
        response["data"] = json!({
            "summary": "Earlier work: added the parser.",
            "firstKeptEntryId": "entry-9",
            "tokensBefore": 48000
        });
    }
    if let Some(error) = error {
        response["error"] = json!(error);
    }
    response
}

async fn started(after_start: Vec<Value>) -> PiProvider<MockTransport> {
    let mut script = vec![state_response("alera-pi-1")];
    script.extend(after_start);
    let mut provider = PiProvider::new(
        MockTransport::new(script),
        PiProviderConfig {
            request_timeout: std::time::Duration::from_millis(100),
            ..PiProviderConfig::default()
        },
    );
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    assert_eq!(next(&mut provider).await.kind, EventKind::SessionStarted);
    assert_eq!(next(&mut provider).await.kind, EventKind::ThreadStarted);
    provider
}

async fn next(provider: &mut PiProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

fn last_write(provider: &PiProvider<MockTransport>) -> Value {
    provider.transport().writes().last().unwrap().clone()
}

#[tokio::test]
async fn compact_with_instructions_uses_the_rpc_command_and_ends_on_its_response() {
    let mut provider = started(vec![
        json!({ "type": "compaction_start", "reason": "manual" }),
        json!({ "type": "compaction_end", "reason": "manual", "result": { "summary": "Earlier work" } }),
        compact_response(true, None),
        state_response("alera-pi-2"),
    ])
    .await;
    let turn = provider
        .send_turn(TurnInput::text(
            "thread",
            "  /compact   keep the API notes \n",
        ))
        .await
        .unwrap();
    assert_eq!(
        last_write(&provider),
        json!({ "type": "compact", "customInstructions": "keep the API notes" })
    );
    assert_eq!(
        next(&mut provider).await.kind,
        EventKind::Unknown("compaction_start".into())
    );
    assert_eq!(
        next(&mut provider).await.kind,
        EventKind::Unknown("compaction_end".into())
    );
    let completed = next(&mut provider).await;
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.turn_id.as_deref(), Some(turn.turn_id.as_str()));
    assert_eq!(completed.payload["state"], "completed");
    assert!(provider.session().unwrap().active_turn_id.is_none());
}

#[tokio::test]
async fn bare_compact_sends_no_instructions_and_ignores_attachments() {
    let mut provider = started(vec![]).await;
    let mut input = TurnInput::text("thread", "/compact");
    input.attachments = vec![Attachment::Image {
        url: "https://example.invalid/image.png".into(),
    }];
    provider.send_turn(input).await.unwrap();
    assert_eq!(last_write(&provider), json!({ "type": "compact" }));
}

#[tokio::test]
async fn only_compact_as_the_whole_first_word_is_the_builtin() {
    for (text, expected) in [
        (
            "/compactor now",
            json!({ "type": "prompt", "message": "/compactor now" }),
        ),
        (
            "please /compact",
            json!({ "type": "prompt", "message": "please /compact" }),
        ),
        // JavaScript's `\s`, like Rust's, treats a no-break space as white space.
        (
            "/compact\u{a0}x",
            json!({ "type": "compact", "customInstructions": "x" }),
        ),
        ("/compact \n ", json!({ "type": "compact" })),
    ] {
        let mut provider = started(vec![]).await;
        provider
            .send_turn(TurnInput::text("thread", text))
            .await
            .unwrap();
        assert_eq!(last_write(&provider), expected, "{text:?}");
    }
}

#[tokio::test]
async fn a_rejected_compact_fails_the_turn_with_pi_error() {
    for (error, expected) in [
        (
            Some("Nothing to compact (session too small)"),
            "Nothing to compact (session too small)",
        ),
        (None, "Pi compact failed."),
    ] {
        let mut provider = started(vec![compact_response(false, error)]).await;
        provider
            .send_turn(TurnInput::text("thread", "/compact"))
            .await
            .unwrap();
        let completed = next(&mut provider).await;
        assert_eq!(completed.kind, EventKind::TurnCompleted);
        assert_eq!(completed.payload["state"], "failed");
        assert_eq!(completed.payload["errorMessage"], expected);
        assert!(provider.session().unwrap().active_turn_id.is_none());
    }
}

#[tokio::test]
async fn a_rejection_after_compaction_started_settles_through_pi_state() {
    let mut provider = started(vec![
        json!({ "type": "compaction_start", "reason": "manual" }),
        compact_response(false, Some("Compaction failed")),
        state_response("alera-pi-2"),
    ])
    .await;
    provider
        .send_turn(TurnInput::text("thread", "/compact"))
        .await
        .unwrap();
    assert_eq!(
        next(&mut provider).await.kind,
        EventKind::Unknown("compaction_start".into())
    );
    let completed = next(&mut provider).await;
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
}
