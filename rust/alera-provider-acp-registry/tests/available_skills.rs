use alera_agent_transport::MockTransport;
use alera_provider_acp_registry::{
    AcpRegistryProvider, AcpRegistryProviderConfig, AcpRegistrySource,
};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use serde_json::json;
use std::path::PathBuf;

#[tokio::test]
async fn registry_agents_advertise_dollar_commands_as_skills() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"registry-session"}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"registry-session","update":{
            "sessionUpdate":"available_commands_update",
            "availableCommands":[
                {"name":"$workspace-skill","description":"Run the workspace skill"},
                {"name":"review","description":"Review changes"}
            ]
        }}}),
    ]);
    let config = AcpRegistryProviderConfig {
        source: AcpRegistrySource::Local,
        agent_id: "github-copilot-cli".into(),
        executable: Some(PathBuf::from("copilot")),
        runtime_mode: alera_provider_protocol::RuntimeMode::ApprovalRequired,
        ..Default::default()
    };
    let mut provider = AcpRegistryProvider::with_transport(transport, config).unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert_eq!(
        commands.payload,
        json!({"commands":[{"name":"review","description":"Review changes"}]})
    );
    let skills = provider.next_event().await.unwrap().unwrap();
    assert_eq!(skills.kind, EventKind::SessionSkillsUpdated);
    assert_eq!(
        skills.payload,
        json!({"skills":[{
            "name":"workspace-skill",
            "description":"Run the workspace skill",
            "path":"acp://skill/workspace-skill",
            "scope":"agent",
            "enabled":true
        }]})
    );
}
