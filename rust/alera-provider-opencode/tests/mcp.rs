use alera_provider_opencode::{
    HttpResponse, MockHttpTransport, OpenCodeGeneration, OpenCodeProvider, OpenCodeProviderConfig,
};
use alera_provider_protocol::{
    EventKind, McpServerSpec, McpTransport, Provider, SessionStartInput, TurnInput,
};
use serde_json::json;
use std::collections::BTreeMap;
use std::path::PathBuf;

fn response(value: serde_json::Value) -> HttpResponse {
    HttpResponse::new(200, serde_json::to_vec(&value).expect("JSON fixture"))
}

fn empty_mcp_list() -> HttpResponse {
    response(json!({"location":{"directory":"/workspace"},"data":[]}))
}

fn remote_server(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test".into(),
            headers: BTreeMap::from([("Authorization".into(), "Bearer token".into())]),
        },
    }
}

fn local_server(name: &str) -> McpServerSpec {
    McpServerSpec {
        name: name.into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("node"),
            args: vec!["server.js".into()],
            env: BTreeMap::new(),
            cwd: None,
        },
    }
}

#[tokio::test]
async fn injects_and_removes_v2_mcp_servers_for_one_session() {
    let transport = MockHttpTransport::new();
    transport.push_response(empty_mcp_list());
    transport.push_response(response(json!({"id":"session-1"})));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_stream(std::iter::empty::<Vec<u8>>());
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.expect("initialize");
    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers.push(remote_server("alera-chat-1"));
    provider.start_session(input).await.expect("start");
    assert!(provider.capabilities().mcp_injection.http);
    provider.close().await.expect("close");
    let requests = provider.client().transport().captured_requests();
    assert_eq!(requests[0].method, "GET");
    assert_eq!(requests[0].path, "http://127.0.0.1:4096/api/mcp");
    let create: serde_json::Value = serde_json::from_slice(&requests[1].body).expect("create body");
    assert_eq!(create["permissions"][0]["action"], "alera-*");
    assert_eq!(create["permissions"][0]["effect"], "deny");
    assert_eq!(create["permissions"][1]["action"], "alera_*");
    assert_eq!(create["permissions"][1]["effect"], "deny");
    assert_eq!(create["permissions"][2]["action"], "alera-chat-1_*");
    assert_eq!(create["permissions"][2]["effect"], "allow");
    assert_eq!(requests[2].method, "PUT");
    assert_eq!(
        requests[2].path,
        "http://127.0.0.1:4096/api/experimental/mcp/alera-chat-1"
    );
    let add: serde_json::Value = serde_json::from_slice(&requests[2].body).expect("add body");
    assert_eq!(add["config"]["type"], "remote");
    assert_eq!(requests[4].method, "DELETE");
    assert_eq!(
        requests[4].path,
        "http://127.0.0.1:4096/api/experimental/mcp/alera-chat-1"
    );
}

#[tokio::test]
async fn rejects_mcp_injection_on_external_server_before_http() {
    let transport = MockHttpTransport::new();
    let config = OpenCodeProviderConfig {
        server_url: Some("https://shared.example.test".into()),
        ..OpenCodeProviderConfig::default()
    };
    let mut provider = OpenCodeProvider::new(transport, config);
    provider.initialize().await.expect("initialize");
    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers.push(remote_server("alera-chat-1"));
    let error = provider
        .start_session(input)
        .await
        .expect_err("must reject");
    assert!(error.to_string().contains("provider-owned local server"));
    assert!(provider.client().transport().captured_requests().is_empty());
}

#[tokio::test]
async fn failed_resume_cleans_partially_installed_mcp_servers() {
    let transport = MockHttpTransport::new();
    transport.push_response(empty_mcp_list());
    transport.push_response(response(json!({"id":"session-1"})));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(HttpResponse::new(500, br#"{"error":"rejected"}"#.to_vec()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.expect("initialize");
    let mut input = SessionStartInput::new("chat-1");
    input.resume_thread_id = Some("session-1".into());
    input.mcp_servers.push(local_server("one"));
    input.mcp_servers.push(remote_server("two"));
    let error = provider.start_session(input).await.expect_err("must fail");
    assert!(error.to_string().contains("MCP cleanup") || error.to_string().contains("HTTP"));
    let requests = provider.client().transport().captured_requests();
    assert_eq!(
        requests[1].path,
        "http://127.0.0.1:4096/api/session/session-1"
    );
    assert_eq!(requests[0].method, "GET");
    assert_eq!(requests[2].method, "PATCH");
    assert_eq!(requests[3].method, "PUT");
    assert_eq!(requests[4].method, "PUT");
    assert_eq!(requests[5].method, "DELETE");
    assert_eq!(
        requests[5].path,
        "http://127.0.0.1:4096/api/experimental/mcp/one"
    );
}

#[tokio::test]
async fn native_mcp_tool_events_use_canonical_item_type_and_refs() {
    let transport = MockHttpTransport::new();
    transport.push_response(empty_mcp_list());
    transport.push_response(response(json!({"id":"session-1"})));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(response(json!({"id":"message-1"})));
    transport.push_stream([br#"data: {"type":"session.tool.input.started","data":{"sessionID":"session-1","id":"call-1","assistantMessageID":"message-1","name":"docs_search"}}

data: {"type":"session.tool.success","data":{"sessionID":"session-1","id":"call-1","assistantMessageID":"message-1","content":[{"type":"text","text":"ok"}]}}

"#.to_vec()]);
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            generation: OpenCodeGeneration::V2,
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.expect("initialize");
    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers.push(local_server("docs"));
    let session = provider.start_session(input).await.expect("start");
    provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "search"))
        .await
        .expect("turn");
    let _ = provider.next_event().await.expect("thread");
    let _ = provider.next_event().await.expect("turn");
    let started = provider
        .next_event()
        .await
        .expect("tool start")
        .expect("event");
    assert_eq!(started.kind, EventKind::ItemStarted);
    assert_eq!(started.item_id.as_deref(), Some("call-1"));
    assert_eq!(started.payload["itemType"], "mcp_tool_call");
    assert_eq!(
        started
            .provider_refs
            .as_ref()
            .unwrap()
            .provider_item_id
            .as_deref(),
        Some("call-1")
    );
    let completed = provider
        .next_event()
        .await
        .expect("tool complete")
        .expect("event");
    assert_eq!(completed.kind, EventKind::ItemCompleted);
    assert_eq!(completed.payload["itemType"], "mcp_tool_call");
}

#[tokio::test]
async fn normalized_input_collisions_are_rejected_before_http() {
    for generation in [OpenCodeGeneration::Legacy1, OpenCodeGeneration::V2] {
        let transport = MockHttpTransport::new();
        let mut provider = OpenCodeProvider::new(
            transport,
            OpenCodeProviderConfig {
                generation,
                ..OpenCodeProviderConfig::default()
            },
        );
        provider.initialize().await.unwrap();
        let mut input = SessionStartInput::new("chat-1");
        input.mcp_servers = vec![local_server("foo.bar"), remote_server("foo_bar")];
        let error = provider.start_session(input).await.unwrap_err();
        assert!(error.to_string().contains("share a native tool namespace"));
        assert!(provider.client().transport().captured_requests().is_empty());
        assert!(provider.session().is_none());
    }
}

#[tokio::test]
async fn configured_exact_and_normalized_collisions_precede_session_mutation() {
    for generation in [OpenCodeGeneration::Legacy1, OpenCodeGeneration::V2] {
        for resume in [false, true] {
            for (existing, injected) in [
                ("foo.bar", "foo.bar"),
                ("foo.bar", "foo_bar"),
                ("foo_bar", "foo.bar"),
            ] {
                let transport = MockHttpTransport::new();
                let body = match generation {
                    OpenCodeGeneration::Legacy1 => json!({(existing):{"status":"disabled"}}),
                    OpenCodeGeneration::V2 => json!({
                        "location":{"directory":"/workspace"},
                        "data":[{"name":existing,"status":{"status":"disabled"}}]
                    }),
                };
                transport.push_response(response(body));
                let mut provider = OpenCodeProvider::new(
                    transport,
                    OpenCodeProviderConfig {
                        generation,
                        ..OpenCodeProviderConfig::default()
                    },
                );
                provider.initialize().await.unwrap();
                let mut input = SessionStartInput::new("chat-1");
                input.resume_thread_id = resume.then(|| "session-1".into());
                input.mcp_servers.push(local_server(injected));
                let error = provider.start_session(input).await.unwrap_err();
                assert!(error
                    .to_string()
                    .contains("collides with a configured native server"));
                let requests = provider.client().transport().captured_requests();
                assert_eq!(requests.len(), 1);
                assert_eq!(requests[0].method, "GET");
                assert!(requests[0].path.ends_with("/mcp"));
                assert!(provider.session().is_none());
                provider.close().await.unwrap();
                assert_eq!(provider.client().transport().captured_requests().len(), 1);
            }
        }
    }
}

#[tokio::test]
async fn failed_or_malformed_preflight_refuses_all_mutations() {
    for generation in [OpenCodeGeneration::Legacy1, OpenCodeGeneration::V2] {
        for preflight in [
            HttpResponse::new(503, br#"{"error":"unavailable"}"#.to_vec()),
            response(json!({"unexpected":true})),
        ] {
            let transport = MockHttpTransport::new();
            transport.push_response(preflight);
            let mut provider = OpenCodeProvider::new(
                transport,
                OpenCodeProviderConfig {
                    generation,
                    ..OpenCodeProviderConfig::default()
                },
            );
            provider.initialize().await.unwrap();
            let mut input = SessionStartInput::new("chat-1");
            input.resume_thread_id = Some("session-1".into());
            input.mcp_servers.push(local_server("docs"));
            provider
                .start_session(input)
                .await
                .expect_err("preflight must refuse");
            assert!(provider.session().is_none());
            provider.close().await.unwrap();
            let requests = provider.client().transport().captured_requests();
            assert_eq!(requests.len(), 1);
            assert_eq!(requests[0].method, "GET");
        }
    }
}

#[tokio::test]
async fn distinct_hyphen_namespace_uses_one_directory_for_preflight_and_install() {
    let transport = MockHttpTransport::new();
    transport.push_response(empty_mcp_list());
    transport.push_response(response(json!({"id":"session-1"})));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_stream(std::iter::empty::<Vec<u8>>());
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut provider = OpenCodeProvider::new(
        transport,
        OpenCodeProviderConfig {
            directory: Some(PathBuf::from("/configured/project")),
            ..OpenCodeProviderConfig::default()
        },
    );
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("chat-1");
    input.cwd = Some(PathBuf::from("/other/project"));
    input.mcp_servers = vec![local_server("alera.chat"), local_server("alera-chat")];
    provider.start_session(input).await.unwrap();
    provider.close().await.unwrap();
    let requests = provider.client().transport().captured_requests();
    assert!(requests
        .iter()
        .all(|request| request.path.ends_with("?directory=%2Fother%2Fproject")));
    let create: serde_json::Value = serde_json::from_slice(&requests[1].body).unwrap();
    assert_eq!(create["permissions"][0]["action"], "alera-*");
    assert_eq!(create["permissions"][1]["action"], "alera_*");
    assert_eq!(create["permissions"][2]["action"], "alera_chat_*");
    assert_eq!(create["permissions"][2]["effect"], "allow");
    assert_eq!(create["permissions"][3]["action"], "alera-chat_*");
    assert_eq!(create["permissions"][3]["effect"], "allow");
}

#[tokio::test]
async fn failed_event_subscription_removes_only_installed_chat_servers() {
    let transport = MockHttpTransport::new();
    transport.push_response(response(json!({
        "location":{"directory":"/workspace"},
        "data":[{"name":"user-tools","status":{"status":"connected"}}]
    })));
    transport.push_response(response(json!({"id":"session-1"})));
    transport.push_response(HttpResponse::new(204, Vec::new()));
    transport.push_stream_error(opencode_agent_sdk::HttpError::Request {
        operation: "stream",
    });
    transport.push_response(HttpResponse::new(204, Vec::new()));
    let mut provider = OpenCodeProvider::new(transport, OpenCodeProviderConfig::default());
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers.push(local_server("docs"));
    provider
        .start_session(input)
        .await
        .expect_err("stream must fail");
    assert!(provider.session().is_none());
    provider.close().await.unwrap();
    let requests = provider.client().transport().captured_requests();
    let removals = requests
        .iter()
        .filter(|request| request.method == "DELETE")
        .collect::<Vec<_>>();
    assert_eq!(removals.len(), 1);
    assert_eq!(
        removals[0].path,
        "http://127.0.0.1:4096/api/experimental/mcp/docs"
    );
    assert!(!requests
        .iter()
        .any(|request| request.path.contains("user-tools")));
}
