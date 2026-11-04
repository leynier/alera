//! Only the Antigravity flavor reads `interaction_*` permission requests as
//! questions; every other agent keeps them as approvals.

use alera_agent_transport::MockTransport;
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{
    EventKind, Provider, ProviderKind, RequestKind, SessionStartInput, TurnInput,
};
use serde_json::json;
use std::time::Duration;

#[tokio::test]
async fn the_generic_flavor_keeps_interaction_permissions_as_approvals() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{},"authMethods":[]}}),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native"}}),
        json!({"jsonrpc":"2.0","id":"q1","method":"session/request_permission","params":{
            "sessionId":"native",
            "toolCall":{"toolCallId":"interaction_1","title":"Pick"},
            "options":[{"optionId":"1","name":"A","kind":"allow_once"}]
        }}),
    ]);
    let mut provider = AcpProvider::with_transport(
        transport,
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
        .send_turn(TurnInput::text("app", "hello"))
        .await
        .unwrap();
    let event = loop {
        let event = provider.next_event().await.unwrap().unwrap();
        if event.runtime_request.is_some() {
            break event;
        }
    };
    assert_eq!(event.kind, EventKind::RequestOpened);
    assert_eq!(
        event.runtime_request.unwrap().kind,
        RequestKind::PermissionApproval
    );
}
