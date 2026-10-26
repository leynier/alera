mod support;

use alera_provider_claude::ClaudeProvider;
use alera_provider_protocol::{EventKind, Provider, ProviderEvent};
use serde_json::{json, Value};
use support::*;

fn initialize_with_commands(commands: Value) -> Value {
    json!({
        "type": "control_response",
        "response": {
            "subtype": "success",
            "request_id": "req_1",
            "response": {"session_id": "native-session", "commands": commands}
        }
    })
}

fn system_init() -> Value {
    json!({
        "type": "system",
        "subtype": "init",
        "session_id": "native-session",
        "slash_commands": ["compact", "review", "compact", "bad name"]
    })
}

async fn events_until_configured(provider: &mut ClaudeProvider) -> Vec<ProviderEvent> {
    let mut events = Vec::new();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        let configured = event.kind == EventKind::SessionConfigured;
        events.push(event);
        if configured {
            // The init commands, when there are any, follow the configuration.
            if let Ok(Ok(Some(next))) =
                tokio::time::timeout(std::time::Duration::from_millis(50), provider.next_event())
                    .await
            {
                events.push(next);
            }
            return events;
        }
    }
}

fn command_lists(events: &[ProviderEvent]) -> Vec<Value> {
    events
        .iter()
        .filter(|event| event.kind == EventKind::SessionCommandsUpdated)
        .map(|event| {
            event.validate().unwrap();
            event.payload["commands"].clone()
        })
        .collect()
}

#[tokio::test]
async fn initialize_commands_are_described_and_win_over_init_names() {
    let (mut provider, _handle) = started_provider([
        initialize_with_commands(json!([
            {"name": "compact", "description": "Clear history but keep a summary", "argumentHint": "<instructions>"},
            {"name": "/review", "description": "Review a pull request"},
            {"name": "", "description": "dropped"}
        ])),
        system_init(),
    ])
    .await;
    let events = events_until_configured(&mut provider).await;
    assert_eq!(
        command_lists(&events),
        vec![json!([
            {"name": "compact", "description": "Clear history but keep a summary", "input": {"hint": "<instructions>"}},
            {"name": "review", "description": "Review a pull request"}
        ])]
    );
    let commands = events
        .iter()
        .position(|event| event.kind == EventKind::SessionCommandsUpdated)
        .unwrap();
    let configured = events
        .iter()
        .position(|event| event.kind == EventKind::SessionConfigured)
        .unwrap();
    assert!(commands < configured, "initialize commands come first");
}

#[tokio::test]
async fn init_names_stand_in_when_initialize_lists_none() {
    let (mut provider, _handle) = started_provider([initialize_response(), system_init()]).await;
    let events = events_until_configured(&mut provider).await;
    assert_eq!(
        command_lists(&events),
        vec![json!([{"name": "compact"}, {"name": "review"}])]
    );
}
