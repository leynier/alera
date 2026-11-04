//! An id-only permission request keeps the command of the tool call it
//! names, after T3 Code `b2871029c9`.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, ProviderKind, RequestKind, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

fn tool_call(session: &str) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":session,"update":{
        "sessionUpdate":"tool_call","toolCallId":"call-1","kind":"execute","title":"Run tests",
        "status":"pending","rawInput":{"command":["cargo","test"],"cwd":"/work"}
    }}})
}

fn id_only(session: &str) -> Value {
    json!({"jsonrpc":"2.0","id":"permit","method":"session/request_permission","params":{
        "sessionId":session,"toolCall":{"toolCallId":"call-1"},
        "options":[{"optionId":"once","kind":"allow_once"}]
    }})
}

async fn request_event(frames: Vec<Value>) -> ProviderEvent {
    let mut all = vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"root"}}),
    ];
    all.extend(frames);
    let mut provider = AcpProvider::with_transport(
        MockTransport::new(all),
        AcpProviderConfig {
            provider: ProviderKind::Other("acp".into()),
            request_timeout: Duration::from_millis(200),
            ..AcpProviderConfig::default()
        },
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app", "test"))
        .await
        .unwrap();
    loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.kind == EventKind::RequestOpened {
            return event;
        }
    }
}

#[tokio::test]
async fn an_id_only_request_keeps_the_tracked_command() {
    let event = request_event(vec![tool_call("root"), id_only("root")]).await;
    let request = event.runtime_request.as_ref().unwrap();
    assert_eq!(request.kind, RequestKind::CommandExecutionApproval);
    assert_eq!(request.item_id.as_deref(), Some("call-1"));
    assert_eq!(event.payload["command"], "cargo test");
    assert_eq!(event.payload["cwd"], "/work");
    assert_eq!(event.payload["detail"], "Run tests");
    assert_eq!(request.payload["toolCall"]["kind"], "execute");
}

#[tokio::test]
async fn a_foreign_sessions_request_is_not_enriched() {
    let event = request_event(vec![tool_call("root"), id_only("other")]).await;
    let request = event.runtime_request.as_ref().unwrap();
    assert_eq!(request.kind, RequestKind::PermissionApproval);
    assert!(event.payload.get("command").is_none());
    assert!(request.payload["toolCall"].get("kind").is_none());
}
