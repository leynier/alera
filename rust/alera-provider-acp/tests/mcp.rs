use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, McpServerSpec, McpTransport, Provider, ProviderError, ProviderKind,
    SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

fn config() -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("acp-test".into()),
        provider_instance_id: "mcp-test".into(),
        flavor: AcpFlavor::Generic,
        ..AcpProviderConfig::default()
    }
}

fn v1_initialize(mcp: Value, load: bool) -> Value {
    json!({
        "jsonrpc":"2.0",
        "id":1,
        "result":{
            "protocolVersion":1,
            "agentCapabilities":{
                "loadSession":load,
                "mcpCapabilities":mcp,
                "sessionCapabilities":{"resume":{}}
            },
            "authMethods":[]
        }
    })
}

fn v2_initialize(mcp: Value) -> Value {
    json!({
        "jsonrpc":"2.0",
        "id":1,
        "result":{
            "protocolVersion":2,
            "info":{"name":"fixture","version":"1"},
            "agentCapabilities":{
                "sessionCapabilities":{
                    "resume":{},
                    "mcp":mcp
                }
            },
            "authMethods":[]
        }
    })
}

fn v2_session_initialize(session: Value) -> Value {
    json!({
        "jsonrpc":"2.0",
        "id":1,
        "result":{
            "protocolVersion":2,
            "info":{"name":"fixture","version":"1"},
            "capabilities":{"session":session},
            "authMethods":[]
        }
    })
}

fn stdio_server(cwd: Option<PathBuf>) -> McpServerSpec {
    McpServerSpec {
        name: "tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("/opt/tools/mcp-server"),
            args: vec!["--port".into(), "9".into()],
            env: BTreeMap::from([("TOKEN".into(), "exact-value".into())]),
            cwd,
        },
    }
}

fn http_server() -> McpServerSpec {
    McpServerSpec {
        name: "remote".into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test/rpc".into(),
            headers: BTreeMap::from([("Authorization".into(), "Bearer exact".into())]),
        },
    }
}

#[tokio::test]
async fn v1_stdio_baseline_reaches_session_without_optional_capabilities() {
    for initialized in [
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}),
        json!({"jsonrpc":"2.0","id":1,"result":{
            "protocolVersion":1,"agentCapabilities":{"loadSession":false}
        }}),
        v1_initialize(json!({}), false),
        v1_initialize(Value::Null, false),
    ] {
        let transport = MockTransport::new([
            initialized,
            json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-v1"}}),
        ]);
        let mut provider = AcpProvider::with_transport(transport, config());
        assert!(!provider.capabilities().mcp_injection.stdio);
        let mut input = SessionStartInput::new("v1-baseline");
        input.mcp_servers = vec![stdio_server(None)];
        provider.start_session(input).await.unwrap();
        assert!(provider.capabilities().mcp_injection.stdio);
        assert!(!provider.capabilities().mcp_injection.http);
        let writes = provider.client().transport().writes();
        let request = writes.last().unwrap();
        assert_eq!(request["method"], "session/new");
        assert_eq!(request["params"]["mcpServers"][0]["name"], "tools");
        assert!(request["params"]["mcpServers"][0].get("type").is_none());
    }
}

#[tokio::test]
async fn grok_v1_http_and_sse_capabilities_keep_stdio_baseline() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{
            "protocolVersion":1,
            "agentInfo":{"name":"grok","version":"1.0.52"},
            "agentCapabilities":{"mcpCapabilities":{"http":true,"sse":true}},
            "authMethods":[]
        }}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-grok"}}),
    ]);
    let mut provider = AcpProvider::with_transport(
        transport,
        AcpProviderConfig {
            provider: ProviderKind::Other("grok".into()),
            flavor: AcpFlavor::Grok,
            ..config()
        },
    );
    let mut input = SessionStartInput::new("grok-baseline");
    let mut server = stdio_server(None);
    server.name = "alera".into();
    input.mcp_servers = vec![server];
    provider.start_session(input).await.unwrap();
    assert!(provider.capabilities().mcp_injection.stdio);
    assert!(provider.capabilities().mcp_injection.http);
    let writes = provider.client().transport().writes();
    let request = writes.last().unwrap();
    assert_eq!(request["method"], "session/new");
    assert_eq!(request["params"]["mcpServers"][0]["name"], "alera");
    assert!(request["params"]["mcpServers"][0].get("type").is_none());
}

#[tokio::test]
async fn v1_http_requires_explicit_boolean_support() {
    for http in [json!(true), json!(false), Value::Null, json!({}), json!([])] {
        let supported = http == json!(true);
        let transport = MockTransport::new([
            v1_initialize(json!({"http":http}), false),
            json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-http"}}),
        ]);
        let mut provider = AcpProvider::with_transport(transport, config());
        let mut input = SessionStartInput::new("v1-http");
        input.mcp_servers = vec![http_server()];
        let result = provider.start_session(input).await;
        assert_eq!(provider.capabilities().mcp_injection.http, supported);
        assert!(provider.capabilities().mcp_injection.stdio);
        if supported {
            result.unwrap();
            let writes = provider.client().transport().writes();
            assert_eq!(
                writes.last().unwrap()["params"]["mcpServers"][0]["type"],
                "http"
            );
        } else {
            assert!(matches!(result, Err(ProviderError::Unsupported(_))));
            assert!(provider
                .client()
                .transport()
                .writes()
                .iter()
                .all(|request| { request["method"] != "session/new" }));
        }
    }
}

#[tokio::test]
async fn v1_explicit_stdio_opt_out_fails_before_session_call() {
    for stdio in [json!(false), Value::Null, json!([])] {
        let transport = MockTransport::new([v1_initialize(json!({"stdio":stdio}), false)]);
        let mut provider = AcpProvider::with_transport(transport, config());
        let mut input = SessionStartInput::new("v1-stdio-disabled");
        input.mcp_servers = vec![stdio_server(None)];
        assert!(matches!(
            provider.start_session(input).await,
            Err(ProviderError::Unsupported(_))
        ));
        assert!(!provider.capabilities().mcp_injection.stdio);
        assert!(provider
            .client()
            .transport()
            .writes()
            .iter()
            .all(|request| { request["method"] != "session/new" }));
    }
}

#[tokio::test]
async fn v2_modern_session_mcp_declarations_reach_session_new() {
    let transport = MockTransport::new([
        v2_session_initialize(json!({"mcp":{"stdio":{},"http":{}}})),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-modern"}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("modern-mcp");
    input.mcp_servers = vec![stdio_server(None), http_server()];
    provider.start_session(input).await.unwrap();
    assert!(provider.capabilities().mcp_injection.stdio);
    assert!(provider.capabilities().mcp_injection.http);
    let writes = provider.client().transport().writes();
    let request = writes.last().unwrap();
    assert_eq!(request["method"], "session/new");
    assert_eq!(request["params"]["mcpServers"][0]["type"], "stdio");
    assert_eq!(request["params"]["mcpServers"][1]["type"], "http");
}

#[tokio::test]
async fn v2_modern_disabled_or_omitted_mcp_cannot_fall_back_to_legacy_support() {
    for session in [
        Value::Null,
        json!(false),
        json!({}),
        json!({"mcp":null}),
        json!({"mcp":false}),
        json!({"mcp":{}}),
        json!({"mcp":{"stdio":false,"http":false}}),
        json!({"mcp":{"stdio":null,"http":null}}),
        json!({"mcp":{"stdio":[],"http":[]}}),
    ] {
        for server in [stdio_server(None), http_server()] {
            let mut initialized = v2_session_initialize(session.clone());
            initialized["result"]["capabilities"]["sessionCapabilities"] =
                json!({"mcp":{"stdio":{},"http":{}}});
            initialized["result"]["capabilities"]["mcpCapabilities"] =
                json!({"stdio":true,"http":true});
            let transport = MockTransport::new([initialized]);
            let mut provider = AcpProvider::with_transport(transport, config());
            let mut input = SessionStartInput::new("modern-disabled");
            input.mcp_servers = vec![server];
            assert!(matches!(
                provider.start_session(input).await,
                Err(ProviderError::Unsupported(_))
            ));
            assert!(!provider.capabilities().mcp_injection.stdio);
            assert!(!provider.capabilities().mcp_injection.http);
            assert!(provider
                .client()
                .transport()
                .writes()
                .iter()
                .all(|request| { request["method"] != "session/new" }));
        }
    }
}

#[tokio::test]
async fn v2_http_support_does_not_imply_stdio_support() {
    for initialized in [
        v2_initialize(json!({"http":{}})),
        v2_session_initialize(json!({"mcp":{"http":{}}})),
    ] {
        let transport = MockTransport::new([initialized]);
        let mut provider = AcpProvider::with_transport(transport, config());
        let mut input = SessionStartInput::new("v2-stdio-omitted");
        input.mcp_servers = vec![stdio_server(None)];
        assert!(matches!(
            provider.start_session(input).await,
            Err(ProviderError::Unsupported(_))
        ));
        assert!(!provider.capabilities().mcp_injection.stdio);
        assert!(provider.capabilities().mcp_injection.http);
        assert!(provider
            .client()
            .transport()
            .writes()
            .iter()
            .all(|request| { request["method"] != "session/new" }));
    }
}

#[tokio::test]
async fn new_session_preserves_stdio_wire_shape_and_capability() {
    let transport = MockTransport::new([
        v2_initialize(json!({"stdio":{},"http":{}})),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-new"}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers = vec![stdio_server(None)];
    provider.start_session(input).await.unwrap();
    assert!(provider.capabilities().mcp_injection.stdio);
    let request = provider
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(request["method"], "session/new");
    assert_eq!(
        request["params"]["mcpServers"][0],
        json!({
            "type":"stdio",
            "name":"tools",
            "command":"/opt/tools/mcp-server",
            "args":["--port","9"],
            "env":[{"name":"TOKEN","value":"exact-value"}]
        })
    );
}

#[tokio::test]
async fn v1_load_and_v2_resume_preserve_mcp_servers() {
    let transport = MockTransport::new([
        v1_initialize(json!({"stdio":{}}), true),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-load"}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("loaded");
    input.resume_thread_id = Some("native-load".into());
    input.mcp_servers = vec![stdio_server(None)];
    provider.start_session(input).await.unwrap();
    let load = provider
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(load["method"], "session/load");
    assert_eq!(load["params"]["mcpServers"][0]["name"], "tools");
    assert!(load["params"]["mcpServers"][0].get("type").is_none());

    let transport = MockTransport::new([
        v2_initialize(json!({"stdio":{},"http":{}})),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-resume"}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("resumed");
    input.resume_thread_id = Some("native-resume".into());
    input.mcp_servers = vec![http_server()];
    provider.start_session(input).await.unwrap();
    let resume = provider
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(resume["method"], "session/resume");
    assert_eq!(
        resume["params"]["mcpServers"][0],
        json!({
            "type":"http",
            "name":"remote",
            "url":"https://mcp.example.test/rpc",
            "headers":[{"name":"Authorization","value":"Bearer exact"}]
        })
    );
}

#[tokio::test]
async fn unsupported_mcp_transport_or_cwd_fails_before_session_call() {
    let transport = MockTransport::new([v1_initialize(json!({"stdio":{}}), false)]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("unsupported-http");
    input.mcp_servers = vec![http_server()];
    assert!(matches!(
        provider.start_session(input).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(provider
        .client()
        .transport()
        .writes()
        .iter()
        .all(|write| write["method"] != "session/new"));

    let transport = MockTransport::new([v1_initialize(json!({"stdio":{}}), false)]);
    let mut provider = AcpProvider::with_transport(transport, config());
    let mut input = SessionStartInput::new("unsupported-cwd");
    input.mcp_servers = vec![stdio_server(Some(PathBuf::from("/tmp/mcp")))];
    assert!(matches!(
        provider.start_session(input).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert!(provider
        .client()
        .transport()
        .writes()
        .iter()
        .all(|write| write["method"] != "session/new"));
}

#[tokio::test]
async fn mcp_tool_metadata_selects_canonical_item_type_and_keeps_raw() {
    let transport = MockTransport::new([
        v1_initialize(json!({"stdio":{}}), false),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native"}}),
        json!({
            "jsonrpc":"2.0",
            "method":"session/update",
            "params":{
                "sessionId":"native",
                "update":{
                    "sessionUpdate":"tool_call",
                    "toolCallId":"mcp-1",
                    "kind":"other",
                    "status":"in_progress",
                    "title":"tools.run",
                    "rawInput":{"x":1},
                    "_meta":{"is_mcp_tool_call":true,"native":"kept"}
                }
            }
        }),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "call"))
        .await
        .unwrap();
    let _ = provider.next_event().await.unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::ItemStarted);
    assert_eq!(event.payload["itemType"], "mcp_tool_call");
    assert_eq!(
        event.raw.unwrap().payload["params"]["update"]["_meta"]["native"],
        "kept"
    );
}
