use alera_provider_protocol::{
    McpInjectionCapabilities, McpServerSpec, McpTransport, SessionStartInput,
};
use std::collections::BTreeMap;

fn stdio() -> McpServerSpec {
    McpServerSpec {
        name: "alera".into(),
        transport: McpTransport::Stdio {
            command: "alera".into(),
            args: vec!["mcp".into(), "serve".into()],
            env: BTreeMap::from([("SECRET".into(), "private-value".into())]),
            cwd: None,
        },
    }
}

#[test]
fn client_commands_cannot_populate_host_mcp_configuration() {
    let input: SessionStartInput = serde_json::from_value(serde_json::json!({
        "threadId": "chat-1",
        "mcpServers": [{"name":"external", "transport":"stdio", "command":"ignored"}]
    }))
    .unwrap();
    assert!(input.mcp_servers.is_empty());

    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers.push(stdio());
    input.validate().unwrap();
    assert!(serde_json::to_value(input)
        .unwrap()
        .get("mcpServers")
        .is_none());
}

#[test]
fn duplicate_servers_are_rejected_before_launch() {
    let mut input = SessionStartInput::new("chat-1");
    input.mcp_servers = vec![stdio(), stdio()];
    assert!(input.validate().is_err());
}

#[test]
fn invalid_native_configuration_is_rejected() {
    let mut server = stdio();
    server.name = " ".into();
    assert!(server.validate().is_err());
    server.name = "alera".into();
    if let McpTransport::Stdio { env, .. } = &mut server.transport {
        env.insert("BAD=KEY".into(), "value".into());
    }
    assert!(server.validate().is_err());
    server.transport = McpTransport::Http {
        url: "file:///tmp/socket".into(),
        headers: BTreeMap::new(),
    };
    assert!(server.validate().is_err());
    server.transport = McpTransport::Http {
        url: "http://127.0.0.1:8080/mcp".into(),
        headers: BTreeMap::from([("Authorization".into(), "Bearer x\r\nInjected: y".into())]),
    };
    assert!(server.validate().is_err());
}

#[test]
fn capabilities_distinguish_http_from_stdio() {
    let capabilities = McpInjectionCapabilities {
        stdio: true,
        http: false,
    };
    assert!(capabilities.supports(&stdio()));
    assert!(!capabilities.supports(&McpServerSpec {
        name: "remote".into(),
        transport: McpTransport::Http {
            url: "https://example.test/mcp".into(),
            headers: BTreeMap::new(),
        },
    }));
    assert!(McpInjectionCapabilities::default().is_empty());
}

#[test]
fn debug_output_redacts_configuration_values() {
    let mut server = stdio();
    let debug = format!("{server:?}");
    assert!(debug.contains("SECRET"));
    assert!(!debug.contains("private-value"));
    server.transport = McpTransport::Http {
        url: "https://user:private-password@example.test/mcp?token=private-token".into(),
        headers: BTreeMap::from([("Authorization".into(), "Bearer private-value".into())]),
    };
    let debug = format!("{server:?}");
    assert!(debug.contains("Authorization"));
    assert!(!debug.contains("private-"));
}
