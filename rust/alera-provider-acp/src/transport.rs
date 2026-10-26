use agent_client_protocol::AcpRequestId;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::RequestKind;
use async_trait::async_trait;
use serde_json::Value;

pub(crate) fn raw(method: &str, payload: Value) -> alera_provider_protocol::RawEvent {
    alera_provider_protocol::RawEvent {
        source: "acp.jsonrpc".into(),
        method: Some(method.into()),
        message_type: Some(method.into()),
        payload,
    }
}

pub struct BoxedTransport(pub(crate) Box<dyn JsonTransport>);

impl BoxedTransport {
    pub fn new(transport: Box<dyn JsonTransport>) -> Self {
        Self(transport)
    }
}

#[async_trait]
impl JsonTransport for BoxedTransport {
    async fn send(&mut self, message: Value) -> Result<(), alera_agent_transport::TransportError> {
        self.0.send(message).await
    }

    async fn recv(&mut self) -> Result<Option<Value>, alera_agent_transport::TransportError> {
        self.0.recv().await
    }

    async fn close(&mut self) -> Result<(), alera_agent_transport::TransportError> {
        self.0.close().await
    }
}

#[derive(Debug, Clone)]
pub struct PendingRequest {
    pub logical_id: String,
    pub rpc_id: AcpRequestId,
    pub kind: RequestKind,
    pub method: String,
    pub params: Value,
    pub raw: Value,
}
