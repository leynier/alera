use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpFlavor, AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, ProviderKind, SessionStartInput,
};
use serde_json::{json, Value};
use std::time::Duration;

fn config(flavor: AcpFlavor) -> AcpProviderConfig {
    AcpProviderConfig {
        provider: ProviderKind::Other("acpRegistry".into()),
        provider_instance_id: "test".into(),
        flavor,
        request_timeout: Duration::from_secs(1),
        ..AcpProviderConfig::default()
    }
}

fn commands_update(commands: Value) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{
        "sessionUpdate":"available_commands_update",
        "availableCommands":commands
    }}})
}

async fn started(flavor: AcpFlavor, updates: Vec<Value>) -> AcpProvider<MockTransport> {
    let mut script = vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{}},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
    ];
    script.extend(updates);
    let mut provider = AcpProvider::with_transport(MockTransport::new(script), config(flavor));
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    assert_eq!(next(&mut provider).await.kind, EventKind::ThreadStarted);
    provider
}

async fn next(provider: &mut AcpProvider<MockTransport>) -> ProviderEvent {
    let event = provider.next_event().await.unwrap().unwrap();
    event.validate().unwrap();
    event
}

#[tokio::test]
async fn registry_lists_dollar_commands_as_agent_skills() {
    let mut provider = started(
        AcpFlavor::Registry,
        vec![commands_update(json!([
            {"name":"$workspace-skill","description":" Run the workspace skill "},
            {"name":"$WORKSPACE-SKILL","description":"duplicate"},
            {"name":"$","description":"empty"},
            {"name":"$plugin:deploy"},
            {"name":" padded","description":"not opaque"},
            {"name":"review","description":"Review changes","input":{"hint":" what to review "}},
            {"name":"REVIEW","description":"duplicate"}
        ]))],
    )
    .await;
    let commands = next(&mut provider).await;
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    assert_eq!(
        commands.payload,
        json!({"commands":[
            {"name":"review","description":"Review changes","input":{"hint":"what to review"}}
        ]})
    );
    let skills = next(&mut provider).await;
    assert_eq!(skills.kind, EventKind::SessionSkillsUpdated);
    assert_eq!(skills.thread_id, commands.thread_id);
    assert_eq!(
        skills.payload,
        json!({"skills":[
            {
                "name":"workspace-skill",
                "description":"Run the workspace skill",
                "path":"acp://skill/workspace-skill",
                "scope":"agent",
                "enabled":true
            },
            {
                "name":"plugin:deploy",
                "path":"acp://skill/plugin%3Adeploy",
                "scope":"agent",
                "enabled":true
            }
        ]})
    );
}

#[tokio::test]
async fn registry_clears_skills_when_a_later_update_lists_none() {
    let mut provider = started(
        AcpFlavor::Registry,
        vec![
            commands_update(json!([{"name":"$deploy"},{"name":"plan"}])),
            commands_update(json!([{"name":"plan"}])),
        ],
    )
    .await;
    assert_eq!(
        next(&mut provider).await.kind,
        EventKind::SessionCommandsUpdated
    );
    assert_eq!(
        next(&mut provider).await.payload["skills"][0]["name"],
        "deploy"
    );
    let commands = next(&mut provider).await;
    assert_eq!(commands.payload, json!({"commands":[{"name":"plan"}]}));
    let cleared = next(&mut provider).await;
    assert_eq!(cleared.kind, EventKind::SessionSkillsUpdated);
    assert_eq!(cleared.payload, json!({"skills":[]}));
}

#[tokio::test]
async fn registry_shares_one_budget_between_commands_and_skills() {
    let mut entries: Vec<Value> = (0..127)
        .map(|index| json!({"name":format!("command_{index}")}))
        .collect();
    entries.push(json!({"name":"$last"}));
    entries.push(json!({"name":"$over-budget"}));
    let mut provider = started(AcpFlavor::Registry, vec![commands_update(json!(entries))]).await;
    let commands = next(&mut provider).await;
    assert_eq!(commands.payload["commands"].as_array().unwrap().len(), 127);
    let skills = next(&mut provider).await;
    assert_eq!(skills.payload["skills"].as_array().unwrap().len(), 1);
    assert_eq!(skills.payload["skills"][0]["name"], "last");
}

#[tokio::test]
async fn other_flavors_keep_dollar_commands_as_slash_commands() {
    for flavor in [AcpFlavor::Generic, AcpFlavor::Grok, AcpFlavor::Antigravity] {
        let mut provider = started(
            flavor,
            vec![
                commands_update(json!([{"name":"$deploy"},{"name":"plan"}])),
                json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"native-session","update":{
                    "sessionUpdate":"current_mode_update","currentModeId":"code"
                }}}),
            ],
        )
        .await;
        let commands = next(&mut provider).await;
        assert_eq!(
            commands.payload,
            json!({"commands":[{"name":"$deploy"},{"name":"plan"}]})
        );
        assert_eq!(
            next(&mut provider).await.kind,
            EventKind::ThreadMetadataUpdated
        );
    }
}
