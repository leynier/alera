use alera_provider_opencode::opencode_agent_sdk::HttpError;
use alera_provider_opencode::{
    ByteStream, HttpRequest, HttpResponse, HttpTransport, MockHttpTransport, OpenCodeGeneration,
    OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{EventKind, Provider, ProviderError, SessionStartInput, TurnInput};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct EventTransport {
    http: MockHttpTransport,
    events: Arc<Mutex<VecDeque<Vec<u8>>>>,
}

impl EventTransport {
    fn push(&self, event: &Value) {
        self.events
            .lock()
            .unwrap()
            .push_back(format!("data: {event}\n\n").into_bytes());
    }
}

#[async_trait]
impl HttpTransport for EventTransport {
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        self.http.request(request).await
    }

    async fn open_stream(&self, _request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        Ok(Box::new(self.clone()))
    }
}

#[async_trait]
impl ByteStream for EventTransport {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        Ok(self.events.lock().unwrap().pop_front())
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        self.events.lock().unwrap().clear();
        Ok(())
    }
}

async fn started(
    generation: OpenCodeGeneration,
) -> (OpenCodeProvider<EventTransport>, EventTransport, String) {
    started_with_resume(generation, false).await
}

async fn started_with_resume(
    generation: OpenCodeGeneration,
    resume: bool,
) -> (OpenCodeProvider<EventTransport>, EventTransport, String) {
    let transport = EventTransport::default();
    transport
        .http
        .push_response(HttpResponse::new(200, br#"{"id":"ses_native"}"#));
    transport
        .http
        .push_response(HttpResponse::new(204, Vec::new()));
    let mut provider = OpenCodeProvider::new(
        transport.clone(),
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    let mut session_input = SessionStartInput::new("app-thread");
    if resume {
        session_input.resume_thread_id = Some("ses_native".into());
    }
    provider.start_session(session_input).await.unwrap();
    let turn = provider
        .send_turn(TurnInput::text("app-thread", "unique QA user prompt"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    (provider, transport, turn.native_turn_id.unwrap())
}

fn delta(message_id: &str, part_id: &str, value: Value) -> Value {
    json!({
        "type": "message.part.delta",
        "properties": {
            "sessionID": "ses_native", "messageID": message_id,
            "partID": part_id, "field": "text", "delta": value
        }
    })
}

fn part(message_id: &str, part_id: &str, kind: &str, text: &str) -> Value {
    json!({
        "type": "message.part.updated",
        "properties": {
            "sessionID": "ses_native",
            "part": { "id": part_id, "messageID": message_id, "sessionID": "ses_native", "type": kind, "text": text }
        }
    })
}

fn message(message_id: &str, role: &str, parent_id: &str) -> Value {
    json!({
        "type": "message.updated",
        "properties": { "info": { "id": message_id, "sessionID": "ses_native", "role": role, "parentID": parent_id } }
    })
}

fn idle() -> Value {
    json!({ "type": "session.idle", "properties": { "sessionID": "ses_native" } })
}

#[tokio::test]
async fn empty_native_delta_preserves_raw_without_content_or_terminal_event() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    let empty = delta("msg_assistant", "prt_text", json!(""));
    transport.push(&empty);
    transport.push(&delta("msg_assistant", "prt_text", json!("answer")));
    transport.push(&idle());
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::Unknown("message.part.delta".into()));
    assert_eq!(event.raw.as_ref().unwrap().payload, empty);
    event.validate().unwrap();
    assert!(provider.session().unwrap().active_turn_id.is_some());
    let content = provider.next_event().await.unwrap().unwrap();
    assert_eq!(content.kind, EventKind::ContentDelta);
    assert_eq!(content.payload["delta"], "answer");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
    assert!(provider.session().unwrap().active_turn_id.is_none());
    provider.close().await.unwrap();
}

#[tokio::test]
async fn empty_v2_text_and_reasoning_deltas_preserve_the_native_envelope() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::V2).await;
    for kind in ["session.text.delta", "session.reasoning.delta"] {
        let empty = json!({ "type": kind, "data": { "sessionID": "ses_native", "assistantMessageID": "msg_assistant", "delta": "" } });
        transport.push(&empty);
        let event = provider.next_event().await.unwrap().unwrap();
        assert_eq!(event.kind, EventKind::Unknown(kind.into()));
        assert_eq!(event.raw.as_ref().unwrap().payload, empty);
        event.validate().unwrap();
    }
    assert!(provider.session().unwrap().active_turn_id.is_some());
}

#[tokio::test]
async fn missing_or_non_string_delta_remains_a_protocol_error() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    for value in [
        None,
        Some(Value::Null),
        Some(json!(7)),
        Some(json!(false)),
        Some(json!([])),
        Some(json!({})),
    ] {
        let mut invalid = delta("msg_assistant", "prt_text", Value::Null);
        match value {
            Some(value) => invalid["properties"]["delta"] = value,
            None => {
                invalid["properties"]
                    .as_object_mut()
                    .unwrap()
                    .remove("delta");
            }
        }
        transport.push(&invalid);
        let error = provider.next_event().await.unwrap_err();
        assert!(matches!(error, ProviderError::Protocol(_)));
        assert!(error.to_string().contains("has no delta"));
        assert!(provider.session().unwrap().active_turn_id.is_some());
    }
    transport.push(&delta("msg_assistant", "prt_text", json!("still valid")));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["delta"],
        "still valid"
    );
}

#[tokio::test]
async fn echoed_sent_user_parts_are_user_messages_and_assistant_parent_refs_survive() {
    let (mut provider, transport, user_id) = started(OpenCodeGeneration::Legacy1).await;
    transport.push(&part(&user_id, "prt_user", "text", "unique QA user prompt"));
    transport.push(&delta(&user_id, "prt_user", json!("unique QA user prompt")));
    let assistant = message("msg_assistant", "assistant", &user_id);
    transport.push(&assistant);
    transport.push(&part("msg_assistant", "prt_assistant", "text", "answer"));
    transport.push(&delta("msg_assistant", "prt_assistant", json!("answer")));
    let echoed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(echoed.payload["itemType"], "user_message");
    assert_eq!(echoed.item_id.as_deref(), Some("prt_user"));
    assert!(matches!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::Unknown(_)
    ));
    let native_assistant = provider.next_event().await.unwrap().unwrap();
    assert_eq!(native_assistant.payload["itemType"], "assistant_message");
    assert_eq!(native_assistant.payload["data"]["parentID"], user_id);
    assert_eq!(native_assistant.raw.unwrap().payload, assistant);
    let text = provider.next_event().await.unwrap().unwrap();
    assert_eq!(text.payload["itemType"], "assistant_message");
    assert_eq!(text.item_id.as_deref(), Some("prt_assistant"));
    assert_eq!(
        text.provider_refs.unwrap().provider_item_id.as_deref(),
        Some("prt_assistant")
    );
    let streamed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(streamed.payload["streamKind"], "assistant_text");
    assert_eq!(streamed.payload["delta"], "answer");
}

#[tokio::test]
async fn native_role_metadata_identifies_user_parts_with_a_different_message_id() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    transport.push(&message("msg_other_user", "user", ""));
    transport.push(&part(
        "msg_other_user",
        "prt_other_user",
        "text",
        "user prompt",
    ));
    transport.push(&delta(
        "msg_other_user",
        "prt_other_user",
        json!("user prompt"),
    ));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["itemType"],
        "user_message"
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["itemType"],
        "user_message"
    );
    assert!(matches!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::Unknown(_)
    ));
}

#[tokio::test]
async fn reasoning_delta_uses_its_prior_part_metadata_and_native_identity() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    transport.push(&part("msg_assistant", "prt_reasoning", "reasoning", ""));
    transport.push(&delta("msg_assistant", "prt_reasoning", json!("thinking")));
    transport.push(&delta(
        "msg_other_assistant",
        "prt_reasoning",
        json!("other message text"),
    ));
    let updated = provider.next_event().await.unwrap().unwrap();
    assert_eq!(updated.payload["itemType"], "reasoning");
    assert_eq!(updated.item_id.as_deref(), Some("prt_reasoning"));
    let streamed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(streamed.payload["streamKind"], "reasoning_text");
    assert_eq!(streamed.payload["delta"], "thinking");
    assert_eq!(streamed.item_id.as_deref(), Some("prt_reasoning"));
    assert_eq!(
        streamed.provider_refs.unwrap().provider_item_id.as_deref(),
        Some("prt_reasoning")
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["streamKind"],
        "assistant_text"
    );
}

#[tokio::test]
async fn native_part_and_role_metadata_are_cleared_between_turns() {
    let (mut provider, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    transport.push(&part("msg_assistant", "prt_reused", "reasoning", ""));
    transport.push(&message("msg_user_metadata", "user", ""));
    transport.push(&idle());
    provider.next_event().await.unwrap();
    provider.next_event().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnCompleted
    );
    transport
        .http
        .push_response(HttpResponse::new(204, Vec::new()));
    provider
        .send_turn(TurnInput::text("app-thread", "next turn"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    transport.push(&delta("msg_assistant", "prt_reused", json!("new answer")));
    transport.push(&part(
        "msg_user_metadata",
        "prt_reused",
        "text",
        "new answer",
    ));
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["streamKind"],
        "assistant_text"
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().payload["itemType"],
        "assistant_message"
    );
}

#[tokio::test]
async fn native_metadata_does_not_leak_into_another_provider_resuming_the_same_session() {
    let (mut first, transport, _) = started(OpenCodeGeneration::Legacy1).await;
    transport.push(&part("msg_assistant", "prt_reused", "reasoning", ""));
    transport.push(&message("msg_user_metadata", "user", ""));
    first.next_event().await.unwrap();
    first.next_event().await.unwrap();
    first.close().await.unwrap();
    assert!(matches!(
        first.next_event().await,
        Err(ProviderError::Closed)
    ));

    let (mut resumed, transport, _) = started_with_resume(OpenCodeGeneration::Legacy1, true).await;
    transport.push(&delta(
        "msg_assistant",
        "prt_reused",
        json!("resumed answer"),
    ));
    transport.push(&part(
        "msg_user_metadata",
        "prt_reused",
        "text",
        "resumed answer",
    ));
    assert_eq!(
        resumed.next_event().await.unwrap().unwrap().payload["streamKind"],
        "assistant_text"
    );
    assert_eq!(
        resumed.next_event().await.unwrap().unwrap().payload["itemType"],
        "assistant_message"
    );
    let requests = transport.http.captured_requests();
    assert_eq!(requests[0].method, "GET");
    assert_eq!(requests[0].path, "http://127.0.0.1:4096/session/ses_native");
    resumed.close().await.unwrap();
}
