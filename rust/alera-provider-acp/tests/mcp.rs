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
