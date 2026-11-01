//! A tool call the agent cancels settles as failed and the turn still ends,
//! after T3 Code's ACP tool status handling.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{EventKind, Provider, ProviderKind, SessionStartInput, TurnInput};
use serde_json::{json, Value};
use std::time::Duration;

const SESSION: &str = "native-session";

fn tool_update(name: &str, status: &str) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":SESSION,"update":{
        "sessionUpdate":name,"toolCallId":"tool-1","kind":"execute","title":"ls","status":status
    }}})
}

#[tokio::test]
async fn cancelled_tool_calls_complete_as_failed_before_the_turn_ends() {
    let frames = vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":SESSION}}),
        tool_update("tool_call", "in_progress"),
        tool_update("tool_call_update", "cancelled"),
        json!({"jsonrpc":"2.0","id":3,"result":{"stopReason":"cancelled"}}),
    ];
    let mut provider = AcpProvider::with_transport(
        MockTransport::new(frames),
        AcpProviderConfig {
            provider: ProviderKind::Other("acp".into()),
            provider_instance_id: "tool-status".into(),
            request_timeout: Duration::from_secs(1),
            ..AcpProviderConfig::default()
        },
    );
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "list"))
        .await
        .unwrap();
    let mut events = Vec::new();
    while let Some(event) = provider.next_event().await.unwrap() {
        let ended = event.kind == EventKind::TurnCompleted;
        events.push(event);
        if ended {
            break;
        }
    }
    let tools: Vec<_> = events
        .iter()
        .filter(|event| event.item_id.as_deref() == Some("tool-1"))
        .map(|event| (event.kind.clone(), event.payload["status"].clone()))
        .collect();
    assert_eq!(
        tools,
        vec![
            (EventKind::ItemStarted, json!("inProgress")),
            (EventKind::ItemCompleted, json!("failed")),
        ]
    );
    assert_eq!(events.last().unwrap().payload["state"], "interrupted");
}
