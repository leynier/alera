use opencode_agent_sdk::{
    ClientConfig, Generation, HttpResponse, McpServerConfig, MockHttpTransport, OpenCodeClient,
    PermissionRule, SessionRequest,
};
use serde_json::json;
use std::collections::BTreeMap;

fn response(value: serde_json::Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).expect("JSON fixture"))
}

#[tokio::test]
async fn v2_prompt_uses_api_route_and_utf8_basic_auth() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(response(json!({"ok":true})));
    let config = ClientConfig {
        base_url: "http://localhost:4096".into(),
        password: Some("päss".into()),
        generation: Generation::V2,
        ..ClientConfig::default()
    };
    let mut client = OpenCodeClient::new(transport, config);
    let session = client
        .create_session(SessionRequest::default())
        .await
        .expect("session");
    assert_eq!(session.id, "s1");
    client
        .prompt_parts_with_id(
            "s1",
            vec![
                json!({"type":"text","text":"hello"}),
                json!({"type":"file","url":"https://example.test/image.png"}),
            ],
            Some("anthropic/claude"),
            Some("message-1"),
        )
        .await
        .expect("prompt");
    let requests = client.transport().captured_requests();
    assert_eq!(requests[0].path, "http://localhost:4096/api/session");
    assert_eq!(
        requests[1].path,
        "http://localhost:4096/api/session/s1/prompt"
    );
    assert_eq!(
        requests[1].headers["authorization"],
        "Basic b3BlbmNvZGU6cMOkc3M="
    );
    let body: serde_json::Value = serde_json::from_slice(&requests[1].body).expect("prompt body");
    assert_eq!(body["text"], "hello");
    assert_eq!(body["files"][0]["uri"], "https://example.test/image.png");
    assert_eq!(body["id"], "message-1");
    assert_eq!(body["model"]["modelID"], "claude");
}

#[tokio::test]
async fn legacy_prompt_keeps_v1_route() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({"id":"s1"})));
    transport.push_response(response(json!({"id":"m1"})));
    let mut client = OpenCodeClient::new(
        transport,
        ClientConfig {
            generation: Generation::Legacy1,
            ..ClientConfig::default()
        },
    );
    client
        .create_session(SessionRequest::default())
        .await
        .expect("session");
    client.prompt("s1", "hello", None).await.expect("prompt");
    let requests = client.transport().captured_requests();
    assert_eq!(
        requests[1].path,
        "http://127.0.0.1:4096/session/s1/prompt_async"
    );
}

#[tokio::test]
async fn v2_model_catalog_uses_model_route() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({
        "data": [{"id":"anthropic/claude","modelID":"claude","providerID":"anthropic","name":"Claude"}]
    })));
    let mut client = OpenCodeClient::new(transport, ClientConfig::default());
    let models = client.list_models().await.expect("models");
    assert_eq!(models[0].provider_id, "anthropic");
    assert_eq!(models[0].model_id, "claude");
    assert_eq!(
        client.transport().captured_requests()[0].path,
        "http://127.0.0.1:4096/api/model"
    );
}

#[tokio::test]
async fn v2_sse_keeps_unreadable_execution_end() {
    let transport = MockHttpTransport::new();
    transport.push_stream([
        b"data: {\"type\":\"future.execution.failed\",\"data\":{\"sessionID\":\"s1\"}}\n\n"
            .to_vec(),
    ]);
    let mut client = OpenCodeClient::new(transport, ClientConfig::default());
    client.start_events().await.expect("event stream");
    assert_eq!(
        client.transport().captured_requests()[0].path,
        "http://127.0.0.1:4096/api/event"
    );
    let event = client.next_event().await.expect("event");
    let event = event.expect("terminal sentinel");
    assert_eq!(event.event_type, "unreadable.execution.ended");
    assert!(event.terminal);
}

#[tokio::test]
async fn v2_mcp_add_and_remove_keep_server_name_and_directory_scope() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut client = OpenCodeClient::new(
        transport,
        ClientConfig {
            directory: Some("/workspace/project".into()),
            ..ClientConfig::default()
        },
    );
    let mut headers = BTreeMap::new();
    headers.insert("Authorization".into(), "Bearer token".into());
    client
        .add_mcp_server(
            "alera-chat-1",
            McpServerConfig::Remote {
                url: "https://mcp.example.test".into(),
                headers,
            },
        )
        .await
        .expect("add MCP");
    client
        .remove_mcp_server("alera-chat-1")
        .await
        .expect("remove MCP");
    let requests = client.transport().captured_requests();
    assert_eq!(
        requests[0].path,
        "http://127.0.0.1:4096/api/experimental/mcp/alera-chat-1?directory=%2Fworkspace%2Fproject"
    );
    assert_eq!(requests[0].method, "PUT");
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).expect("add body");
    assert_eq!(body["config"]["type"], "remote");
    assert_eq!(body["config"]["url"], "https://mcp.example.test");
    assert_eq!(body["config"]["oauth"], false);
    assert_eq!(
        requests[1].path,
        "http://127.0.0.1:4096/api/experimental/mcp/alera-chat-1?directory=%2Fworkspace%2Fproject"
    );
    assert_eq!(requests[1].method, "DELETE");
    assert!(requests[1].body.is_empty());
}

#[tokio::test]
async fn legacy_mcp_add_and_disconnect_use_v1_routes() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(200, br#"{"connected":true}"#.to_vec()));
    transport.push_response(HttpResponse::new(200, br#"{"connected":false}"#.to_vec()));
    let mut client = OpenCodeClient::new(
        transport,
        ClientConfig {
            generation: Generation::Legacy1,
            directory: Some("/workspace/project".into()),
            ..ClientConfig::default()
        },
    );
    client
        .add_mcp_server(
            "local-tools",
            McpServerConfig::Local {
                command: vec!["node".into(), "server.js".into()],
                cwd: Some("/workspace/project".into()),
                environment: BTreeMap::from([("TOKEN".into(), "secret".into())]),
            },
        )
        .await
        .expect("add MCP");
    client
        .remove_mcp_server("local-tools")
        .await
        .expect("disconnect MCP");
    let requests = client.transport().captured_requests();
    assert_eq!(
        requests[0].path,
        "http://127.0.0.1:4096/mcp?directory=%2Fworkspace%2Fproject"
    );
    assert_eq!(requests[0].method, "POST");
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).expect("add body");
    assert_eq!(body["name"], "local-tools");
    assert_eq!(body["config"]["type"], "local");
    assert_eq!(body["config"]["command"][1], "server.js");
    assert_eq!(
        requests[1].path,
        "http://127.0.0.1:4096/mcp/local-tools/disconnect?directory=%2Fworkspace%2Fproject"
    );
    assert_eq!(requests[1].method, "POST");
}

#[tokio::test]
async fn v2_session_permission_rules_use_patch_route() {
    let transport = MockHttpTransport::new();
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut client = OpenCodeClient::new(transport, ClientConfig::default());
    client
        .update_session_permissions(
            "s1",
            vec![PermissionRule {
                action: "alera-*".into(),
                resource: "*".into(),
                effect: "deny".into(),
            }],
        )
        .await
        .expect("permissions");
    let request = &client.transport().captured_requests()[0];
    assert_eq!(request.method, "PATCH");
    assert_eq!(request.path, "http://127.0.0.1:4096/api/session/s1");
    let body: serde_json::Value = serde_json::from_slice(&request.body).expect("permissions body");
    assert_eq!(body["permissions"][0]["action"], "alera-*");
}
