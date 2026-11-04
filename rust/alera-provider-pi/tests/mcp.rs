use alera_agent_transport::MockTransport;
use alera_provider_pi::{PiProvider, PiProviderConfig};
use alera_provider_protocol::{
    ApprovalPolicy, McpServerSpec, McpTransport, Provider, ProviderError, RuntimeMode,
    SessionStartInput,
};
use serde_json::json;
use std::collections::BTreeMap;

fn state() -> serde_json::Value {
    json!({
        "sessionFile": "/tmp/pi/mcp-session.jsonl",
        "sessionId": "mcp-session",
        "model": { "provider": "anthropic", "id": "claude-sonnet" },
        "isStreaming": false
    })
}

fn response(id: &str, command: &str, data: serde_json::Value) -> serde_json::Value {
    json!({ "type": "response", "id": id, "command": command, "success": true, "data": data })
}

fn server() -> McpServerSpec {
    let mut env = BTreeMap::new();
    env.insert(
        "ALERA_CHAT_CREDENTIAL_FILE".into(),
        "/private/chat-credential".into(),
    );
    McpServerSpec {
        name: "chat".into(),
        transport: McpTransport::Stdio {
            command: "/opt/alera".into(),
            args: vec!["mcp".into(), "serve".into()],
            env,
            cwd: None,
        },
    }
}

#[tokio::test]
async fn session_mcp_specs_are_checked_against_launch_configuration() {
    let servers = vec![server()];
    let config = PiProviderConfig {
        mcp_servers: servers.clone(),
        ..PiProviderConfig::default()
    };
    let responses = vec![response("alera-pi-1", "get_state", state())];
    let mut provider = PiProvider::with_transport(MockTransport::new(responses), config);
    let mut input = SessionStartInput::new("thread");
    input.mcp_servers = servers;
    provider.start_session(input).await.unwrap();
    assert!(provider.capabilities().mcp_injection.stdio);
    assert!(!provider.capabilities().mcp_injection.http);
}

#[tokio::test]
async fn session_mcp_specs_cannot_arrive_after_process_launch() {
    let responses = vec![response("alera-pi-1", "get_state", state())];
    let mut provider =
        PiProvider::with_transport(MockTransport::new(responses), PiProviderConfig::default());
    let mut input = SessionStartInput::new("thread");
    input.mcp_servers = vec![server()];
    let result = provider.start_session(input).await;
    assert!(matches!(result, Err(ProviderError::Unsupported(_))));
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn http_mcp_specs_are_rejected_at_session_boundary() {
    let config = PiProviderConfig {
        mcp_servers: vec![McpServerSpec {
            name: "remote".into(),
            transport: McpTransport::Http {
                url: "https://example.invalid/mcp".into(),
                headers: BTreeMap::new(),
            },
        }],
        ..PiProviderConfig::default()
    };
    let responses = vec![response("alera-pi-1", "get_state", state())];
    let mut provider = PiProvider::with_transport(MockTransport::new(responses), config);
    let result = provider
        .start_session(SessionStartInput::new("thread"))
        .await;
    assert!(matches!(result, Err(ProviderError::Unsupported(_))));
    assert!(provider.transport().writes().is_empty());
}

#[tokio::test]
async fn only_the_enforced_approval_required_policy_is_accepted() {
    for runtime_mode in [
        RuntimeMode::AutoAcceptEdits,
        RuntimeMode::Auto,
        RuntimeMode::FullAccess,
    ] {
        let mut provider =
            PiProvider::with_transport(MockTransport::default(), PiProviderConfig::default());
        let mut input = SessionStartInput::new("thread");
        input.runtime_mode = runtime_mode;
        assert!(matches!(
            provider.start_session(input).await,
            Err(ProviderError::Unsupported(_))
        ));
        assert!(provider.transport().writes().is_empty());
    }
    for approval_policy in [
        ApprovalPolicy::Untrusted,
        ApprovalPolicy::OnFailure,
        ApprovalPolicy::Never,
    ] {
        let mut provider =
            PiProvider::with_transport(MockTransport::default(), PiProviderConfig::default());
        let mut input = SessionStartInput::new("thread");
        input.approval_policy = Some(approval_policy);
        assert!(matches!(
            provider.start_session(input).await,
            Err(ProviderError::Unsupported(_))
        ));
        assert!(provider.transport().writes().is_empty());
    }
    let responses = vec![response("alera-pi-1", "get_state", state())];
    let mut provider =
        PiProvider::with_transport(MockTransport::new(responses), PiProviderConfig::default());
    let mut input = SessionStartInput::new("thread");
    input.approval_policy = Some(ApprovalPolicy::OnRequest);
    provider.start_session(input).await.unwrap();
}
