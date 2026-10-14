mod support;

use alera_provider_muse::{MuseProvider, MuseProviderConfig};
use alera_provider_protocol::{
    EventKind, InterruptInput, McpServerSpec, McpTransport, Provider, SessionStartInput, TurnInput,
};
use serde_json::json;
use std::collections::BTreeMap;
use std::path::PathBuf;
use support::{
    initialize_response, initialize_response_with_grants, response, session_response,
    ScriptedTransport,
};

#[tokio::test]
async fn start_session_sends_handshake_and_session_start_in_order() {
    let transport =
        ScriptedTransport::new([initialize_response(), session_response(2, "muse-session")]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(session.native_thread_id, "muse-session");
    assert!(matches!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionStarted
    ));
    assert!(matches!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    ));
    let writes = writes.lock().unwrap().clone();
    assert_eq!(writes[0]["method"], "initialize");
    assert_eq!(writes[1]["method"], "initialized");
    assert_eq!(writes[2]["method"], "session/start");
    assert!(uuid::Uuid::parse_str(writes[2]["params"]["commandId"].as_str().unwrap()).is_ok());
    provider.close().await.unwrap();
}

#[tokio::test]
async fn resume_and_interrupt_wait_for_native_terminal_event() {
    let transport = ScriptedTransport::new([
        initialize_response(),
        session_response(2, "existing-session"),
        response(
            3,
            json!({
                "status":"accepted",
                "turnId":"native-turn",
                "startedNewTurn":true,
                "disposition":"started"
            }),
        ),
        json!({
            "jsonrpc":"2.0",
            "method":"turn/started",
            "params":{"sessionId":"existing-session","turnId":"native-turn"}
        }),
        response(4, json!({"status":"accepted"})),
        json!({
            "jsonrpc":"2.0",
            "method":"turn/completed",
            "params":{"sessionId":"existing-session","turnId":"native-turn","terminal":"cancelled"}
        }),
    ]);
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let session = provider
        .start_session(SessionStartInput {
            thread_id: "app-thread".into(),
            resume_thread_id: Some("existing-session".into()),
            ..SessionStartInput::default()
        })
        .await
        .unwrap();
    let _ = provider.next_event().await;
    let _ = provider.next_event().await;
    let result = provider
        .send_turn(TurnInput::text(session.thread_id.clone(), "hello"))
        .await
        .unwrap();
    assert_eq!(result.native_turn_id.as_deref(), Some("native-turn"));
    provider
        .interrupt(InterruptInput {
            thread_id: session.thread_id,
            turn_id: Some(result.turn_id),
        })
        .await
        .unwrap();
    assert!(provider.session().unwrap().active_turn_id.is_some());
    let _ = provider.next_event().await.unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert!(provider.session().unwrap().active_turn_id.is_none());
    provider.close().await.unwrap();
}

#[tokio::test]
async fn mcp_http_negotiates_and_maps_session_start_config() {
    let transport = ScriptedTransport::new([
        initialize_response_with_grants(["sessionMcp"]),
        session_response(2, "muse-session"),
    ]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers.push(McpServerSpec {
        name: "alera".into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test/session".into(),
            headers: BTreeMap::from([(String::from("Authorization"), String::from("Bearer x"))]),
        },
    });
    provider.start_session(input).await.unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(
        writes[0]["params"]["capabilities"]["requestedCapabilities"],
        json!(["sessionMcp"])
    );
    assert_eq!(writes[2]["method"], "session/start");
    assert_eq!(
        writes[2]["params"]["config"]["mcpServers"]["alera"],
        json!({
            "transport": "streamableHttp",
            "url": "https://mcp.example.test/session",
            "headers": {"Authorization": "Bearer x"},
            "mode": "required"
        })
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionStarted
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider.close().await.unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::SessionExited
    );
}

#[tokio::test]
async fn mcp_stdio_maps_native_shape_and_rejects_unrepresentable_cwd() {
    let transport = ScriptedTransport::new([
        initialize_response_with_grants(["sessionMcp"]),
        session_response(2, "muse-session"),
    ]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers.push(McpServerSpec {
        name: "local-tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("mcp-tools"),
            args: vec!["--stdio".into()],
            env: BTreeMap::from([(String::from("TOKEN"), String::from("secret"))]),
            cwd: None,
        },
    });
    provider.start_session(input).await.unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(
        writes[2]["params"]["config"]["mcpServers"]["local-tools"],
        json!({
            "transport": "stdio",
            "command": "mcp-tools",
            "args": ["--stdio"],
            "env": {"TOKEN": "secret"},
            "mode": "required"
        })
    );
    provider.close().await.unwrap();

    let transport = ScriptedTransport::new([initialize_response_with_grants(["sessionMcp"])]);
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers.push(McpServerSpec {
        name: "local-tools".into(),
        transport: McpTransport::Stdio {
            command: PathBuf::from("mcp-tools"),
            args: Vec::new(),
            env: BTreeMap::new(),
            cwd: Some(PathBuf::from("/tmp")),
        },
    });
    let error = provider.start_session(input).await.unwrap_err();
    assert!(error.to_string().contains("no cwd field"));
    provider.close().await.unwrap();
}

#[tokio::test]
async fn mcp_start_is_rejected_when_host_withholds_session_capability() {
    let transport =
        ScriptedTransport::new([initialize_response(), session_response(2, "must-not-start")]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput::new("app-thread");
    input.mcp_servers.push(McpServerSpec {
        name: "alera".into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test/session".into(),
            headers: BTreeMap::new(),
        },
    });
    let error = provider.start_session(input).await.unwrap_err();
    assert!(error.to_string().contains("did not grant sessionMcp"));
    assert_eq!(writes.lock().unwrap().len(), 2);
    provider.close().await.unwrap();
}

#[tokio::test]
async fn mcp_resume_forwards_the_same_session_config() {
    let transport = ScriptedTransport::new([
        initialize_response_with_grants(["sessionMcp"]),
        session_response(2, "existing-session"),
    ]);
    let writes = transport.writes.clone();
    let mut provider =
        MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    let mut input = SessionStartInput {
        thread_id: "app-thread".into(),
        resume_thread_id: Some("existing-session".into()),
        ..SessionStartInput::default()
    };
    input.mcp_servers.push(McpServerSpec {
        name: "alera".into(),
        transport: McpTransport::Http {
            url: "https://mcp.example.test/session".into(),
            headers: BTreeMap::new(),
        },
    });
    provider.start_session(input).await.unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(writes[2]["method"], "session/resume");
    assert_eq!(
        writes[2]["params"]["config"]["mcpServers"]["alera"]["transport"],
        "streamableHttp"
    );
    assert_eq!(
        writes[2]["params"]["config"]["mcpServers"]["alera"]["mode"],
        "required"
    );
    provider.close().await.unwrap();
}

#[tokio::test]
async fn mcp_capabilities_follow_negotiated_grant_and_connection_lifecycle() {
    for granted in [false, true] {
        let grants = if granted {
            vec!["sessionMcp"]
        } else {
            vec!["userShell"]
        };
        let transport = ScriptedTransport::new([initialize_response_with_grants(grants)]);
        let mut provider =
            MuseProvider::with_transport(transport, MuseProviderConfig::default()).unwrap();
        assert!(provider.capabilities().mcp_injection.is_empty());
        provider.initialize().await.unwrap();
        assert_eq!(provider.capabilities().mcp_injection.stdio, granted);
        assert_eq!(provider.capabilities().mcp_injection.http, granted);
        provider.close().await.unwrap();
        assert!(provider.capabilities().mcp_injection.is_empty());
    }
}
