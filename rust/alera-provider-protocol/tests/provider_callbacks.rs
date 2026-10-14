use alera_provider_protocol::{
    EventKind, InterruptInput, Provider, ProviderCapabilities, ProviderError, ProviderEvent,
    ProviderKind, ProviderSession, RequestHandler, RequestId, RequestKind, RuntimeRequest,
    RuntimeResponse, SessionStartInput, TurnInput, TurnStartResult,
};
use async_trait::async_trait;
use serde_json::json;
use std::collections::VecDeque;

struct FakeProvider {
    events: VecDeque<Result<Option<ProviderEvent>, ProviderError>>,
    responses: Vec<RuntimeResponse>,
    session: Option<ProviderSession>,
}

impl FakeProvider {
    fn with_event(event: ProviderEvent) -> Self {
        Self {
            events: VecDeque::from([Ok(Some(event))]),
            responses: Vec::new(),
            session: None,
        }
    }
}

#[async_trait]
impl Provider for FakeProvider {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Codex
    }

    fn capabilities(&self) -> ProviderCapabilities {
        ProviderCapabilities {
            approvals: true,
            ..ProviderCapabilities::default()
        }
    }

    fn session(&self) -> Option<&ProviderSession> {
        self.session.as_ref()
    }

    async fn initialize(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }

    async fn start_session(
        &mut self,
        _input: SessionStartInput,
    ) -> Result<ProviderSession, ProviderError> {
        Err(ProviderError::Unsupported("fake provider".into()))
    }

    async fn send_turn(&mut self, _input: TurnInput) -> Result<TurnStartResult, ProviderError> {
        Err(ProviderError::Unsupported("fake provider".into()))
    }

    async fn interrupt(&mut self, _input: InterruptInput) -> Result<(), ProviderError> {
        Err(ProviderError::Unsupported("fake provider".into()))
    }

    async fn respond(&mut self, response: RuntimeResponse) -> Result<(), ProviderError> {
        self.responses.push(response);
        Ok(())
    }

    async fn next_event(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        self.events.pop_front().unwrap_or(Ok(None))
    }

    async fn close(&mut self) -> Result<(), ProviderError> {
        Ok(())
    }
}

struct FixedHandler {
    response: Option<Result<RuntimeResponse, ProviderError>>,
    seen_request_ids: Vec<RequestId>,
}

#[tokio::test]
async fn native_extension_defaults_are_explicitly_unsupported() {
    let mut provider = FakeProvider {
        events: VecDeque::new(),
        responses: Vec::new(),
        session: None,
    };
    assert!(matches!(
        provider
            .steer_turn(TurnInput::text("app", "input"), "native-turn")
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(matches!(
        provider
            .fork_session(alera_provider_protocol::NativeForkInput {
                source_native_thread_id: "source".into(),
                session: SessionStartInput::new("target"),
                boundary: None,
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(matches!(
        provider
            .rollback_session(alera_provider_protocol::NativeRollbackInput {
                thread_id: "app".into(),
                boundary: alera_provider_protocol::NativeRollbackBoundary::RemoveTurns(1),
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(matches!(
        provider
            .rewind_files(alera_provider_protocol::NativeRewindFilesInput {
                thread_id: "app".into(),
                native_user_message_id: "checkpoint".into(),
            })
            .await,
        Err(ProviderError::Unsupported(_))
    ));
    assert_eq!(provider.reasoning_effort_capabilities(), Default::default());
    assert_eq!(provider.native_history_capabilities(), Default::default());
}

impl FixedHandler {
    fn returning(response: RuntimeResponse) -> Self {
        Self {
            response: Some(Ok(response)),
            seen_request_ids: Vec::new(),
        }
    }

    fn failing(message: &str) -> Self {
        Self {
            response: Some(Err(ProviderError::Validation(message.into()))),
            seen_request_ids: Vec::new(),
        }
    }
}

#[async_trait]
impl RequestHandler for FixedHandler {
    async fn handle(&mut self, request: &RuntimeRequest) -> Result<RuntimeResponse, ProviderError> {
        self.seen_request_ids.push(request.request_id.clone());
        self.response
            .take()
            .expect("fixed handler called more than once")
    }
}

fn request_event(request_id: RequestId) -> (ProviderEvent, RuntimeRequest) {
    let request = RuntimeRequest {
        request_id,
        thread_id: "app-thread-1".into(),
        turn_id: Some("turn-1".into()),
        item_id: Some("item-1".into()),
        kind: RequestKind::CommandExecutionApproval,
        questions: Vec::new(),
        payload: json!({ "command": "cargo test" }),
    };
    let event = ProviderEvent::new(
        ProviderKind::Codex,
        "codex-instance",
        request.thread_id.clone(),
        EventKind::RequestOpened,
        json!({ "requestType": "command_execution_approval" }),
        None,
    )
    .with_request(request.clone());
    (event, request)
}

fn resolved_request_event(request_id: RequestId) -> ProviderEvent {
    let (mut event, _) = request_event(request_id);
    event.kind = EventKind::RequestResolved;
    event.payload = json!({
        "requestType": "command_execution_approval",
        "decision": "accept"
    });
    event
}

fn approval(request_id: RequestId) -> RuntimeResponse {
    RuntimeResponse::Approval {
        request_id,
        decision: alera_provider_protocol::ApprovalDecision::Accept,
        updated_input: None,
    }
}

async fn matching_response_is_forwarded_once(request_id: RequestId) {
    let (event, request) = request_event(request_id.clone());
    let response = approval(request_id);
    let mut provider = FakeProvider::with_event(event.clone());
    let mut handler = FixedHandler::returning(response.clone());

    let received = provider.next_event_with(&mut handler).await.unwrap();
    assert_eq!(received, Some(event));
    assert_eq!(handler.seen_request_ids, vec![request.request_id]);
    assert_eq!(provider.responses, vec![response]);

    assert_eq!(provider.next_event_with(&mut handler).await.unwrap(), None);
    assert_eq!(provider.responses.len(), 1);
}

#[tokio::test]
async fn next_event_with_preserves_matching_string_request_id() {
    matching_response_is_forwarded_once(RequestId::String("request-7".into())).await;
}

#[tokio::test]
async fn next_event_with_preserves_matching_integer_request_id() {
    matching_response_is_forwarded_once(RequestId::Integer(7)).await;
}

#[tokio::test]
async fn callback_error_is_returned_without_sending_an_approval() {
    let (event, request) = request_event(RequestId::String("request-7".into()));
    let mut provider = FakeProvider::with_event(event);
    let mut handler = FixedHandler::failing("handler unavailable");

    let result = provider.next_event_with(&mut handler).await;

    assert!(
        matches!(result, Err(ProviderError::Validation(message)) if message == "handler unavailable")
    );
    assert_eq!(handler.seen_request_ids, vec![request.request_id]);
    assert!(provider.responses.is_empty());
}

#[tokio::test]
async fn mismatched_request_id_is_rejected_without_calling_respond() {
    let (event, request) = request_event(RequestId::Integer(7));
    let mut provider = FakeProvider::with_event(event);
    let mut handler = FixedHandler::returning(approval(RequestId::String("7".into())));

    let result = provider.next_event_with(&mut handler).await;

    assert!(
        matches!(result, Err(ProviderError::Validation(message)) if message.contains("request id"))
    );
    assert_eq!(handler.seen_request_ids, vec![request.request_id]);
    assert!(provider.responses.is_empty());
}

#[tokio::test]
async fn resolved_request_event_does_not_invoke_handler_or_respond_again() {
    let event = resolved_request_event(RequestId::String("request-7".into()));
    event.validate().unwrap();
    let mut provider = FakeProvider::with_event(event.clone());
    let mut handler = FixedHandler::failing("resolved request must not be handled");

    let received = provider.next_event_with(&mut handler).await.unwrap();

    assert_eq!(received, Some(event));
    assert!(handler.seen_request_ids.is_empty());
    assert!(provider.responses.is_empty());
}
