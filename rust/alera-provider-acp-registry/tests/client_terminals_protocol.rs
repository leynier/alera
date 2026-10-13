use alera_agent_transport::{JsonTransport, TransportError};
use alera_provider_acp_registry::{AcpRegistryProvider, AcpRegistryProviderConfig};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, InterruptInput, Provider, RuntimeResponse, SessionStartInput,
    TurnInput,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::time::Duration;
use tokio::sync::mpsc;

struct ChannelTransport {
    frames: mpsc::UnboundedReceiver<Value>,
    writes: mpsc::UnboundedSender<Value>,
    fail_permission_response: bool,
    max_frame_bytes: usize,
}

#[async_trait]
impl JsonTransport for ChannelTransport {
    async fn send(&mut self, value: Value) -> Result<(), TransportError> {
        let observed = serde_json::to_vec(&value).unwrap().len();
        if observed > self.max_frame_bytes {
            self.frames.close();
            return Err(TransportError::FrameTooLarge {
                limit: self.max_frame_bytes,
                observed,
            });
        }
        if self.fail_permission_response
            && value.get("id") == Some(&json!("permit"))
            && value.get("method").is_none()
        {
            return Err(TransportError::Closed);
        }
        self.writes.send(value).map_err(|_| TransportError::Closed)
    }
    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        Ok(self.frames.recv().await)
    }
    async fn close(&mut self) -> Result<(), TransportError> {
        self.frames.close();
        Ok(())
    }
}

async fn start(
    fail_permission_response: bool,
) -> (
    AcpRegistryProvider<ChannelTransport>,
    mpsc::UnboundedSender<Value>,
    mpsc::UnboundedReceiver<Value>,
) {
    start_with_budget(fail_permission_response, 1024 * 1024).await
}

async fn start_with_budget(
    fail_permission_response: bool,
    max_frame_bytes: usize,
) -> (
    AcpRegistryProvider<ChannelTransport>,
    mpsc::UnboundedSender<Value>,
    mpsc::UnboundedReceiver<Value>,
) {
    let (sender, frames) = mpsc::unbounded_channel();
    let (writes, mut receiver) = mpsc::unbounded_channel();
    sender
        .send(json!({"jsonrpc":"2.0", "id":1, "result":{"protocolVersion":2, "authMethods":[]}}))
        .unwrap();
    sender
        .send(json!({"jsonrpc":"2.0", "id":2, "result":{"sessionId":"native"}}))
        .unwrap();
    let mut provider = AcpRegistryProvider::with_transport(
        ChannelTransport {
            frames,
            writes,
            fail_permission_response,
            max_frame_bytes,
        },
        AcpRegistryProviderConfig {
            agent_id: "devin".into(),
            request_timeout: Duration::from_secs(5),
            max_frame_bytes,
            ..Default::default()
        },
    )
    .unwrap();
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let initialize = receiver.recv().await.unwrap();
    assert_eq!(initialize["params"]["clientCapabilities"]["terminal"], true);
    assert_eq!(
        initialize["params"]["clientCapabilities"]["fs"],
        json!({"readTextFile":false, "writeTextFile":false})
    );
    assert_eq!(receiver.recv().await.unwrap()["method"], "session/new");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::ThreadStarted
    );
    provider
        .send_turn(TurnInput::text("app", "run fixture"))
        .await
        .unwrap();
    assert_eq!(receiver.recv().await.unwrap()["method"], "session/prompt");
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::TurnStarted
    );
    (provider, sender, receiver)
}

fn permission(options: Value) -> Value {
    json!({"jsonrpc":"2.0", "id":"permit", "method":"session/request_permission", "params":{"sessionId":"native", "toolCall":{"toolCallId":"command", "kind":"execute", "title":"Run command"}, "options":options}})
}

async fn approve(
    provider: &mut AcpRegistryProvider<ChannelTransport>,
    sender: &mpsc::UnboundedSender<Value>,
    decision: ApprovalDecision,
    options: Value,
) -> Result<(), alera_provider_protocol::ProviderError> {
    sender.send(permission(options)).unwrap();
    let request = provider
        .next_event()
        .await
        .unwrap()
        .unwrap()
        .runtime_request
        .unwrap();
    assert_eq!(
        request.kind,
        alera_provider_protocol::RequestKind::CommandExecutionApproval
    );
    provider
        .respond(RuntimeResponse::Approval {
            request_id: request.request_id,
            decision,
            updated_input: None,
        })
        .await
}

async fn receive_id(receiver: &mut mpsc::UnboundedReceiver<Value>, id: Value) -> Value {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let frame = receiver.recv().await.unwrap();
            if frame.get("id") == Some(&id) {
                return frame;
            }
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn wait_reply_survives_cancelled_event_poll_and_interrupt_is_responsive() {
    let (mut provider, sender, mut receiver) = start(false).await;
    approve(
        &mut provider,
        &sender,
        ApprovalDecision::Accept,
        json!([{"optionId":"once", "kind":"allow_once"}]),
    )
    .await
    .unwrap();
    assert_eq!(
        receive_id(&mut receiver, json!("permit")).await["result"]["outcome"]["optionId"],
        "once"
    );
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::RequestResolved
    );
    sender.send(json!({"jsonrpc":"2.0", "id":77, "method":"terminal/create", "params":{"sessionId":"native", "command":env!("CARGO_BIN_EXE_acp-terminal-fixture"), "args":["linger"]}})).unwrap();
    let remote_sender = sender.clone();
    let remote = tokio::spawn(async move {
        let create = receive_id(&mut receiver, json!(77)).await;
        assert!(create.get("error").is_none(), "{create}");
        let terminal_id = create["result"]["terminalId"].clone();
        remote_sender.send(json!({"jsonrpc":"2.0", "method":"session/update", "params":{"sessionId":"native", "update":{"sessionUpdate":"tool_call", "toolCallId":"terminal-tool", "kind":"execute", "title":"Fixture", "content":[{"type":"terminal", "terminalId":terminal_id}], "_meta":{"native":"metadata"}}}})).unwrap();
        (receiver, terminal_id)
    });
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::ItemStarted);
    assert_eq!(event.payload["itemType"], "command_execution");
    assert_eq!(event.payload["data"]["_meta"]["native"], "metadata");
    assert_eq!(
        event.raw.as_ref().unwrap().payload["params"]["update"]["content"][0]["type"],
        "terminal"
    );
    let (mut receiver, terminal_id) = remote.await.unwrap();
    sender.send(json!({"jsonrpc":"2.0", "id":"77", "method":"terminal/wait_for_exit", "params":{"sessionId":"native", "terminalId":terminal_id}})).unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(100), provider.next_event())
            .await
            .is_err()
    );
    tokio::time::timeout(
        Duration::from_secs(1),
        provider.interrupt(InterruptInput {
            thread_id: "app".into(),
            turn_id: None,
        }),
    )
    .await
    .expect("interrupt must not wait on terminal callback")
    .unwrap();
    let remote = tokio::spawn(async move {
        let wait = receive_id(&mut receiver, json!("77")).await;
        assert!(wait.get("error").is_none(), "{wait}");
        #[cfg(unix)]
        assert_eq!(wait["result"]["signal"], "SIGKILL");
        sender
            .send(json!({"jsonrpc":"2.0", "id":3, "result":{"stopReason":"cancelled"}}))
            .unwrap();
    });
    let completed = tokio::time::timeout(Duration::from_secs(5), provider.next_event())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(completed.kind, EventKind::TurnCompleted);
    assert_eq!(completed.payload["state"], "interrupted");
    remote.await.unwrap();
    provider.close().await.unwrap();
}

async fn assert_terminal_denied(
    mut provider: AcpRegistryProvider<ChannelTransport>,
    sender: mpsc::UnboundedSender<Value>,
    mut receiver: mpsc::UnboundedReceiver<Value>,
) {
    sender.send(json!({"jsonrpc":"2.0", "id":88, "method":"terminal/create", "params":{"sessionId":"native", "command":"must-never-execute"}})).unwrap();
    let remote = tokio::spawn(async move {
        let denied = receive_id(&mut receiver, json!(88)).await;
        assert_eq!(denied["error"]["code"], -32002);
        sender
            .send(json!({"jsonrpc":"2.0", "id":99, "method":"future/unknown", "params":{}}))
            .unwrap();
        let unknown = receive_id(&mut receiver, json!(99)).await;
        assert_eq!(unknown["error"]["code"], -32601);
    });
    let event = tokio::time::timeout(Duration::from_secs(5), provider.next_event())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(
        event.kind,
        EventKind::Unknown("acp.request.future/unknown".into())
    );
    remote.await.unwrap();
    provider.close().await.unwrap();
}

#[tokio::test]
async fn unapproved_terminal_create_fails_with_permission_error_and_unknown_methods_remain_unhandled(
) {
    let (provider, sender, receiver) = start(false).await;
    assert_terminal_denied(provider, sender, receiver).await;
}

#[tokio::test]
async fn failed_permission_response_write_closes_acp_connection() {
    let (mut provider, sender, _receiver) = start(true).await;
    assert!(approve(
        &mut provider,
        &sender,
        ApprovalDecision::Accept,
        json!([{"optionId":"once", "kind":"allow_once"}])
    )
    .await
    .is_err());
    assert!(sender.is_closed());
    assert!(matches!(
        provider.next_event().await,
        Err(alera_provider_protocol::ProviderError::Closed)
    ));
    provider.close().await.unwrap();
}

#[tokio::test]
async fn unsupported_session_approval_does_not_grant_execution_or_write_a_fallback() {
    let (mut provider, sender, receiver) = start(false).await;
    assert!(approve(
        &mut provider,
        &sender,
        ApprovalDecision::AcceptForSession,
        json!([{"optionId":"once", "kind":"allow_once"}])
    )
    .await
    .is_err());
    assert_terminal_denied(provider, sender, receiver).await;
}

#[tokio::test]
async fn escaped_terminal_output_fits_native_wire_budget_and_later_requests_succeed() {
    let budget = 512;
    let (mut provider, sender, mut receiver) = start_with_budget(false, budget).await;
    approve(
        &mut provider,
        &sender,
        ApprovalDecision::Accept,
        json!([{"optionId":"once", "kind":"allow_once"}]),
    )
    .await
    .unwrap();
    receive_id(&mut receiver, json!("permit")).await;
    assert_eq!(
        provider.next_event().await.unwrap().unwrap().kind,
        EventKind::RequestResolved
    );
    sender.send(json!({"jsonrpc":"2.0", "id":"create", "method":"terminal/create", "params":{"sessionId":"native", "command":env!("CARGO_BIN_EXE_acp-terminal-fixture"), "args":["control"]}})).unwrap();
    let remote = tokio::spawn(async move {
        let created = receive_id(&mut receiver, json!("create")).await;
        assert!(created.get("error").is_none(), "{created}");
        let terminal_id = created["result"]["terminalId"].clone();
        sender.send(json!({"jsonrpc":"2.0", "id":"wait", "method":"terminal/wait_for_exit", "params":{"sessionId":"native", "terminalId":terminal_id}})).unwrap();
        let exit = receive_id(&mut receiver, json!("wait")).await;
        assert_eq!(exit["result"]["exitCode"], 0);
        for id in [json!("output\"id\n"), json!(22)] {
            sender.send(json!({"jsonrpc":"2.0", "id":id, "method":"terminal/output", "params":{"sessionId":"native", "terminalId":terminal_id}})).unwrap();
            let output = receive_id(&mut receiver, id).await;
            assert!(output.get("error").is_none(), "{output}");
            assert!(serde_json::to_vec(&output).unwrap().len() <= budget);
            assert_eq!(output["result"]["truncated"], true);
            assert!(output["result"]["output"]
                .as_str()
                .unwrap()
                .ends_with("😀tail\n"));
        }
        sender.send(json!({"jsonrpc":"2.0", "id":23, "method":"terminal/release", "params":{"sessionId":"native", "terminalId":terminal_id}})).unwrap();
        assert_eq!(
            receive_id(&mut receiver, json!(23)).await["result"],
            json!({})
        );
        sender
            .send(json!({"jsonrpc":"2.0", "id":24, "method":"future/unknown", "params":{}}))
            .unwrap();
        assert_eq!(
            receive_id(&mut receiver, json!(24)).await["error"]["code"],
            -32601
        );
    });
    let event = tokio::time::timeout(Duration::from_secs(5), provider.next_event())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(
        event.kind,
        EventKind::Unknown("acp.request.future/unknown".into())
    );
    remote.await.unwrap();
    provider.close().await.unwrap();
}
