use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, InterruptInput, Provider, RequestId, RuntimeResponse,
    SessionStartInput, TurnInput,
};
use serde_json::json;
use std::collections::BTreeMap;

fn state() -> serde_json::Value {
    json!({
        "sessionFile": "/tmp/pi/session.jsonl",
        "sessionId": "session-1",
        "model": { "provider": "anthropic", "id": "claude-sonnet" },
        "isStreaming": false
    })
}

fn response(id: &str, command: &str, data: serde_json::Value) -> serde_json::Value {
    json!({ "type": "response", "id": id, "command": command, "success": true, "data": data })
}

fn config() -> PiProviderConfig {
    PiProviderConfig {
        request_timeout: std::time::Duration::from_millis(100),
        ..PiProviderConfig::default()
    }
}

#[tokio::test]
async fn initializes_current_session_and_streams_until_agent_settled() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({ "type": "response", "command": "prompt", "success": true }),
        json!({ "type": "agent_start" }),
        json!({ "type": "message_update", "assistantMessageEvent": { "type": "text_delta", "delta": "hello" } }),
        json!({ "type": "agent_end" }),
        json!({ "type": "agent_settled" }),
        response("alera-pi-2", "get_state", state()),
    ];
    let mock = MockTransport::new(responses);
    let mut provider = PiProvider::new(mock, config());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(session.native_thread_id, "/tmp/pi/session.jsonl");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionStarted
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    assert!(turn.native_turn_id.is_none());
    assert!(matches!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    ));
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(delta.kind, EventKind::ContentDelta);
    assert_eq!(delta.payload["delta"], "hello");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::Unknown("agent_end".into())
    );
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
    assert!(provider.session().unwrap().active_turn_id.is_none());
}

#[tokio::test]
async fn extension_confirm_uses_native_id_and_resolves_once() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({ "type": "extension_ui_request", "id": 17, "method": "confirm", "title": "Allow bash?", "message": "Run command" }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    assert_eq!(event.request_id.as_deref(), Some("17"));
    assert_eq!(
        provider.session().unwrap().status,
        alera_provider_protocol::SessionStatus::Ready
    );
    provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::Integer(17),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    let writes = provider.transport().writes();
    let response = writes.last().unwrap();
    assert_eq!(response["type"], "extension_ui_response");
    assert_eq!(response["id"], 17);
    assert_eq!(response["confirmed"], true);
    let resolved = provider.next_event().await.unwrap().unwrap();
    assert_eq!(resolved.kind, EventKind::RequestResolved);
}

#[tokio::test]
async fn overlapping_turns_are_rejected_and_interrupt_waits_for_settlement() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({ "type": "response", "command": "prompt", "success": true }),
        response("alera-pi-2", "abort", json!(null)),
        json!({ "type": "agent_settled", "aborted": true }),
        response("alera-pi-3", "get_state", state()),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let turn = provider
        .send_turn(TurnInput::text("thread", "one"))
        .await
        .unwrap();
    assert!(provider
        .send_turn(TurnInput::text("thread", "two"))
        .await
        .is_err());
    provider
        .interrupt(InterruptInput {
            thread_id: "thread".into(),
            turn_id: Some(turn.turn_id),
        })
        .await
        .unwrap();
    assert!(provider.session().unwrap().active_turn_id.is_some());
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.payload["state"], "interrupted");
}

#[tokio::test]
async fn resume_uses_switch_session_and_preserves_jsonl_options() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        response(
            "alera-pi-2",
            "switch_session",
            json!({ "cancelled": false }),
        ),
        response("alera-pi-3", "get_state", state()),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    let mut input = SessionStartInput::new("thread");
    input.resume_thread_id = Some("/old/session.jsonl".into());
    provider.start_session(input).await.unwrap();
    let writes = provider.transport().writes();
    assert_eq!(writes[1]["type"], "switch_session");
    assert_eq!(writes[1]["sessionPath"], "/old/session.jsonl");
}

#[tokio::test]
async fn select_response_preserves_empty_values_and_native_id_type() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "extension_ui_request",
            "id": "choice",
            "method": "select",
            "title": "Pick",
            "options": ["", "second"]
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let request = provider.next_event().await.unwrap().unwrap();
    assert_eq!(request.kind, EventKind::UserInputRequested);
    let mut answers = BTreeMap::new();
    answers.insert("choice".into(), json!(""));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: RequestId::String("choice".into()),
            answers,
        })
        .await
        .unwrap();
    let wire = provider.transport().writes().last().unwrap();
    assert_eq!(wire["type"], "extension_ui_response");
    assert_eq!(wire["id"], "choice");
    assert_eq!(wire["value"], "");
}

#[tokio::test]
async fn settled_turn_waits_for_idle_state_before_terminal_event() {
    let mut busy = state();
    busy["isCompacting"] = json!(true);
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({ "type": "response", "command": "prompt", "success": true }),
        json!({ "type": "agent_settled" }),
        response("alera-pi-2", "get_state", busy),
        json!({ "type": "agent_settled" }),
        response("alera-pi-3", "get_state", state()),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(
        provider
            .transport()
            .writes()
            .iter()
            .filter(|record| record["type"] == "get_state")
            .count(),
        3
    );
}

#[tokio::test]
async fn expired_extension_request_is_cancelled_on_next_poll() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "extension_ui_request",
            "id": -7,
            "method": "confirm",
            "title": "Expired",
            "timeout": -1
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let resolved = provider.next_event().await.unwrap().unwrap();
    assert_eq!(resolved.kind, EventKind::RequestResolved);
    assert_eq!(resolved.request_id.as_deref(), Some("-7"));
    let wire = provider.transport().writes().last().unwrap();
    assert_eq!(wire["id"], -7);
    assert_eq!(wire["cancelled"], true);
}

#[tokio::test]
async fn rejected_prompt_emits_failed_terminal_event_and_clears_turn() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "response",
            "command": "prompt",
            "success": false,
            "error": "prompt rejected"
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::TurnCompleted);
    assert_eq!(event.payload["state"], "failed");
    assert_eq!(event.payload["errorMessage"], "prompt rejected");
    assert!(provider.session().unwrap().active_turn_id.is_none());
}

#[tokio::test]
async fn idless_prompt_ack_does_not_collide_with_abort_response() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({ "type": "response", "command": "prompt", "success": true }),
        response("alera-pi-2", "abort", json!(null)),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let turn = provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    provider
        .interrupt(InterruptInput {
            thread_id: "thread".into(),
            turn_id: Some(turn.turn_id),
        })
        .await
        .unwrap();
    assert!(provider.session().unwrap().active_turn_id.is_some());
}

#[tokio::test]
async fn persistent_approval_decisions_remain_pending_until_one_time_answer() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "extension_ui_request",
            "id": 17,
            "method": "confirm",
            "title": "Allow bash?"
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let persistent = provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::Integer(17),
            decision: ApprovalDecision::AcceptForSession,
            updated_input: None,
        })
        .await;
    assert!(matches!(
        persistent,
        Err(alera_provider_protocol::ProviderError::Unsupported(_))
    ));
    provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::Integer(17),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    assert_eq!(
        provider.transport().writes().last().unwrap()["confirmed"],
        true
    );
}

#[tokio::test]
async fn non_string_user_input_is_rejected_without_cancelling_request() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "extension_ui_request",
            "id": "choice",
            "method": "input",
            "title": "Value"
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let mut answers = BTreeMap::new();
    answers.insert("choice".into(), json!(42));
    let invalid = provider
        .respond(RuntimeResponse::UserInput {
            request_id: RequestId::String("choice".into()),
            answers,
        })
        .await;
    assert!(matches!(
        invalid,
        Err(alera_provider_protocol::ProviderError::Validation(_))
    ));
    let mut answers = BTreeMap::new();
    answers.insert("choice".into(), json!("ok"));
    provider
        .respond(RuntimeResponse::UserInput {
            request_id: RequestId::String("choice".into()),
            answers,
        })
        .await
        .unwrap();
    assert_eq!(provider.transport().writes().last().unwrap()["value"], "ok");
}

#[tokio::test]
async fn multi_select_extension_request_is_explicitly_unsupported() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "extension_ui_request",
            "id": "many",
            "method": "select",
            "multiSelect": true,
            "options": ["one", "two"]
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    assert!(matches!(
        provider.next_event().await,
        Err(alera_provider_protocol::ProviderError::Unsupported(_))
    ));
}

#[tokio::test]
async fn text_end_completes_item_without_repeating_content_delta() {
    let responses = vec![
        response("alera-pi-1", "get_state", state()),
        json!({
            "type": "message_update",
            "assistantMessageEvent": { "type": "text_delta", "delta": "one" }
        }),
        json!({
            "type": "message_update",
            "assistantMessageEvent": { "type": "text_end", "content": "one" }
        }),
    ];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("thread", "hello"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ContentDelta
    );
    let end = provider.next_event().await.unwrap().unwrap();
    assert_eq!(end.kind, EventKind::ItemUpdated);
    assert_ne!(end.kind, EventKind::ContentDelta);
}

#[tokio::test]
async fn eof_emits_one_session_exit_and_stops_session() {
    let responses = vec![response("alera-pi-1", "get_state", state())];
    let mut provider = PiProvider::new(MockTransport::new(responses), config());
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    let exited = provider.next_event().await.unwrap().unwrap();
    assert_eq!(exited.kind, EventKind::SessionExited);
    assert_eq!(
        provider.session().unwrap().status,
        alera_provider_protocol::SessionStatus::Stopped
    );
    assert!(provider.next_event().await.unwrap().is_none());
    assert!(!provider.capabilities().steer);
}
