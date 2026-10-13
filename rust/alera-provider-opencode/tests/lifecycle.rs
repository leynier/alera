use alera_provider_opencode::opencode_agent_sdk::HttpError;
use alera_provider_opencode::{
    ByteStream, HttpRequest, HttpResponse, HttpTransport, MockHttpTransport, OpenCodeGeneration,
    OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    EventKind, InterruptInput, Provider, RuntimeMode, SessionStartInput, TurnInput,
};
use async_trait::async_trait;
use serde_json::json;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

struct DelayedStream {
    chunks: VecDeque<Vec<u8>>,
    delay: Duration,
    closed: bool,
}

#[async_trait]
impl ByteStream for DelayedStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        if self.closed {
            return Err(HttpError::Closed);
        }
        let Some(chunk) = self.chunks.pop_front() else {
            self.closed = true;
            return Ok(None);
        };
        tokio::time::sleep(self.delay).await;
        Ok(Some(chunk))
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        self.closed = true;
        self.chunks.clear();
        Ok(())
    }
}

#[derive(Clone)]
struct DelayedTransport {
    responses: Arc<Mutex<VecDeque<HttpResponse>>>,
    chunks: Arc<Mutex<VecDeque<Vec<u8>>>>,
    delay: Duration,
}

impl DelayedTransport {
    fn new(delay: Duration, chunks: impl IntoIterator<Item = Vec<u8>>) -> Self {
        Self {
            responses: Arc::new(Mutex::new(VecDeque::new())),
            chunks: Arc::new(Mutex::new(chunks.into_iter().collect())),
            delay,
        }
    }

    fn push_response(&self, response: HttpResponse) {
        self.responses.lock().unwrap().push_back(response);
    }
}

#[async_trait]
impl HttpTransport for DelayedTransport {
    async fn request(&self, _request: HttpRequest) -> Result<HttpResponse, HttpError> {
        self.responses
            .lock()
            .map_err(|_| HttpError::Request {
                operation: "test response lock",
            })?
            .pop_front()
            .ok_or(HttpError::MockScriptExhausted)
    }

    async fn open_stream(&self, _request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        let chunks = self
            .chunks
            .lock()
            .map_err(|_| HttpError::Request {
                operation: "test stream lock",
            })?
            .drain(..)
            .collect();
        Ok(Box::new(DelayedStream {
            chunks,
            delay: self.delay,
            closed: false,
        }))
    }
}

fn provider_with_stream(
    generation: OpenCodeGeneration,
    stream: &[u8],
) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"session-1"})).unwrap(),
    ));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"message-1"})).unwrap(),
    ));
    transport.push_stream([stream.to_vec()]);
    OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation,
            ..OpenCodeProviderConfig::default()
        },
    )
}

#[tokio::test]
async fn v2_session_prompt_stream_and_idle_complete_turn() {
    let stream = br#"data: {"type":"session.text.delta","data":{"sessionID":"session-1","assistantMessageID":"message-1","ordinal":0,"delta":"hello"}}

data: {"type":"session.execution.succeeded","properties":{"sessionID":"session-1"}}

"#;
    let mut provider = provider_with_stream(OpenCodeGeneration::V2, stream);
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
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
    let delta = provider.next_event().await.unwrap().unwrap();
    assert_eq!(delta.kind, EventKind::ContentDelta);
    assert_eq!(delta.payload["delta"], "hello");
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.payload["state"], "completed");
    assert!(provider.session().unwrap().active_turn_id.is_none());
}

#[tokio::test]
async fn legacy_generation_uses_message_route() {
    let mut provider = provider_with_stream(
        OpenCodeGeneration::Legacy1,
        b"data: {\"type\":\"session.idle\"}\n\n",
    );
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
        .await
        .unwrap();
    let requests = provider.client().transport().captured_requests();
    assert!(requests
        .iter()
        .any(|request| request.path == "http://127.0.0.1:4096/session/session-1/prompt_async"));
}

#[tokio::test]
async fn overlapping_turns_are_rejected() {
    let mut provider = provider_with_stream(
        OpenCodeGeneration::V2,
        b"data: {\"type\":\"session.idle\"}\n\n",
    );
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "one"))
        .await
        .unwrap();
    let error = provider
        .send_turn(TurnInput::text(session.thread_id, "two"))
        .await
        .unwrap_err();
    assert!(error.to_string().contains("another turn is active"));
}

#[tokio::test]
async fn unsupported_session_policy_is_rejected_before_http() {
    let mut provider = provider_with_stream(OpenCodeGeneration::V2, b"");
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.runtime_mode = RuntimeMode::FullAccess;
    let error = provider.start_session(input).await.unwrap_err();
    assert!(error
        .to_string()
        .contains("runtime mode policy is not implemented"));
    assert!(provider.client().transport().captured_requests().is_empty());
}

#[tokio::test]
async fn interrupt_waits_for_v2_execution_terminal() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"session-1"})).unwrap(),
    ));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"message-1"})).unwrap(),
    ));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"interrupted":true})).unwrap(),
    ));
    transport.push_stream([
        br#"data: {"type":"session.execution.interrupted","data":{"sessionID":"session-1"}}

"#
        .to_vec(),
    ]);
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let turn = provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .interrupt(InterruptInput {
            thread_id: session.thread_id,
            turn_id: Some(turn.turn_id),
        })
        .await
        .unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.payload["state"], "interrupted");
}

#[tokio::test]
async fn event_stream_reads_are_not_limited_by_request_timeout() {
    let transport = DelayedTransport::new(
        Duration::from_millis(20),
        [
            b": heartbeat\n\n".to_vec(),
            br#"data: {"type":"session.heartbeat","properties":{"sessionID":"session-1"}}

"#
            .to_vec(),
            br#"data: {"type":"session.execution.succeeded","properties":{"sessionID":"session-1"}}

"#
            .to_vec(),
        ],
    );
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"session-1"})).unwrap(),
    ));
    transport.push_response(HttpResponse::new(
        200,
        serde_json::to_vec(&json!({"id":"message-1"})).unwrap(),
    ));
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            request_timeout: Duration::from_millis(5),
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(terminal.payload["state"], "completed");
}
