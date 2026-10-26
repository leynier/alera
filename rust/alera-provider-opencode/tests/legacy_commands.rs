use alera_provider_opencode::{
    ByteStream, HttpRequest, HttpResponse, HttpTransport, MockHttpTransport, OpenCodeGeneration,
    OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    Attachment, EventKind, Provider, ProviderError, SessionStartInput, TurnInput,
};
use async_trait::async_trait;
use opencode_agent_sdk::HttpError;
use serde_json::{json, Value};
use std::time::Duration;

fn response(value: Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).unwrap())
}

/// What a 1.x server answers for `/command`: its builtins, a project
/// command with argument hints, and a skill exposed as a command.
fn legacy_commands() -> Value {
    json!([
        {"name":"init","description":"create/update AGENTS.md","source":"command","template":"...","hints":[]},
        {"name":"review","description":"review changes [commit|branch|pr], defaults to uncommitted","source":"command","template":"...","hints":["$ARGUMENTS"]},
        {"name":"deploy","description":"Deploy to staging","template":"Deploy $1 to $2","hints":["$1","$2"]},
        {"name":"plum","description":"plum skill","source":"skill","template":"...","hints":[]}
    ])
}

/// A mock that never answers `POST .../command` and whose event stream
/// stays open, for a command the server never admits.
#[derive(Clone, Default)]
struct SilentCommand {
    http: MockHttpTransport,
}

struct OpenStream;

#[async_trait]
impl ByteStream for OpenStream {
    async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpError> {
        std::future::pending().await
    }

    async fn close(&mut self) -> Result<(), HttpError> {
        Ok(())
    }
}

#[async_trait]
impl HttpTransport for SilentCommand {
    async fn request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
        if request.method == "POST" && request.path.ends_with("/command") {
            return std::future::pending().await;
        }
        self.http.request(request).await
    }

    async fn open_stream(&self, _request: HttpRequest) -> Result<Box<dyn ByteStream>, HttpError> {
        Ok(Box::new(OpenStream))
    }
}

async fn started<T: HttpTransport + Clone + 'static>(
    transport: T,
    push: impl Fn(&T, HttpResponse),
    listing: Value,
) -> OpenCodeProvider<T> {
    push(&transport, response(json!({"id":"s1"})));
    push(&transport, response(listing));
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation: OpenCodeGeneration::Legacy1,
            model: Some("anthropic/claude-sonnet-4".into()),
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider
}

async fn mock(stream: &str) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_stream([stream.as_bytes().to_vec()]);
    started(
        transport,
        MockHttpTransport::push_response,
        legacy_commands(),
    )
    .await
}

fn sent(provider: &OpenCodeProvider<MockHttpTransport>) -> Vec<(String, Value)> {
    provider
        .client()
        .transport()
        .captured_requests()
        .into_iter()
        .map(|request| {
            let body = serde_json::from_slice(&request.body).unwrap_or(Value::Null);
            (format!("{} {}", request.method, request.path), body)
        })
        .collect()
}

#[tokio::test]
async fn session_start_lists_compact_then_commands_with_their_hints() {
    let mut provider = mock("").await;
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert_eq!(
        commands.payload,
        json!({"commands":[
            {"name":"compact","description":"Summarize the conversation and reduce context usage"},
            {"name":"init","description":"create/update AGENTS.md"},
            {"name":"review","description":"review changes [commit|branch|pr], defaults to uncommitted","input":{"hint":"$ARGUMENTS"}},
            {"name":"deploy","description":"Deploy to staging","input":{"hint":"$1 $2"}}
        ]})
    );
    assert_eq!(sent(&provider)[2].0, "GET http://127.0.0.1:4096/command");
}

#[tokio::test]
async fn known_commands_run_beside_the_stream_with_the_turn_message_id() {
    let mut provider =
        mock("data: {\"type\":\"session.idle\",\"properties\":{\"sessionID\":\"s1\"}}\n\n").await;
    let transport = provider.client().transport().clone();
    transport.push_response(response(legacy_commands()));
    transport.push_response(response(json!({"info":{"id":"msg_reply"},"parts":[]})));
    let mut input = TurnInput::text("thread", "/deploy web staging");
    input.attachments = vec![Attachment::Image {
        url: "https://example.invalid/shot.png".into(),
    }];
    let turn = provider.send_turn(input).await.unwrap();
    // Let the command request reach the server before the stream ends the turn.
    tokio::time::sleep(Duration::from_millis(20)).await;
    for kind in [
        EventKind::ThreadStarted,
        EventKind::SessionCommandsUpdated,
        EventKind::TurnStarted,
        EventKind::TurnCompleted,
    ] {
        assert_eq!(provider.next_event().await.unwrap().unwrap().kind, kind);
    }
    let sent = sent(&provider);
    assert_eq!(sent[3].0, "GET http://127.0.0.1:4096/command");
    assert_eq!(sent[4].0, "POST http://127.0.0.1:4096/session/s1/command");
    assert_eq!(
        sent[4].1,
        json!({
            "messageID": turn.native_turn_id.unwrap(),
            "command": "deploy",
            "arguments": "web staging",
            "model": "anthropic/claude-sonnet-4",
            "parts": [{"type":"file","url":"https://example.invalid/shot.png","mime":"image/*"}]
        })
    );
}

#[tokio::test]
async fn a_failed_command_request_fails_the_turn() {
    let mut provider = mock("").await;
    let transport = provider.client().transport().clone();
    transport.push_response(response(legacy_commands()));
    transport.push_response(HttpResponse::new(
        400,
        br#"{"name":"BadRequest","data":{"message":"Command failed"}}"#.to_vec(),
    ));
    provider
        .send_turn(TurnInput::text("thread", "/review"))
        .await
        .unwrap();
    for _ in 0..3 {
        provider.next_event().await.unwrap().unwrap();
    }
    // The empty stream would end first; let the request finish.
    tokio::time::sleep(Duration::from_millis(20)).await;
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "failed");
    assert!(completed.payload["errorMessage"]
        .as_str()
        .unwrap()
        .contains("HTTP 400"));
    assert!(provider.session().unwrap().active_turn_id.is_none());
}

#[tokio::test(start_paused = true)]
async fn a_command_the_server_never_admits_fails_after_ten_seconds() {
    let mut provider = started(
        SilentCommand::default(),
        |transport, response| transport.http.push_response(response),
        legacy_commands(),
    )
    .await;
    provider
        .client()
        .transport()
        .http
        .push_response(response(legacy_commands()));
    provider
        .send_turn(TurnInput::text("thread", "/review"))
        .await
        .unwrap();
    for _ in 0..3 {
        provider.next_event().await.unwrap().unwrap();
    }
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(
        completed.payload["errorMessage"],
        "OpenCode command admission did not complete within 10 seconds."
    );
}

#[tokio::test]
async fn unknown_commands_stay_prompts() {
    let mut provider = mock("").await;
    let transport = provider.client().transport().clone();
    transport.push_response(response(legacy_commands()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    provider
        .send_turn(TurnInput::text("thread", "/nope now"))
        .await
        .unwrap();
    let sent = sent(&provider);
    assert_eq!(
        sent[4].0,
        "POST http://127.0.0.1:4096/session/s1/prompt_async"
    );
    assert_eq!(
        sent[4].1["parts"],
        json!([{"type":"text","text":"/nope now"}])
    );
}

#[tokio::test]
async fn bare_compact_summarizes_with_the_turn_model_and_ends_the_turn() {
    let mut provider = mock("").await;
    provider
        .client()
        .transport()
        .push_response(response(json!(true)));
    provider
        .send_turn(TurnInput::text("thread", "/compact"))
        .await
        .unwrap();
    for _ in 0..3 {
        provider.next_event().await.unwrap().unwrap();
    }
    tokio::time::sleep(Duration::from_millis(20)).await;
    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "completed");
    let sent = sent(&provider);
    assert_eq!(sent.len(), 4);
    assert_eq!(
        sent[3],
        (
            "POST http://127.0.0.1:4096/session/s1/summarize".to_owned(),
            json!({"providerID":"anthropic","modelID":"claude-sonnet-4","auto":false})
        )
    );
}

#[tokio::test]
async fn compact_without_a_provider_model_is_rejected() {
    let mut provider = mock("").await;
    let mut input = TurnInput::text("thread", "/compact");
    input.model = Some("default".into());
    let error = provider.send_turn(input).await.unwrap_err();
    assert!(matches!(error, ProviderError::Validation(_)));
    assert!(provider.session().unwrap().active_turn_id.is_none());
}
