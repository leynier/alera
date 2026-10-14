use agent_client_protocol::{
    AcpClient, AcpClientRequestHandler, AcpError, AcpIncoming, AcpProtocolGeneration,
    AcpRequestHandlerContext, AcpRequestId, RpcError, RpcRequest,
};
use alera_agent_transport::{JsonTransport, MockTransport, TransportError};
use async_trait::async_trait;
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;

fn initialize_response() -> serde_json::Value {
    json!({"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2,"agentCapabilities":{"sessionCapabilities":{"resume":{}}},"authMethods":[]}})
}

#[tokio::test]
async fn initialize_and_session_keep_json_rpc_order() {
    let transport = MockTransport::new([
        initialize_response(),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-1","configOptions":[]}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    client.initialize("alera", "test").await.unwrap();
    let session = client.new_session(Some("/tmp"), &[]).await.unwrap();
    assert_eq!(session.session_id.as_deref(), Some("native-1"));
    let writes = client.transport().writes();
    assert_eq!(writes[0]["method"], "initialize");
    assert_eq!(writes[0]["id"], 1);
    assert_eq!(writes[1]["method"], "session/new");
    assert_eq!(writes[1]["id"], 2);
}

#[tokio::test]
async fn prompt_pump_surfaces_peer_request_before_terminal_response() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":9,"method":"session/request_permission","params":{"sessionId":"s","title":"Run","options":[{"optionId":"allow","kind":"allow_once","name":"Allow"}]}}),
        json!({"jsonrpc":"2.0","id":1,"result":{"stopReason":"end_turn"}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    let prompt_id = client
        .begin_prompt("s", vec![json!({"type":"text","text":"hi"})])
        .await
        .unwrap();
    assert_eq!(prompt_id, AcpRequestId::Number(1));
    let incoming = client.next_incoming().await.unwrap().unwrap();
    match incoming {
        AcpIncoming::Request(request) => assert_eq!(request.id, AcpRequestId::Number(9)),
        _ => panic!("expected peer request"),
    }
    let terminal = client.next_incoming().await.unwrap().unwrap();
    match terminal {
        AcpIncoming::Response(response) => {
            assert_eq!(response.id, prompt_id);
            assert_eq!(response.result.unwrap()["stopReason"], "end_turn");
        }
        _ => panic!("expected correlated prompt response"),
    }
}

#[tokio::test]
async fn string_and_integer_ids_are_not_interchangeable() {
    let transport = MockTransport::new([json!({"jsonrpc":"2.0","id":"1","result":{}})]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    let _ = client.begin_prompt("s", vec![]).await.unwrap();
    let result = client.next_incoming().await;
    assert!(result.is_err());
}

#[tokio::test]
async fn unexpected_eof_fails_the_outstanding_call() {
    let mut client = AcpClient::with_options(MockTransport::default(), Duration::from_secs(1), 8);
    let error = client.initialize("alera", "test").await.unwrap_err();
    assert!(matches!(error, AcpError::Closed));
}

struct SlowReceiveTransport;

#[async_trait]
impl JsonTransport for SlowReceiveTransport {
    async fn send(&mut self, _message: serde_json::Value) -> Result<(), TransportError> {
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<serde_json::Value>, TransportError> {
        tokio::time::sleep(Duration::from_millis(40)).await;
        Ok(None)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        Ok(())
    }
}

#[tokio::test]
async fn receive_timeout_bounds_a_stalled_transport() {
    let mut client = AcpClient::with_options(SlowReceiveTransport, Duration::from_millis(5), 8);
    let error = client.initialize("alera", "test").await.unwrap_err();
    assert!(matches!(error, AcpError::Timeout { .. }));
}

#[tokio::test]
async fn v2_initialize_selects_v2_auth_and_config_shapes() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "info":{"name":"agent","version":"1"},
                "capabilities":{"sessionCapabilities":{"resume":{}}},
                "authMethods":[{"methodId":"oauth","name":"OAuth","type":"agent"}]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{}}),
        json!({"jsonrpc":"2.0","id":3,"result":{}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    client.initialize("alera", "test").await.unwrap();
    assert_eq!(
        client.initialized().unwrap().generation,
        AcpProtocolGeneration::V2
    );
    client.authenticate("oauth").await.unwrap();
    client.set_mode("session", "yolo").await.unwrap();
    let writes = client.transport().writes();
    assert_eq!(writes[1]["method"], "auth/login");
    assert_eq!(writes[2]["method"], "session/set_config_option");
    assert_eq!(writes[2]["params"]["type"], "id");
}

#[tokio::test]
async fn v1_load_session_uses_top_level_load_session_method() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"loadSession":true},
                "authMethods":[]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    client.initialize("alera", "test").await.unwrap();
    let session = client
        .load_session("native-session", Some("/tmp"))
        .await
        .unwrap();
    assert_eq!(session.session_id.as_deref(), Some("native-session"));
    assert_eq!(client.transport().writes()[1]["method"], "session/load");
}

#[tokio::test]
async fn v1_resume_session_uses_resume_when_load_is_not_selected() {
    let transport = MockTransport::new([
        json!({
            "jsonrpc":"2.0","id":1,"result":{
                "protocolVersion":2,
                "agentCapabilities":{"sessionCapabilities":{"resume":{}}},
                "authMethods":[]
            }
        }),
        json!({"jsonrpc":"2.0","id":2,"result":{"sessionId":"native-session"}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    client.initialize("alera", "test").await.unwrap();
    client
        .resume_session("native-session", Some("/tmp"))
        .await
        .unwrap();
    assert_eq!(client.transport().writes()[1]["method"], "session/resume");
}

struct TerminalRequestHandler;

#[async_trait]
impl AcpClientRequestHandler for TerminalRequestHandler {
    async fn handle(
        &self,
        request: RpcRequest,
        context: AcpRequestHandlerContext,
    ) -> Option<Result<serde_json::Value, RpcError>> {
        assert_eq!(context.request_id, request.id);
        if request.method == "terminal/create" {
            Some(Ok(json!({"terminalId":"terminal-1"})))
        } else {
            None
        }
    }
}

struct SlowRequestHandler;

#[async_trait]
impl AcpClientRequestHandler for SlowRequestHandler {
    async fn handle(
        &self,
        _request: RpcRequest,
        _context: AcpRequestHandlerContext,
    ) -> Option<Result<serde_json::Value, RpcError>> {
        tokio::time::sleep(Duration::from_millis(50)).await;
        Some(Ok(json!({"done":true})))
    }
}

struct DelayedEofTransport(MockTransport);

#[async_trait]
impl JsonTransport for DelayedEofTransport {
    async fn send(&mut self, message: serde_json::Value) -> Result<(), TransportError> {
        self.0.send(message).await
    }

    async fn recv(&mut self) -> Result<Option<serde_json::Value>, TransportError> {
        let message = self.0.recv().await?;
        if message.is_none() {
            tokio::time::sleep(Duration::from_millis(40)).await;
        }
        Ok(message)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.0.close().await
    }
}

#[tokio::test]
async fn request_handler_replies_with_exact_id_and_leaves_unhandled_requests_visible() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":9,"method":"terminal/create","params":{"command":"pwd"}}),
        json!({"jsonrpc":"2.0","id":"future","method":"future/request","params":{}}),
    ]);
    let mut client = AcpClient::with_options(transport, Duration::from_secs(1), 8);
    client.set_request_handler(Some(Arc::new(TerminalRequestHandler)));
    let incoming = client.next_incoming().await.unwrap().unwrap();
    assert!(matches!(incoming, AcpIncoming::Request(_)));
    let writes = client.transport().writes();
    assert_eq!(writes[0]["id"], 9);
    assert_eq!(writes[0]["result"]["terminalId"], "terminal-1");
}

#[tokio::test]
async fn request_handler_deadline_cancels_slow_operation() {
    let transport = MockTransport::new([
        json!({"jsonrpc":"2.0","id":9,"method":"terminal/wait_for_exit","params":{}}),
    ]);
    let mut client =
        AcpClient::with_options(DelayedEofTransport(transport), Duration::from_millis(5), 8);
    client.set_request_handler(Some(Arc::new(SlowRequestHandler)));
    assert!(client.next_incoming().await.unwrap().is_none());
    let response = client.transport().0.writes().last().unwrap();
    assert_eq!(response["id"], 9);
    assert_eq!(response["error"]["code"], -32001);
}
