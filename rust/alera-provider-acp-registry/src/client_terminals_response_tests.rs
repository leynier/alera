use super::AcpRegistryProvider;
use crate::client_terminals_tests::{call, FakeSpawner};
use crate::AcpRegistryProviderConfig;
use alera_agent_transport::{JsonTransport, MockTransport, TransportError};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, Provider, RuntimeResponse, SessionStartInput, TurnInput,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::Arc;

struct FailedPermissionWrite(MockTransport);

#[async_trait]
impl JsonTransport for FailedPermissionWrite {
    async fn send(&mut self, frame: Value) -> Result<(), TransportError> {
        if frame.get("method").is_none() && frame.get("id") == Some(&json!(9)) {
            return Err(TransportError::Closed);
        }
        self.0.send(frame).await
    }
    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        self.0.recv().await
    }
    async fn close(&mut self) -> Result<(), TransportError> {
        self.0.close().await
    }
}

#[tokio::test]
async fn failed_permission_response_write_never_records_execute_grant() {
    let transport = FailedPermissionWrite(MockTransport::new([
        json!({"jsonrpc":"2.0", "id":1, "result":{"protocolVersion":2, "authMethods":[]}}),
        json!({"jsonrpc":"2.0", "id":2, "result":{"sessionId":"native"}}),
        json!({"jsonrpc":"2.0", "id":9, "method":"session/request_permission", "params":{"sessionId":"native", "toolCall":{"kind":"execute"}, "options":[{"kind":"allow_once", "optionId":"once"}]}}),
    ]));
    let spawner = Arc::new(FakeSpawner::default());
    let mut provider = AcpRegistryProvider::with_transport_and_terminal_spawner(
        transport,
        AcpRegistryProviderConfig {
            agent_id: "devin".into(),
            ..Default::default()
        },
        spawner.clone(),
    )
    .unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("app", "run command"))
        .await
        .unwrap();
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    let request = provider
        .next_event()
        .await
        .unwrap()
        .unwrap()
        .runtime_request
        .unwrap();
    let terminals = provider.client_terminals.as_ref().unwrap().clone();
    assert!(provider
        .respond(RuntimeResponse::Approval {
            request_id: request.request_id,
            decision: ApprovalDecision::Accept,
            updated_input: None
        })
        .await
        .is_err());
    let denied = call(
        &terminals,
        "terminal/create",
        json!({"sessionId":"native", "command":"must not run"}),
    )
    .await
    .unwrap_err();
    assert_eq!(denied.code, -32002);
    assert!(spawner.commands.lock().unwrap().is_empty());
    assert!(provider.inner().client().transport().0.is_closed());
    provider.close().await.unwrap();
}
