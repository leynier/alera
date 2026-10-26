use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    McpServerSpec, McpTransport, Provider, ProviderError, SessionStartInput,
};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

fn v2_initialize(capabilities: Value) -> Value {
    json!({
        "jsonrpc":"2.0",
        "id":1,
        "result":{
            "protocolVersion":2,
            "info":{"name":"fixture","version":"1"},
            "capabilities":capabilities,
            "authMethods":[]
        }
    })
}

fn resume_input() -> SessionStartInput {
    let mut input = SessionStartInput::new("app-thread");
    input.resume_thread_id = Some("native-session-7".into());
    input.cwd = Some(PathBuf::from("/work/project"));
    input
}

#[tokio::test]
async fn modern_v2_empty_session_object_advertises_baseline_resume() {
    let transport = MockTransport::new([
        v2_initialize(json!({"session":{}})),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
    assert!(!provider.capabilities().resume);
    provider.initialize().await.unwrap();
    assert!(provider.capabilities().resume);
    assert!(!provider.capabilities().mcp_injection.stdio);
    provider.start_session(resume_input()).await.unwrap();
    let writes = provider.client().transport().writes();
    assert_eq!(writes.last().unwrap()["method"], "session/resume");
    assert_eq!(
        writes.last().unwrap()["params"]["sessionId"],
        "native-session-7"
    );
}

#[tokio::test]
async fn modern_v2_resume_preserves_native_id_and_explicit_mcp_server() {
    let transport = MockTransport::new([
        v2_initialize(json!({
            "session":{"mcp":{"stdio":{}}},
            "sessionCapabilities":{"resume":false},
            "loadSession":true
        })),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
    provider.initialize().await.unwrap();
    assert!(provider.capabilities().resume);
    assert!(provider.capabilities().mcp_injection.stdio);
    let mut input = resume_input();
    input.mcp_servers = vec![McpServerSpec {
        name: "tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("/opt/tools/mcp-server"),
            args: vec!["--stdio".into()],
            env: BTreeMap::from([("CONTEXT".into(), "resume-fixture".into())]),
            cwd: None,
        },
    }];
    provider.start_session(input).await.unwrap();
    let writes = provider.client().transport().writes();
    assert_eq!(writes.len(), 2);
    assert_eq!(
        writes[1],
        json!({
            "jsonrpc":"2.0",
            "id":2,
            "method":"session/resume",
            "params":{
                "sessionId":"native-session-7",
                "cwd":"/work/project",
                "mcpServers":[{
                    "type":"stdio",
                    "name":"tools",
                    "command":"/opt/tools/mcp-server",
                    "args":["--stdio"],
                    "env":[{"name":"CONTEXT","value":"resume-fixture"}]
                }]
            }
        })
    );
}

#[tokio::test]
async fn modern_v2_disabled_or_invalid_session_does_not_use_legacy_resume() {
    for session in [Value::Null, json!(false), json!(true), json!([]), json!(7)] {
        let transport = MockTransport::new([v2_initialize(json!({
            "session":session,
            "sessionCapabilities":{"resume":{}},
            "loadSession":true
        }))]);
        let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
        provider.initialize().await.unwrap();
        assert!(!provider.capabilities().resume);
        assert!(matches!(
            provider.start_session(resume_input()).await,
            Err(ProviderError::Unsupported(_))
        ));
        let writes = provider.client().transport().writes();
        assert_eq!(writes.len(), 1);
        assert_eq!(writes[0]["method"], "initialize");
    }
}

#[tokio::test]
async fn v2_without_modern_session_retains_explicit_legacy_resume() {
    let transport = MockTransport::new([
        v2_initialize(json!({"sessionCapabilities":{"resume":{}}})),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
    provider.initialize().await.unwrap();
    assert!(provider.capabilities().resume);
    provider.start_session(resume_input()).await.unwrap();
    let writes = provider.client().transport().writes();
    assert_eq!(writes.last().unwrap()["method"], "session/resume");

    for capabilities in [
        json!({}),
        json!({"loadSession":true}),
        json!({"sessionCapabilities":{}}),
        json!({"sessionCapabilities":{"resume":false}}),
        json!({"sessionCapabilities":{"resume":null}}),
    ] {
        let transport = MockTransport::new([v2_initialize(capabilities)]);
        let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
        provider.initialize().await.unwrap();
        assert!(!provider.capabilities().resume);
        assert!(matches!(
            provider.start_session(resume_input()).await,
            Err(ProviderError::Unsupported(_))
        ));
        assert_eq!(provider.client().transport().writes().len(), 1);
    }
}

#[tokio::test]
async fn v1_load_and_resume_capabilities_keep_native_method_selection() {
    for (capabilities, method) in [
        (json!({"loadSession":true}), "session/load"),
        (
            json!({"loadSession":false,"sessionCapabilities":{"resume":{}}}),
            "session/resume",
        ),
    ] {
        let transport = MockTransport::new([
            json!({"jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":1,"agentCapabilities":capabilities,"authMethods":[]
            }}),
            json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session-7"}}),
        ]);
        let mut provider = AcpProvider::with_transport(transport, AcpProviderConfig::default());
        provider.initialize().await.unwrap();
        assert!(provider.capabilities().resume);
        provider.start_session(resume_input()).await.unwrap();
        let writes = provider.client().transport().writes();
        assert_eq!(writes.last().unwrap()["method"], method);
        assert_eq!(
            writes.last().unwrap()["params"]["sessionId"],
            "native-session-7"
        );
    }
}
