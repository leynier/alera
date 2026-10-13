#[path = "support/callback_transport.rs"]
mod callback_transport;

use agent_client_protocol::{
    AcpClient, AcpClientRequestHandler, AcpError, AcpIncoming, AcpRequestHandlerContext,
    AcpRequestId, RpcError, RpcRequest,
};
use async_trait::async_trait;
use callback_transport::CallbackTransport;
use serde_json::{json, Value};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

fn request(id: Value, method: &str) -> Value {
    json!({"jsonrpc":"2.0","id":id,"method":method,"params":{}})
}

fn method_not_found() -> Result<Value, RpcError> {
    Err(RpcError {
        code: -32601,
        message: "Method not found".into(),
        data: None,
    })
}

#[tokio::test]
async fn long_id_unknown_error_fits_and_the_next_request_stays_healthy() {
    let (mut transport, sender) = CallbackTransport::new();
    transport.max_frame_bytes = 512;
    let writes = transport.writes.clone();
    let closed = transport.closed.clone();
    let mut client = AcpClient::new(transport);
    client.set_max_response_frame_bytes(512);
    let id = AcpRequestId::String("x".repeat(450));
    let frame = request(id.as_value(), "x");
    assert_eq!(serde_json::to_vec(&frame).unwrap().len(), 500);
    sender.send(frame).await.unwrap();
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Request(_))
    ));
    client.respond(&id, method_not_found()).await.unwrap();
    sender.send(request(json!(2), "x")).await.unwrap();
    client.next_incoming().await.unwrap();
    client
        .respond(&AcpRequestId::Number(2), method_not_found())
        .await
        .unwrap();
    let writes = writes.lock().unwrap();
    assert_eq!(writes.len(), 2);
    assert_eq!(writes[0]["id"], id.as_value());
    assert_eq!(writes[0]["error"]["code"], -32601);
    assert_eq!(serde_json::to_vec(&writes[0]).unwrap().len(), 512);
    assert_eq!(writes[1]["id"], 2);
    assert_eq!(writes[1]["error"]["message"], "Method not found");
    assert!(!closed.load(Ordering::SeqCst));
}

struct DeadlineHandler;

#[async_trait]
impl AcpClientRequestHandler for DeadlineHandler {
    async fn handle(
        &self,
        request: RpcRequest,
        _context: AcpRequestHandlerContext,
    ) -> Option<Result<Value, RpcError>> {
        if request.method == "x" {
            std::future::pending().await
        } else {
            None
        }
    }
}

#[tokio::test]
async fn long_id_deadline_error_preserves_code_and_next_request_stays_healthy() {
    let (mut transport, sender) = CallbackTransport::new();
    transport.max_frame_bytes = 512;
    let writes = transport.writes.clone();
    let written = transport.written.clone();
    let closed = transport.closed.clone();
    let mut client = AcpClient::with_options(transport, Duration::from_millis(20), 8);
    client.set_max_response_frame_bytes(512);
    client.set_request_handler(Some(Arc::new(DeadlineHandler)));
    let id = AcpRequestId::String("x".repeat(450));
    sender.send(request(id.as_value(), "x")).await.unwrap();
    {
        let next = client.next_incoming();
        tokio::pin!(next);
        tokio::select! {
            notified = tokio::time::timeout(Duration::from_secs(1), written.notified()) => {
                notified.expect("deadline response write timed out");
            },
            result = &mut next => panic!("deadline response was not sent: {result:?}"),
        }
    }
    sender.send(request(json!(2), "future")).await.unwrap();
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Request(_))
    ));
    client
        .respond(&AcpRequestId::Number(2), method_not_found())
        .await
        .unwrap();
    let writes = writes.lock().unwrap();
    assert_eq!(writes.len(), 2);
    assert_eq!(writes[0]["id"], id.as_value());
    assert_eq!(writes[0]["error"]["code"], -32001);
    assert_eq!(serde_json::to_vec(&writes[0]).unwrap().len(), 512);
    assert_eq!(writes[1]["id"], 2);
    assert!(!closed.load(Ordering::SeqCst));
}

#[tokio::test]
async fn impossible_id_budget_fails_before_send_and_leaves_transport_usable() {
    let (mut transport, sender) = CallbackTransport::new();
    transport.max_frame_bytes = 512;
    let writes = transport.writes.clone();
    let closed = transport.closed.clone();
    let mut client = AcpClient::new(transport);
    client.set_max_response_frame_bytes(512);
    let id = AcpRequestId::String("x".repeat(451));
    let frame = request(id.as_value(), "x");
    assert_eq!(serde_json::to_vec(&frame).unwrap().len(), 501);
    sender.send(frame).await.unwrap();
    client.next_incoming().await.unwrap();
    let error = client.respond(&id, method_not_found()).await.unwrap_err();
    assert!(matches!(error, AcpError::Protocol(message) if message.contains("minimum 513 bytes")));
    assert!(writes.lock().unwrap().is_empty());
    sender.send(request(json!(2), "x")).await.unwrap();
    client.next_incoming().await.unwrap();
    client
        .respond(&AcpRequestId::Number(2), method_not_found())
        .await
        .unwrap();
    assert_eq!(writes.lock().unwrap().len(), 1);
    assert!(!closed.load(Ordering::SeqCst));
}
