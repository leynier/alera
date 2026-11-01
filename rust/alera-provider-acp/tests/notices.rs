//! ACP `notice` session updates become chat notices without breaking the
//! reply that streams around them.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderEvent, ProviderKind, SessionStartInput, TurnInput,
};
use serde_json::{json, Value};
use std::time::Duration;

const SESSION: &str = "native-session";

fn update(update: Value) -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":SESSION,"update":update}})
}

fn chunk(text: &str) -> Value {
    update(json!({"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":text}}))
}

async fn turn(frames: Vec<Value>) -> Vec<ProviderEvent> {
    let mut all = vec![
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":SESSION}}),
    ];
    all.extend(frames);
    all.push(json!({"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}));
    let mut provider = AcpProvider::with_transport(
        MockTransport::new(all),
        AcpProviderConfig {
            provider: ProviderKind::Other("acp".into()),
            provider_instance_id: "notices".into(),
            request_timeout: Duration::from_secs(1),
            ..AcpProviderConfig::default()
        },
    );
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    provider
        .send_turn(TurnInput::text("app-thread", "hello"))
        .await
        .unwrap();
    let mut events = Vec::new();
    while let Some(event) = provider.next_event().await.unwrap() {
        let ended = event.kind == EventKind::TurnCompleted;
        event.validate().unwrap();
        events.push(event);
        if ended {
            return events;
        }
    }
    events
}

#[tokio::test]
async fn a_notice_between_chunks_is_a_warning_and_the_reply_continues() {
    let events = turn(vec![
        chunk("Hello"),
        update(json!({"sessionUpdate":"notice","title":"Switched model","description":"The requested model is busy.","severity":"warning"})),
        chunk(" world"),
    ])
    .await;
    let deltas: String = events
        .iter()
        .filter(|event| event.kind == EventKind::ContentDelta)
        .map(|event| event.payload["delta"].as_str().unwrap())
        .collect();
    assert_eq!(deltas, "Hello world");
    let notice = events
        .iter()
        .find(|event| event.kind == EventKind::RuntimeWarning)
        .expect("notice");
    assert_eq!(
        notice.payload["message"],
        "Switched model\n\nThe requested model is busy."
    );
    assert_eq!(notice.payload["title"], "Switched model");
    assert_eq!(notice.payload["severity"], "warning");
    assert_eq!(events.last().unwrap().payload["state"], "completed");
}

#[tokio::test]
async fn an_untitled_notice_stays_unknown() {
    let events = turn(vec![update(
        json!({"sessionUpdate":"notice","title":" ","description":"no title"}),
    )])
    .await;
    assert!(events
        .iter()
        .all(|event| event.kind != EventKind::RuntimeWarning));
    assert!(events
        .iter()
        .any(|event| event.kind == EventKind::Unknown("acp.session-update.notice".into())));
}
