use alera_agent_transport::{JsonTransport, MockTransport, TransportError};
use alera_provider_acp::{AcpProvider, AcpProviderConfig};
use alera_provider_protocol::{EventKind, Provider, SessionStartInput};
use async_trait::async_trait;
use serde_json::{json, Value};

struct FrameLimitedTransport {
    inner: MockTransport,
    max_frame_bytes: usize,
    poisoned: bool,
}

#[async_trait]
impl JsonTransport for FrameLimitedTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        let observed = serde_json::to_vec(&message).unwrap().len();
        if observed > self.max_frame_bytes {
            self.poisoned = true;
            return Err(TransportError::FrameTooLarge {
                limit: self.max_frame_bytes,
                observed,
            });
        }
        self.inner.send(message).await
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        self.inner.recv().await
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.inner.close().await
    }
}

#[tokio::test]
async fn configured_frame_budget_bounds_generic_unknown_errors_and_keeps_session_healthy() {
    let id = "x".repeat(450);
    let incoming = json!({"jsonrpc":"2.0","id":id,"method":"x","params":{}});
    assert_eq!(serde_json::to_vec(&incoming).unwrap().len(), 500);
    let transport = FrameLimitedTransport {
        inner: MockTransport::new([
            json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{}}}),
            json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
            incoming,
            json!({"jsonrpc":"2.0","id":7,"method":"future","params":{}}),
        ]),
        max_frame_bytes: 512,
        poisoned: false,
    };
    let mut config = AcpProviderConfig::default();
    config.process.max_frame_bytes = 512;
    let mut provider = AcpProvider::with_transport(transport, config);
    provider
        .start_session(SessionStartInput::new("thread"))
        .await
        .unwrap();
    provider.next_event().await.unwrap();
    let first = provider.next_event().await.unwrap().unwrap();
    assert!(matches!(first.kind, EventKind::Unknown(_)));
    let second = provider.next_event().await.unwrap().unwrap();
    assert!(matches!(second.kind, EventKind::Unknown(_)));
    let transport = provider.client().transport();
    let writes = transport.inner.writes();
    assert_eq!(writes[2]["id"], id);
    assert_eq!(writes[2]["error"]["code"], -32601);
    assert_eq!(serde_json::to_vec(&writes[2]).unwrap().len(), 512);
    assert_eq!(writes[3]["id"], 7);
    assert_eq!(writes[3]["error"]["code"], -32601);
    assert!(!transport.poisoned);
}
