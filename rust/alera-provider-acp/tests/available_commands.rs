use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderKind, ProviderSlashCommandsUpdate, SessionStartInput,
};
use serde_json::json;
use std::time::Duration;

fn config() -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("grok".into()),
        provider_instance_id: "test".into(),
        flavor: AcpFlavor::Grok,
        request_timeout: Duration::from_secs(1),
        ..AcpProviderConfig::default()
    }
}

#[tokio::test]
async fn available_commands_update_becomes_the_session_command_list() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{
            "sessionUpdate":"available_commands_update",
            "availableCommands":[
                {"name":"web","description":"Search the web","input":{"hint":"query to search for"}},
                {"name":"/plan","description":"  "},
                {"name":"two words","description":"cannot be typed"},
                {"description":"no name"},
                {"name":"WEB","description":"duplicate"}
            ]
        }}}),
        json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{
            "sessionUpdate":"current_mode_update","currentModeId":"code"
        }}}),
    ]);
    let mut provider = AcpProvider::with_transport(transport, config());
    provider.initialize().await.unwrap();
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
    commands.validate().unwrap();
    let update: ProviderSlashCommandsUpdate = serde_json::from_value(commands.payload).unwrap();
    assert_eq!(
        serde_json::to_value(&update.commands).unwrap(),
        json!([
            {"name":"web","description":"Search the web","input":{"hint":"query to search for"}},
            {"name":"plan"}
        ])
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadMetadataUpdated
    );
}
