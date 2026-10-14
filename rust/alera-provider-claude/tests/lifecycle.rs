mod support;

use alera_provider_claude::{ClaudeProvider, ClaudeProviderConfig};
use alera_provider_protocol::{EventKind, InterruptInput, Provider, SessionStartInput, TurnInput};
use serde_json::json;
use support::*;

#[tokio::test]
async fn initialize_start_turn_and_result_preserve_wire_messages() {
    let (mut provider, handle) = started_provider([
        initialize_response(),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {
                "id": "message-1",
                "model": "claude-test",
                "content": [{"type": "text", "text": "hello"}]
            }
        }),
        result_message(false, None),
    ])
    .await;

    let session_event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(session_event.kind, EventKind::SessionStarted);
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "prompt"))
        .await
        .unwrap();
    assert!(turn.turn_id.starts_with("turn:claude:"));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let content = provider.next_event().await.unwrap().unwrap();
    assert_eq!(content.kind, EventKind::ContentDelta);
    assert_eq!(content.payload["delta"], "hello");
    assert_eq!(
        content.raw.unwrap().payload["message"]["content"][0]["text"],
        "hello"
    );
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.turn_id.as_deref(), Some(turn.turn_id.as_str()));
    assert_eq!(completed.payload["state"], "completed");
    assert_eq!(
        completed.raw.unwrap().payload["opaque_sentinel"]["kept"],
        true
    );

    let writes = handle.writes.lock().unwrap();
    assert_eq!(writes[0]["type"], "control_request");
    assert_eq!(writes[0]["request"]["subtype"], "initialize");
    assert_eq!(writes[1]["type"], "user");
    assert_eq!(writes[1]["message"]["content"], "prompt");
}

#[tokio::test]
async fn resume_keeps_native_thread_separate_from_app_thread() {
    let (transport, _handle) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput {
            resume_thread_id: Some("native-resume".into()),
            ..SessionStartInput::new("app-thread")
        })
        .await
        .unwrap();
    assert_eq!(session.thread_id, "app-thread");
    assert_eq!(session.native_thread_id, "native-resume");
    assert!(!provider.capabilities().native_turn_ids);
}

#[tokio::test]
async fn interrupt_ack_is_not_a_terminal_event() {
    let interrupt_response = json!({
        "type": "control_response",
        "response": {"subtype": "success", "request_id": "req_2", "response": {}}
    });
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        interrupt_response,
        result_message(false, Some("interrupted")),
    ])
    .await;
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "run"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    provider
        .interrupt(InterruptInput {
            thread_id: "app-thread".into(),
            turn_id: Some(turn.turn_id.clone()),
        })
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::TurnAborted);
    assert_eq!(event.payload["reason"], "interrupted");
}

#[tokio::test]
async fn overlapping_turns_are_rejected_until_result() {
    let (mut provider, _handle) = started_provider([initialize_response()]).await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "first"))
        .await
        .unwrap();
    let error = provider
        .send_turn(TurnInput::text("app-thread", "second"))
        .await
        .unwrap_err();
    assert!(matches!(
        error,
        alera_provider_protocol::ProviderError::InvalidState(_)
    ));
}

#[tokio::test]
async fn multiple_turns_keep_synthetic_turns_and_terminal_boundaries() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {"id": "message-1", "content": [{"type": "text", "text": "one"}]}
        }),
        result_message(false, None),
        json!({
            "type": "assistant",
            "session_id": "native-session",
            "message": {"id": "message-2", "content": [{"type": "text", "text": "two"}]}
        }),
        result_message(false, None),
    ])
    .await;
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let first = provider
        .send_turn(TurnInput::text("app-thread", "first"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["delta"],
        "one"
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().turn_id,
        Some(first.turn_id.clone())
    );
    let second = provider
        .send_turn(TurnInput::text("app-thread", "second"))
        .await
        .unwrap();
    assert_ne!(first.turn_id, second.turn_id);
    let _ = provider.next_event().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["delta"],
        "two"
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().turn_id,
        Some(second.turn_id)
    );
}

#[tokio::test]
async fn unsupported_read_only_sandbox_fails_before_launch() {
    let (transport, _handle) = ScriptedTransport::new([initialize_response()]);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let result = provider
        .start_session(SessionStartInput {
            sandbox_mode: Some(alera_provider_protocol::SandboxMode::ReadOnly),
            ..SessionStartInput::new("app-thread")
        })
        .await;
    assert!(matches!(
        result,
        Err(alera_provider_protocol::ProviderError::Unsupported(_))
    ));
}
