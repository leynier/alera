use opencode_agent_sdk::{
    ClientConfig, CommandRequest, Generation, HttpResponse, MockHttpTransport, OpenCodeClient,
    OpenCodeError,
};
use serde_json::{json, Value};

fn client(generation: Generation) -> OpenCodeClient<MockHttpTransport> {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(200, b"{}".to_vec()));
    OpenCodeClient::new(
        transport,
        ClientConfig {
            generation,
            ..ClientConfig::default()
        },
    )
}

fn last(client: &OpenCodeClient<MockHttpTransport>) -> (String, Value) {
    let request = client.transport().captured_requests().pop().unwrap();
    (request.path, serde_json::from_slice(&request.body).unwrap())
}

fn request() -> CommandRequest {
    CommandRequest {
        name: "review".into(),
        arguments: "main".into(),
        message_id: Some("msg_1".into()),
        model: Some("anthropic/claude".into()),
        files: vec![json!({"type":"file","url":"https://example.invalid/a.png","mime":"image/*"})],
    }
}

#[tokio::test]
async fn v2_commands_send_only_name_and_text() {
    let mut client = client(Generation::V2);
    client.run_command("s1", request()).await.unwrap();
    assert_eq!(
        last(&client),
        (
            "http://127.0.0.1:4096/api/session/s1/command".into(),
            json!({"name":"review","text":"main"})
        )
    );
}

#[tokio::test]
async fn legacy_commands_carry_message_model_and_files() {
    let mut client = client(Generation::Legacy1);
    client.run_command("s1", request()).await.unwrap();
    assert_eq!(
        last(&client),
        (
            "http://127.0.0.1:4096/session/s1/command".into(),
            json!({
                "messageID":"msg_1",
                "command":"review",
                "arguments":"main",
                "model":"anthropic/claude",
                "parts":[{"type":"file","url":"https://example.invalid/a.png","mime":"image/*"}]
            })
        )
    );
}

#[tokio::test]
async fn compaction_routes_differ_by_generation() {
    let mut client_v2 = client(Generation::V2);
    client_v2
        .compact_session("s1", Some("msg_1"), None)
        .await
        .unwrap();
    assert_eq!(
        last(&client_v2),
        (
            "http://127.0.0.1:4096/api/session/s1/compact".into(),
            json!({"id":"msg_1"})
        )
    );
    let mut legacy = client(Generation::Legacy1);
    legacy
        .compact_session("s1", None, Some("anthropic/claude"))
        .await
        .unwrap();
    assert_eq!(
        last(&legacy),
        (
            "http://127.0.0.1:4096/session/s1/summarize".into(),
            json!({"providerID":"anthropic","modelID":"claude","auto":false})
        )
    );
    assert!(matches!(
        legacy.compact_session("s1", None, Some("default")).await,
        Err(OpenCodeError::Unsupported(_))
    ));
}
