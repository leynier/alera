#[path = "support/callback_transport.rs"]
mod callback_transport;

use agent_client_protocol::{
    AcpClient, AcpClientRequestHandler, AcpError, AcpIncoming, AcpRequestHandlerContext,
    AcpRequestId, RpcError, RpcRequest,
};
use alera_agent_transport::MockTransport;
use async_trait::async_trait;
use callback_transport::CallbackTransport;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Notify;

const TEST_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Default)]
struct ConcurrentHandler {
    started: Notify,
    release: Notify,
    dropped: Notify,
    drop_count: AtomicUsize,
    terminal: bool,
}

struct CallbackGuard<'a>(&'a ConcurrentHandler);

impl Drop for CallbackGuard<'_> {
    fn drop(&mut self) {
        self.0.drop_count.fetch_add(1, Ordering::SeqCst);
        self.0.dropped.notify_one();
    }
}

#[async_trait]
impl AcpClientRequestHandler for ConcurrentHandler {
    fn supports_terminal(&self) -> bool {
        self.terminal
    }

    async fn handle(
        &self,
        request: RpcRequest,
        context: AcpRequestHandlerContext,
    ) -> Option<Result<Value, RpcError>> {
        assert_eq!(context.request_id, request.id);
        assert!(!context.is_expired());
        match request.method.as_str() {
            "terminal/wait_for_exit" => {
                let _guard = CallbackGuard(self);
                self.started.notify_one();
                self.release.notified().await;
                Some(Ok(json!({"exitCode":0})))
            }
            "terminal/kill" => {
                self.release.notify_one();
                Some(Ok(json!({"killed":true})))
            }
            "terminal/create" => Some(Ok(json!({"terminalId":"terminal-1"}))),
            _ => None,
        }
    }
}

fn request(id: Value, method: &str) -> Value {
    json!({"jsonrpc":"2.0","id":id,"method":method,"params":{}})
}

fn notification() -> Value {
    json!({"jsonrpc":"2.0","method":"session/update","params":{"progress":true}})
}

async fn wait_for(signal: &Notify) {
    tokio::time::timeout(TEST_TIMEOUT, signal.notified())
        .await
        .expect("callback signal timed out");
}

#[tokio::test]
async fn blocked_wait_does_not_block_notifications_permissions_or_kill() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let handler = Arc::new(ConcurrentHandler::default());
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(handler.clone()));
    sender
        .send(request(json!("wait"), "terminal/wait_for_exit"))
        .await
        .unwrap();
    sender.send(notification()).await.unwrap();
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Notification { .. })
    ));
    wait_for(&handler.started).await;

    sender
        .send(request(json!("permission"), "session/request_permission"))
        .await
        .unwrap();
    let permission = client.next_incoming().await.unwrap().unwrap();
    assert!(
        matches!(permission, AcpIncoming::Request(request) if request.id == AcpRequestId::String("permission".into()))
    );
    client
        .respond(
            &AcpRequestId::String("permission".into()),
            Ok(json!({"allowed":true})),
        )
        .await
        .unwrap();
    sender
        .send(request(json!(9), "terminal/kill"))
        .await
        .unwrap();
    sender.send(notification()).await.unwrap();
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Notification { .. })
    ));
    wait_for(&handler.dropped).await;
    client.cancel("session").await.unwrap();

    let writes = writes.lock().unwrap();
    assert_eq!(
        writes.iter().filter(|frame| frame["id"] == "wait").count(),
        1
    );
    assert_eq!(writes.iter().filter(|frame| frame["id"] == 9).count(), 1);
    assert_eq!(
        writes
            .iter()
            .filter(|frame| frame["id"] == "permission")
            .count(),
        1
    );
    assert!(writes
        .iter()
        .any(|frame| frame["method"] == "session/cancel"));
}

#[tokio::test]
async fn cancelled_read_keeps_callback_and_sends_exact_response_once() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let handler = Arc::new(ConcurrentHandler::default());
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(handler.clone()));
    sender
        .send(request(json!("9"), "terminal/wait_for_exit"))
        .await
        .unwrap();
    {
        let next = client.next_incoming();
        tokio::pin!(next);
        tokio::select! {
            _ = wait_for(&handler.started) => {},
            result = &mut next => panic!("read finished while callback was blocked: {result:?}"),
        }
    }
    handler.release.notify_one();
    wait_for(&handler.dropped).await;
    client.cancel("session").await.unwrap();
    sender.send(notification()).await.unwrap();
    client.next_incoming().await.unwrap();
    client.cancel("session").await.unwrap();
    let writes = writes.lock().unwrap();
    let responses = writes
        .iter()
        .filter(|frame| frame.get("id").is_some())
        .collect::<Vec<_>>();
    assert_eq!(responses.len(), 1);
    assert_eq!(responses[0]["id"], "9");
    assert_eq!(responses[0]["result"]["exitCode"], 0);
}

#[tokio::test]
async fn cancelled_response_write_retains_outbox_until_success() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let gate = transport.gate.clone();
    gate.blocked.store(true, Ordering::SeqCst);
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(Arc::new(ConcurrentHandler::default())));
    sender
        .send(request(json!(41), "terminal/create"))
        .await
        .unwrap();
    {
        let next = client.next_incoming();
        tokio::pin!(next);
        tokio::select! {
            _ = wait_for(&gate.started) => {},
            result = &mut next => panic!("write did not remain blocked: {result:?}"),
        }
    }
    assert!(writes.lock().unwrap().is_empty());
    gate.blocked.store(false, Ordering::SeqCst);
    sender.send(notification()).await.unwrap();
    client.next_incoming().await.unwrap();
    client.cancel("session").await.unwrap();
    let writes = writes.lock().unwrap();
    assert_eq!(writes.iter().filter(|frame| frame["id"] == 41).count(), 1);
    assert_eq!(writes[0]["result"]["terminalId"], "terminal-1");
}

#[tokio::test]
async fn close_and_drop_abort_callback_futures() {
    for explicit_close in [true, false] {
        let (transport, sender) = CallbackTransport::new();
        let closed = transport.closed.clone();
        let handler = Arc::new(ConcurrentHandler::default());
        let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
        client.set_request_handler(Some(handler.clone()));
        sender
            .send(request(json!(1), "terminal/wait_for_exit"))
            .await
            .unwrap();
        sender.send(notification()).await.unwrap();
        client.next_incoming().await.unwrap();
        wait_for(&handler.started).await;
        if explicit_close {
            client.close().await.unwrap();
            assert!(closed.load(Ordering::SeqCst));
        }
        drop(client);
        wait_for(&handler.dropped).await;
        assert_eq!(handler.drop_count.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test]
async fn eof_aborts_callback_instead_of_waiting_for_its_deadline() {
    let (transport, sender) = CallbackTransport::new();
    let handler = Arc::new(ConcurrentHandler::default());
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(handler.clone()));
    sender
        .send(request(json!(1), "terminal/wait_for_exit"))
        .await
        .unwrap();
    sender.send(notification()).await.unwrap();
    client.next_incoming().await.unwrap();
    wait_for(&handler.started).await;
    drop(sender);
    assert!(client.next_incoming().await.unwrap().is_none());
    assert_eq!(handler.drop_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn duplicate_ids_and_callback_overflow_abort_and_reap_pending_work() {
    for duplicate in [true, false] {
        let (transport, sender) = CallbackTransport::new();
        let closed = transport.closed.clone();
        let handler = Arc::new(ConcurrentHandler::default());
        let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 1);
        client.set_request_handler(Some(handler.clone()));
        sender
            .send(request(json!(1), "terminal/wait_for_exit"))
            .await
            .unwrap();
        sender.send(notification()).await.unwrap();
        client.next_incoming().await.unwrap();
        wait_for(&handler.started).await;
        sender
            .send(request(
                json!(if duplicate { 1 } else { 2 }),
                "terminal/wait_for_exit",
            ))
            .await
            .unwrap();
        let error = client.next_incoming().await.unwrap_err();
        if duplicate {
            assert!(
                matches!(error, AcpError::Protocol(message) if message.contains("duplicate outstanding"))
            );
        } else {
            assert!(matches!(error, AcpError::QueueFull { capacity: 1 }));
        }
        assert_eq!(handler.drop_count.load(Ordering::SeqCst), 1);
        assert!(closed.load(Ordering::SeqCst));
        assert!(matches!(
            client.next_incoming().await,
            Err(AcpError::Closed)
        ));
    }
}

#[tokio::test]
async fn callback_deadline_returns_timeout_with_original_null_id() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let written = transport.written.clone();
    let handler = Arc::new(ConcurrentHandler::default());
    let mut client = AcpClient::with_options(transport, Duration::from_millis(10), 8);
    client.set_request_handler(Some(handler.clone()));
    sender
        .send(request(Value::Null, "terminal/wait_for_exit"))
        .await
        .unwrap();
    {
        let next = client.next_incoming();
        tokio::pin!(next);
        tokio::select! {
            _ = wait_for(&written) => {},
            result = &mut next => panic!("read finished unexpectedly: {result:?}"),
        }
    }
    assert_eq!(handler.drop_count.load(Ordering::SeqCst), 1);
    let writes = writes.lock().unwrap();
    assert_eq!(writes.len(), 1);
    assert_eq!(writes[0]["id"], Value::Null);
    assert_eq!(writes[0]["error"]["code"], -32001);
    assert!(writes[0]["error"]["message"]
        .as_str()
        .unwrap()
        .contains("terminal/wait_for_exit"));
}

#[tokio::test]
async fn unhandled_request_can_receive_method_not_found_only_once() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(Arc::new(ConcurrentHandler::default())));
    sender
        .send(request(json!("future"), "future/request"))
        .await
        .unwrap();
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Request(_))
    ));
    let id = AcpRequestId::String("future".into());
    let response = Err(RpcError {
        code: -32601,
        message: "Method not found".into(),
        data: None,
    });
    client.respond(&id, response.clone()).await.unwrap();
    assert!(matches!(
        client.respond(&id, response).await,
        Err(AcpError::Protocol(_))
    ));
    let writes = writes.lock().unwrap();
    assert_eq!(writes.len(), 1);
    assert_eq!(writes[0]["id"], "future");
    assert_eq!(writes[0]["error"]["code"], -32601);
}

#[tokio::test]
async fn only_terminal_service_handlers_advertise_terminal_support() {
    for terminal in [false, true] {
        let transport = MockTransport::new([
            json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{}}}),
        ]);
        let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
        client.set_request_handler(Some(Arc::new(ConcurrentHandler {
            terminal,
            ..Default::default()
        })));
        client.initialize("alera", "test").await.unwrap();
        assert_eq!(
            client.transport().writes()[0]["params"]["clientCapabilities"]["terminal"],
            terminal
        );
    }
}

#[tokio::test]
async fn initialize_response_is_not_blocked_by_callback_wait() {
    let (transport, sender) = CallbackTransport::new();
    let handler = Arc::new(ConcurrentHandler::default());
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 8);
    client.set_request_handler(Some(handler.clone()));
    sender
        .send(request(json!(90), "terminal/wait_for_exit"))
        .await
        .unwrap();
    sender.send(notification()).await.unwrap();
    sender
        .send(json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{}}}))
        .await
        .unwrap();
    client.initialize("alera", "test").await.unwrap();
    wait_for(&handler.started).await;
    assert!(matches!(
        client.next_incoming().await.unwrap(),
        Some(AcpIncoming::Notification { .. })
    ));
    client.close().await.unwrap();
    assert_eq!(handler.drop_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn cancelled_response_write_keeps_its_original_deadline() {
    let (transport, sender) = CallbackTransport::new();
    let writes = transport.writes.clone();
    let gate = transport.gate.clone();
    gate.blocked.store(true, Ordering::SeqCst);
    let mut client = AcpClient::with_options(transport, Duration::from_millis(20), 8);
    client.set_request_handler(Some(Arc::new(ConcurrentHandler::default())));
    sender
        .send(request(json!(42), "terminal/create"))
        .await
        .unwrap();
    {
        let next = client.next_incoming();
        tokio::pin!(next);
        tokio::select! {
            _ = wait_for(&gate.started) => {},
            result = &mut next => panic!("write did not remain blocked: {result:?}"),
        }
    }
    tokio::time::sleep(Duration::from_millis(40)).await;
    client.set_timeout(TEST_TIMEOUT);
    let error = client.cancel("session").await.unwrap_err();
    assert!(matches!(error, AcpError::Timeout { method, .. } if method == "peer response 42"));
    assert!(writes.lock().unwrap().is_empty());
    assert!(matches!(
        client.next_incoming().await,
        Err(AcpError::Closed)
    ));
}

#[tokio::test]
async fn outstanding_outbound_requests_are_bounded() {
    let (transport, _sender) = CallbackTransport::new();
    let mut client = AcpClient::with_options(transport, TEST_TIMEOUT, 1);
    client.begin_prompt("session", vec![]).await.unwrap();
    assert!(matches!(
        client.begin_prompt("session", vec![]).await,
        Err(AcpError::QueueFull { capacity: 1 })
    ));
    assert_eq!(client.state().pending_requests, 1);
}
