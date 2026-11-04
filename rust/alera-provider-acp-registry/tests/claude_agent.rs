//! Claude Agent over the registry: the ACP v2 preview that runs sub-agents as
//! native child sessions.

use alera_agent_transport::MockTransport;
use alera_provider_acp_registry::{
    AcpRegistryAgentFlavor, AcpRegistryProvider, AcpRegistryProviderConfig, AcpRegistrySource,
    CLAUDE_ACP_V2_ENV,
};
use alera_provider_protocol::{EventKind, Provider, ProviderError, SessionStartInput};
use serde_json::json;
use std::ffi::OsString;

fn claude() -> AcpRegistryProviderConfig {
    AcpRegistryProviderConfig {
        agent_id: "claude-acp".into(),
        ..Default::default()
    }
}

#[test]
fn claude_agent_is_recognized_from_the_registry_and_a_local_command() {
    assert_eq!(claude().agent_flavor(), AcpRegistryAgentFlavor::ClaudeAgent);
    let local = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "my-claude".into(),
        executable: Some("/opt/bin/claude-agent-acp.exe".into()),
        ..Default::default()
    };
    assert_eq!(local.agent_flavor(), AcpRegistryAgentFlavor::ClaudeAgent);
    let other = AcpRegistryProviderConfig {
        agent_id: "pi".into(),
        ..Default::default()
    };
    assert!(!other
        .launch_env()
        .contains_key(&OsString::from(CLAUDE_ACP_V2_ENV)));
}

#[test]
fn claude_agent_launches_on_acp_v2_unless_its_environment_decides() {
    let mut opted_out = claude();
    opted_out
        .env
        .insert(CLAUDE_ACP_V2_ENV.into(), OsString::from("0"));
    assert_eq!(
        opted_out
            .launch_env()
            .get(&OsString::from(CLAUDE_ACP_V2_ENV)),
        Some(&OsString::from("0"))
    );
    if std::env::var_os(CLAUDE_ACP_V2_ENV).is_none() {
        assert_eq!(
            claude()
                .launch_env()
                .get(&OsString::from(CLAUDE_ACP_V2_ENV)),
            Some(&OsString::from("1"))
        );
    }
}

#[tokio::test]
async fn claude_agent_on_v2_projects_and_stops_its_children() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"info":{"name":"claude-agent-acp","version":"0.90.0"},"capabilities":{"session":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"root"}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"root","update":{"sessionUpdate":"subagent_update","sessionId":"child","state":{"state":"running"}}}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"child","update":{"sessionUpdate":"session_message","messageId":"agent-1","senderSessionId":"root","content":[{"type":"text","text":"Review"}]}}}),
    ]);
    let mut provider = AcpRegistryProvider::with_transport(transport, claude()).unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert!(provider.subagent_capabilities().native_child_sessions);
    let _ = provider.next_event().await.unwrap();
    let _ = provider.next_event().await.unwrap();
    let linked = provider.next_event().await.unwrap().unwrap();
    assert_eq!(linked.kind, EventKind::TaskStarted);
    assert_eq!(linked.payload["taskId"], "agent-1");
    assert!(matches!(
        provider.stop_subagent("other").await,
        Err(ProviderError::Validation(_))
    ));
    provider.stop_subagent("agent-1").await.unwrap();
    let cancel = provider
        .inner()
        .client()
        .transport()
        .writes()
        .last()
        .unwrap()
        .clone();
    assert_eq!(cancel["params"]["sessionId"], "child");
}
