use alera_provider_cursor::{CursorProvider, CursorProviderConfig};
use alera_provider_protocol::{
    EventKind, McpServerSpec, McpTransport, Provider, SessionStartInput, TurnInput,
};
use cursor_agent_sdk::{encode_connect_frame, CursorClient, MockBridgeTransport};
use serde_json::json;
use std::collections::BTreeMap;
use std::path::PathBuf;

fn stdio_server() -> McpServerSpec {
    McpServerSpec {
        name: "chat-tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("/opt/chat-mcp"),
            args: vec!["--stdio".into()],
            env: BTreeMap::from([("CHAT_SCOPE".into(), "chat-123".into())]),
            cwd: Some(PathBuf::from("/workspace/project")),
        },
    }
}

fn http_server() -> McpServerSpec {
    McpServerSpec {
        name: "chat-http".into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test/tools".into(),
            headers: BTreeMap::from([("Authorization".into(), "Bearer private".into())]),
        },
    }
}

fn client(mock: MockBridgeTransport) -> CursorClient {
    CursorClient::with_transport(mock, "bridge-token").unwrap()
}

#[tokio::test]
async fn cursor_injects_stdio_and_http_servers_on_create_and_send() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message": "pong"})));
    mock.push_unary(Ok(json!({"protocolVersion": "sdk.v1"})));
    mock.push_unary(Ok(json!({"agentId": "agent-1"})));
    mock.push_stream(vec![]);
    let mut provider = CursorProvider::new(client(mock.clone()), CursorProviderConfig::default());
    let mut input = SessionStartInput::new("chat-thread");
    input.mcp_servers = vec![stdio_server(), http_server()];
    provider.start_session(input).await.unwrap();
    let _ = provider.next_event().await.unwrap();

    let create = &mock.calls()[2].1;
    assert_eq!(
        create["options"]["mcpServers"]["chat-tools"]["stdio"]["command"],
        "/opt/chat-mcp"
    );
    assert_eq!(
        create["options"]["mcpServers"]["chat-tools"]["stdio"]["cwd"],
        "/workspace/project"
    );
    assert_eq!(
        create["options"]["mcpServers"]["chat-http"]["http"]["type"],
        "HTTP_MCP_TRANSPORT_TYPE_HTTP"
    );
    assert_eq!(
        create["options"]["mcpServers"]["chat-http"]["http"]["headers"]["Authorization"],
        "Bearer private"
    );

    provider
        .send_turn(TurnInput::text("chat-thread", "use the tools"))
        .await
        .unwrap();
    let send = &mock.calls()[3].1;
    assert_eq!(
        send["options"]["mcpServers"]["chat-tools"]["stdio"]["args"],
        json!(["--stdio"])
    );
    assert_eq!(
        send["options"]["mcpServers"]["chat-http"]["http"]["url"],
        "https://mcp.example.test/tools"
    );
}

#[tokio::test]
async fn cursor_resume_injects_the_session_mcp_servers() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message": "pong"})));
    mock.push_unary(Ok(json!({"protocolVersion": "sdk.v1"})));
    mock.push_unary(Ok(json!({"agentId": "agent-1"})));
    mock.push_stream(vec![]);
    let mut provider = CursorProvider::new(client(mock.clone()), CursorProviderConfig::default());
    let mut input = SessionStartInput::new("chat-thread");
    input.resume_thread_id = Some("agent-existing".into());
    input.mcp_servers = vec![stdio_server()];
    provider.start_session(input).await.unwrap();
    let resume = &mock.calls()[2];
    assert_eq!(resume.0, "sdk.v1.SdkAgentService/ResumeAgent");
    assert_eq!(
        resume.1["options"]["mcpServers"]["chat-tools"]["stdio"]["env"]["CHAT_SCOPE"],
        "chat-123"
    );
}

#[tokio::test]
async fn cursor_maps_mcp_tool_calls_to_canonical_items() {
    let mock = MockBridgeTransport::default();
    mock.push_unary(Ok(json!({"message": "pong"})));
    mock.push_unary(Ok(json!({"protocolVersion": "sdk.v1"})));
    mock.push_unary(Ok(json!({"agentId": "agent-1"})));
    mock.push_stream(vec![
        encode_connect_frame(&json!({
            "sdkMessage": {"type": "tool_call", "message": {
                "type": "mcp", "callId": "call-1", "args": {
                    "providerIdentifier": "chat-tools", "toolName": "lookup"
                }, "status": "running"
            }}
        }))
        .unwrap(),
        encode_connect_frame(&json!({
            "sdkMessage": {"type": "tool_call", "message": {
                "type": "mcp", "callId": "call-1", "args": {
                    "providerIdentifier": "chat-tools", "toolName": "lookup"
                }, "status": "completed", "result": {"value": "ok"}
            }}
        }))
        .unwrap(),
        encode_connect_frame(&json!({"result": {"status": "finished"}})).unwrap(),
    ]);
    let mut provider = CursorProvider::new(client(mock), CursorProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("chat-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("chat-thread", "lookup"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();

    let started = provider.next_event().await.unwrap().unwrap();
    assert_eq!(started.kind, EventKind::ItemStarted);
    assert_eq!(started.payload["itemType"], "mcp_tool_call");
    assert_eq!(started.payload["title"], "mcp__chat-tools__lookup");
    assert_eq!(
        started
            .provider_refs
            .as_ref()
            .and_then(|refs| refs.provider_item_id.as_deref()),
        Some("call-1")
    );
    assert_eq!(
        started
            .raw
            .as_ref()
            .and_then(|raw| raw.message_type.as_deref()),
        Some("tool_call")
    );

    let completed = provider.next_event().await.unwrap().unwrap();
    assert_eq!(completed.kind, EventKind::ItemCompleted);
    assert_eq!(completed.payload["itemType"], "mcp_tool_call");
}
