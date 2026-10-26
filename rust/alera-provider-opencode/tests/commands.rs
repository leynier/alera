use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{Attachment, EventKind, Provider, SessionStartInput, TurnInput};
use serde_json::{json, Value};

fn response(value: Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).unwrap())
}

/// What a 2.x server answers for `/api/command` once it has scanned the
/// workspace (T3 Code's recorded probe response).
fn v2_commands() -> Value {
    json!({"location":{"directory":"/work"},"data":[
        {"name":"init","description":"guided AGENTS.md setup"},
        {"name":"review","description":"review changes [commit|branch|pr], defaults to uncommitted"},
        {"name":"bee","description":"B command"}
    ]})
}

fn v2_command_list() -> Value {
    json!({"commands":[
        {"name":"compact","description":"Summarize the conversation and reduce context usage"},
        {"name":"init","description":"guided AGENTS.md setup"},
        {"name":"review","description":"review changes [commit|branch|pr], defaults to uncommitted"},
        {"name":"bee","description":"B command"}
    ]})
}

/// A 2.x provider whose session start reads [listing] and whose stream
/// carries [stream].
async fn started(listing: HttpResponse, stream: &[u8]) -> OpenCodeProvider<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(listing);
    transport.push_stream([stream.to_vec()]);
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation: OpenCodeGeneration::V2,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
}

fn requests(provider: &OpenCodeProvider<MockHttpTransport>) -> Vec<(String, String, Value)> {
    provider
        .client()
        .transport()
        .captured_requests()
        .into_iter()
        .map(|request| {
            let body = serde_json::from_slice(&request.body).unwrap_or(Value::Null);
            (request.method, request.path, body)
        })
        .collect()
}

#[tokio::test]
async fn v2_session_start_publishes_compact_then_the_workspace_commands() {
    let mut provider = started(response(v2_commands()), b"").await;
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    commands.validate().unwrap();
    assert_eq!(commands.payload, v2_command_list());
    assert_eq!(
        requests(&provider)[2].1,
        "http://127.0.0.1:4096/api/command"
    );
}

#[tokio::test]
async fn v2_publishes_commands_once_a_first_scan_ends() {
    let stream = concat!(
        "data: {\"type\":\"command.updated\",\"location\":{\"directory\":\"/work\"}}\n\n",
        "data: {\"type\":\"session.status\",\"data\":{\"sessionID\":\"s1\",\"status\":{\"type\":\"idle\"}}}\n\n"
    );
    let mut provider = started(
        response(json!({"location":{"directory":"/work"},"data":[]})),
        stream.as_bytes(),
    )
    .await;
    provider
        .client()
        .transport()
        .push_response(response(v2_commands()));
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert_eq!(commands.payload, v2_command_list());
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStateChanged
    );
}

#[tokio::test]
async fn v2_known_commands_run_through_the_command_route() {
    let mut provider = started(HttpResponse::new(404, Vec::new()), b"").await;
    provider
        .client()
        .transport()
        .push_response(response(v2_commands()));
    provider
        .client()
        .transport()
        .push_response(response(json!({})));
    let turn = provider
        .send_turn(TurnInput::text("thread", "  /review  main\nthen fix it "))
        .await
        .unwrap();
    assert!(turn.native_turn_id.is_none());
    let sent = requests(&provider);
    assert_eq!(sent[3].1, "http://127.0.0.1:4096/api/command");
    assert_eq!(
        (sent[4].0.as_str(), sent[4].1.as_str()),
        ("POST", "http://127.0.0.1:4096/api/session/s1/command")
    );
    assert_eq!(
        sent[4].2,
        json!({"name":"review","text":"main\nthen fix it"})
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
}

#[tokio::test]
async fn v2_unknown_commands_and_commands_with_files_stay_prompts() {
    let mut provider = started(HttpResponse::new(404, Vec::new()), b"").await;
    provider
        .client()
        .transport()
        .push_response(response(v2_commands()));
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    provider
        .send_turn(TurnInput::text("thread", "/nope x"))
        .await
        .unwrap();
    let sent = requests(&provider);
    assert_eq!(sent[3].1, "http://127.0.0.1:4096/api/command");
    assert_eq!(sent[4].1, "http://127.0.0.1:4096/api/session/s1/prompt");
    assert_eq!(sent[4].2["text"], "/nope x");

    let mut provider = started(HttpResponse::new(404, Vec::new()), b"").await;
    provider
        .client()
        .transport()
        .push_response(response(json!({"id":"m1"})));
    let mut input = TurnInput::text("thread", "/review");
    input.attachments = vec![Attachment::Image {
        url: "https://example.invalid/shot.png".into(),
    }];
    provider.send_turn(input).await.unwrap();
    let sent = requests(&provider);
    assert_eq!(sent.len(), 4);
    assert_eq!(sent[3].1, "http://127.0.0.1:4096/api/session/s1/prompt");
    assert_eq!(sent[3].2["text"], "/review");
}

#[tokio::test]
async fn v2_bare_compact_compacts_under_the_turn_prompt_id() {
    let mut provider = started(HttpResponse::new(404, Vec::new()), b"").await;
    provider
        .client()
        .transport()
        .push_response(response(json!({})));
    let turn = provider
        .send_turn(TurnInput::text("thread", " /compact "))
        .await
        .unwrap();
    let sent = requests(&provider);
    assert_eq!(sent.len(), 4);
    assert_eq!(
        (sent[3].0.as_str(), sent[3].1.as_str()),
        ("POST", "http://127.0.0.1:4096/api/session/s1/compact")
    );
    let id = sent[3].2["id"].as_str().unwrap();
    assert!(id.starts_with("msg_"));
    assert_eq!(turn.native_turn_id.as_deref(), Some(id));
}
