use async_trait::async_trait;
use claude_agent_sdk::{
    ClaudeAgentOptions, ClaudeClient, JsonTransport, PermissionCallback, PermissionResult,
    TransportError,
};
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tokio::time::Duration;

struct FakeTransport {
    incoming: mpsc::UnboundedReceiver<Value>,
    incoming_tx: mpsc::UnboundedSender<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
    ask_permission: bool,
    answer_initialize: bool,
    closed: bool,
}

impl FakeTransport {
    fn new(ask_permission: bool, answer_initialize: bool) -> (Self, Arc<Mutex<Vec<Value>>>) {
        let (incoming_tx, incoming) = mpsc::unbounded_channel();
        let writes = Arc::new(Mutex::new(Vec::new()));
        (
            Self {
                incoming,
                incoming_tx,
                writes: Arc::clone(&writes),
                ask_permission,
                answer_initialize,
                closed: false,
            },
            writes,
        )
    }

    fn response(&self, request_id: &str, payload: Value) {
        let _ = self.incoming_tx.send(json!({
            "type": "control_response",
            "response": { "subtype": "success", "request_id": request_id, "response": payload }
        }));
    }

    fn result_messages(&self) {
        let _ = self.incoming_tx.send(json!({
            "type": "assistant",
            "session_id": "session",
            "message": { "role": "assistant", "model": "claude-sonnet", "content": [{ "type": "text", "text": "ok" }] }
        }));
        let _ = self.incoming_tx.send(json!({
            "type": "result", "subtype": "success", "duration_ms": 1,
            "duration_api_ms": 1, "is_error": false, "num_turns": 1,
            "session_id": "session", "result": "ok"
        }));
    }
}

#[async_trait]
impl JsonTransport for FakeTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        if self.closed {
            return Err(TransportError::Closed);
        }
        self.writes.lock().await.push(message.clone());
        match message.get("type").and_then(Value::as_str) {
            Some("control_request") => {
                let id = message
                    .get("request_id")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                let request = message.get("request").cloned().unwrap_or(Value::Null);
                match request.get("subtype").and_then(Value::as_str) {
                    Some("initialize") if self.answer_initialize => {
                        self.response(id, json!({ "commands": [] }))
                    }
                    Some("initialize") => {}
                    Some(_) => self.response(id, Value::Object(Default::default())),
                    None => {}
                }
            }
            Some("user") if self.ask_permission => {
                let _ = self.incoming_tx.send(json!({
                    "type": "control_request", "request_id": "permission_1",
                    "request": { "subtype": "can_use_tool", "tool_name": "Write",
                        "input": { "file": "answer.txt" }, "permission_suggestions": [],
                        "tool_use_id": "tool_1" }
                }));
            }
            Some("user") => self.result_messages(),
            Some("control_response") if self.ask_permission => self.result_messages(),
            _ => {}
        }
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        Ok(self.incoming.recv().await)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed = true;
        Ok(())
    }
}

#[tokio::test]
async fn initializes_sends_prompt_and_parses_messages() {
    let (transport, writes) = FakeTransport::new(false, true);
    let client = ClaudeClient::with_transport(transport, ClaudeAgentOptions::default()).unwrap();
    let initialization = client.initialize().await.unwrap();
    assert_eq!(initialization["commands"], json!([]));
    client.send_prompt("hello").await.unwrap();
    assert_eq!(
        client.next_message().await.unwrap().unwrap().kind(),
        "assistant"
    );
    assert!(client
        .next_message()
        .await
        .unwrap()
        .unwrap()
        .is_terminal_result());

    let writes = writes.lock().await;
    assert_eq!(writes[0]["type"], "control_request");
    assert_eq!(writes[0]["request"]["subtype"], "initialize");
    assert_eq!(writes[1]["type"], "user");
    assert_eq!(writes[1]["message"]["content"], "hello");
    client.close().await.unwrap();
}

#[tokio::test]
async fn dynamic_control_commands_use_typed_wire_shapes() {
    let (transport, writes) = FakeTransport::new(false, true);
    let client = ClaudeClient::connect_with_transport(transport, ClaudeAgentOptions::default())
        .await
        .unwrap();
    client
        .set_model(Some("claude-opus".to_owned()))
        .await
        .unwrap();
    client.set_permission_mode("plan").await.unwrap();
    client.rewind_files("user-1").await.unwrap();
    client.reconnect_mcp_server("files").await.unwrap();
    client.toggle_mcp_server("files", false).await.unwrap();
    client.stop_task("task-1").await.unwrap();
    client.interrupt().await.unwrap();

    let writes = writes.lock().await;
    let subtypes = writes
        .iter()
        .filter_map(|frame| {
            frame
                .get("request")
                .and_then(|request| request.get("subtype"))
                .and_then(Value::as_str)
        })
        .collect::<Vec<_>>();
    assert!(subtypes.contains(&"set_model"));
    assert!(subtypes.contains(&"set_permission_mode"));
    assert!(subtypes.contains(&"rewind_files"));
    assert!(subtypes.contains(&"mcp_reconnect"));
    assert!(subtypes.contains(&"mcp_toggle"));
    assert!(subtypes.contains(&"stop_task"));
    assert!(subtypes.contains(&"interrupt"));
    client.close().await.unwrap();
}

#[tokio::test]
async fn permission_callback_round_trips_incoming_control_request() {
    let (transport, writes) = FakeTransport::new(true, true);
    let callback: PermissionCallback =
        Arc::new(|_tool, _input, _context| Box::pin(async { Ok(PermissionResult::allow()) }));
    let options = ClaudeAgentOptions {
        permission_callback: Some(callback),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    client.send_prompt("write a file").await.unwrap();
    let first = client.next_message().await.unwrap().unwrap();
    if !first.is_terminal_result() {
        assert!(client
            .next_message()
            .await
            .unwrap()
            .unwrap()
            .is_terminal_result());
    }

    let writes = writes.lock().await;
    let response = writes
        .iter()
        .find(|frame| frame.get("type") == Some(&json!("control_response")))
        .expect("permission response");
    assert_eq!(response["response"]["subtype"], "success");
    assert_eq!(response["response"]["response"]["behavior"], "allow");
    assert_eq!(
        response["response"]["response"]["updatedInput"]["file"],
        "answer.txt"
    );
    client.close().await.unwrap();
}

#[tokio::test]
async fn initialize_timeout_is_bounded() {
    let (transport, _) = FakeTransport::new(false, false);
    let options = ClaudeAgentOptions {
        initialize_timeout: Duration::from_millis(5),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::with_transport(transport, options).unwrap();
    let error = client.initialize().await.unwrap_err();
    assert!(matches!(
        error,
        claude_agent_sdk::ClaudeSdkError::Timeout { .. }
    ));
    client.close().await.unwrap();
}
