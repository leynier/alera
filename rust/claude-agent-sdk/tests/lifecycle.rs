use async_trait::async_trait;
use claude_agent_sdk::{
    ClaudeAgentOptions, ClaudeClient, HookMatcher, HookOutput, JsonTransport, PermissionCallback,
    PermissionResult, TransportError,
};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex, Notify};
use tokio::time::{sleep, timeout, Duration};
#[derive(Clone, Copy)]
enum Mode {
    Reorder,
    Burst,
    Cancel,
    Hook,
    Mcp,
    Turns,
    HangCallback,
}
type ScriptParts = (
    ScriptTransport,
    mpsc::UnboundedSender<Value>,
    Arc<Mutex<Vec<Value>>>,
    Arc<AtomicBool>,
);
struct ScriptTransport {
    incoming: mpsc::UnboundedReceiver<Value>,
    incoming_tx: mpsc::UnboundedSender<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
    pending: Vec<(String, String)>,
    mode: Mode,
    closed: Arc<AtomicBool>,
}
impl ScriptTransport {
    fn new(mode: Mode) -> ScriptParts {
        let (incoming_tx, incoming) = mpsc::unbounded_channel();
        let writes = Arc::new(Mutex::new(Vec::new()));
        let closed = Arc::new(AtomicBool::new(false));
        (
            Self {
                incoming,
                incoming_tx: incoming_tx.clone(),
                writes: Arc::clone(&writes),
                pending: Vec::new(),
                mode,
                closed: Arc::clone(&closed),
            },
            incoming_tx,
            writes,
            closed,
        )
    }
    fn enqueue(&self, frame: Value) {
        let _ = self.incoming_tx.send(frame);
    }
    fn success(&self, request_id: &str, response: Value) {
        self.enqueue(json!({ "type": "control_response", "response": { "subtype": "success", "request_id": request_id, "response": response } }));
    }
}
#[async_trait]
impl JsonTransport for ScriptTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        if self.closed.load(Ordering::Acquire) {
            return Err(TransportError::Closed);
        }
        self.writes.lock().await.push(message.clone());
        if matches!(self.mode, Mode::HangCallback)
            && message.get("type").and_then(Value::as_str) == Some("control_response")
        {
            sleep(Duration::from_secs(10)).await;
            return Ok(());
        }
        if message.get("type").and_then(Value::as_str) == Some("control_request") {
            let id = message
                .get("request_id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let request = message.get("request").cloned().unwrap_or(Value::Null);
            let subtype = request
                .get("subtype")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            match self.mode {
                Mode::Reorder => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                    } else if subtype == "error" {
                        self.enqueue(json!({ "type": "control_response", "response": { "subtype": "error", "request_id": id, "error": "scripted control failure" } }));
                    } else {
                        self.pending.push((id, subtype));
                        if self.pending.len() == 2 {
                            for (request_id, pending_subtype) in
                                std::mem::take(&mut self.pending).into_iter().rev()
                            {
                                self.success(&request_id, json!({ "subtype": pending_subtype }));
                            }
                        }
                    }
                }
                Mode::Burst => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                        for index in 0..128 {
                            self.enqueue(
                                json!({ "type": "system", "subtype": "burst", "index": index }),
                            );
                        }
                    } else if subtype == "ping" {
                        self.success(&id, json!({ "subtype": subtype }));
                        for index in 128..256 {
                            self.enqueue(
                                json!({ "type": "system", "subtype": "burst", "index": index }),
                            );
                        }
                    } else {
                        self.success(&id, json!({ "subtype": subtype }));
                    }
                }
                Mode::Cancel => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                    }
                }
                Mode::Hook => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                        let callback_id = request["hooks"]["PreToolUse"][0]["hookCallbackIds"][0]
                            .as_str()
                            .unwrap_or_default();
                        self.enqueue(json!({ "type": "control_request", "request_id": "hook-1", "request": { "subtype": "hook_callback", "callback_id": callback_id, "input": { "tool": "Write" }, "tool_use_id": "tool-1" } }));
                    }
                }
                Mode::Mcp => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                    }
                }
                Mode::Turns => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                    }
                }
                Mode::HangCallback => {
                    if subtype == "initialize" {
                        self.success(&id, json!({ "commands": [] }));
                    }
                }
            }
        } else if message.get("type").and_then(Value::as_str) == Some("user") {
            if matches!(self.mode, Mode::Cancel | Mode::HangCallback) {
                self.enqueue(json!({ "type": "control_request", "request_id": "permission-1", "request": { "subtype": "can_use_tool", "tool_name": "Write", "input": { "file": "answer.txt" }, "permission_suggestions": [], "tool_use_id": "tool-1" } }));
            } else if matches!(self.mode, Mode::Mcp) {
                self.enqueue(json!({ "type": "control_request", "request_id": "mcp-1", "request": { "subtype": "mcp_message", "server_name": "files", "message": { "jsonrpc": "2.0", "id": 1, "method": "tools/list" }, "vendor_field": { "trace": true } }, "vendor_envelope": "preserve-me" }));
            } else if matches!(self.mode, Mode::Turns) {
                self.enqueue(json!({ "type": "assistant", "session_id": "session", "message": { "role": "assistant", "model": "claude-sonnet", "content": [{ "type": "text", "text": "ok" }] } }));
                self.enqueue(json!({ "type": "result", "subtype": "success", "duration_ms": 1, "duration_api_ms": 1, "is_error": false, "num_turns": 1, "session_id": "session", "result": "ok" }));
            }
        }
        Ok(())
    }
    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        Ok(self.incoming.recv().await)
    }
    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed.store(true, Ordering::Release);
        Ok(())
    }
}
async fn wait_for_write<F>(writes: &Arc<Mutex<Vec<Value>>>, predicate: F) -> Value
where
    F: Fn(&Value) -> bool,
{
    for _ in 0..100 {
        if let Some(frame) = writes
            .lock()
            .await
            .iter()
            .find(|frame| predicate(frame))
            .cloned()
        {
            return frame;
        }
        sleep(Duration::from_millis(2)).await;
    }
    panic!("timed out waiting for scripted write");
}
#[tokio::test]
async fn concurrent_initialize_callers_share_one_handshake() {
    let (transport, _, writes, _) = ScriptTransport::new(Mode::Reorder);
    let client = ClaudeClient::with_transport(transport, ClaudeAgentOptions::default()).unwrap();
    let (first, second) = tokio::join!(client.initialize(), client.initialize());
    assert!(first.is_ok());
    assert!(second.is_ok());
    let writes = writes.lock().await;
    assert_eq!(
        writes
            .iter()
            .filter(|frame| frame["request"]["subtype"] == "initialize")
            .count(),
        1
    );
    client.close().await.unwrap();
}
#[tokio::test]
async fn concurrent_controls_correlate_out_of_order_responses_and_errors() {
    let (transport, _, _, _) = ScriptTransport::new(Mode::Reorder);
    let client = ClaudeClient::connect_with_transport(transport, ClaudeAgentOptions::default())
        .await
        .unwrap();
    let (first, second) = tokio::join!(
        client.control_command(json!({ "subtype": "first" }), Duration::from_secs(1)),
        client.control_command(json!({ "subtype": "second" }), Duration::from_secs(1)),
    );
    assert_eq!(first.unwrap()["subtype"], "first");
    assert_eq!(second.unwrap()["subtype"], "second");
    let error = client
        .control_command(json!({ "subtype": "error" }), Duration::from_secs(1))
        .await
        .unwrap_err();
    assert!(matches!(
        error,
        claude_agent_sdk::ClaudeSdkError::Control { .. }
    ));
    client.close().await.unwrap();
}
#[tokio::test]
async fn malformed_control_response_is_reported_to_message_consumer() {
    let (transport, incoming_tx, _, _) = ScriptTransport::new(Mode::Reorder);
    let client = ClaudeClient::connect_with_transport(transport, ClaudeAgentOptions::default())
        .await
        .unwrap();
    incoming_tx
        .send(json!({ "type": "control_response", "response": { "subtype": "success" } }))
        .unwrap();
    let error = client.next_message().await.unwrap_err();
    assert!(matches!(
        error,
        claude_agent_sdk::ClaudeSdkError::Control { .. }
    ));
    client.close().await.unwrap();
}
#[tokio::test]
async fn bounded_message_queue_stays_responsive_and_reports_overflow() {
    let (transport, _, _, _) = ScriptTransport::new(Mode::Burst);
    let options = ClaudeAgentOptions {
        initialize_timeout: Duration::from_secs(1),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    let response = client
        .control_command(json!({ "subtype": "ping" }), Duration::from_secs(1))
        .await
        .unwrap();
    assert_eq!(response["subtype"], "ping");
    let error = loop {
        match client.next_message().await {
            Err(error) => break error,
            Ok(Some(_)) => continue,
            Ok(None) => panic!("stream ended without reporting queue overflow"),
        }
    };
    assert!(error.to_string().contains("message queue overflowed"));
    assert!(client.close().await.is_ok());
}
struct DropProbe(Arc<AtomicBool>);
impl Drop for DropProbe {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Release);
    }
}
#[tokio::test]
async fn control_cancel_aborts_callback_and_does_not_write_a_reply() {
    let (transport, incoming_tx, writes, _) = ScriptTransport::new(Mode::Cancel);
    let started = Arc::new(Notify::new());
    let dropped = Arc::new(AtomicBool::new(false));
    let callback_started = Arc::clone(&started);
    let callback_dropped = Arc::clone(&dropped);
    let callback: PermissionCallback = Arc::new(move |_tool, _input, _context| {
        let callback_started = Arc::clone(&callback_started);
        let callback_dropped = Arc::clone(&callback_dropped);
        Box::pin(async move {
            let _probe = DropProbe(callback_dropped);
            callback_started.notify_one();
            sleep(Duration::from_secs(10)).await;
            Ok(PermissionResult::allow())
        })
    });
    let options = ClaudeAgentOptions {
        permission_callback: Some(callback),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    client.send_prompt("write a file").await.unwrap();
    timeout(Duration::from_secs(1), started.notified())
        .await
        .unwrap();
    incoming_tx
        .send(json!({ "type": "control_cancel_request", "request_id": "permission-1" }))
        .unwrap();
    timeout(Duration::from_secs(1), async {
        while !dropped.load(Ordering::Acquire) {
            sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
    let writes = writes.lock().await;
    assert!(!writes
        .iter()
        .any(|frame| frame["type"] == "control_response"));
    drop(writes);
    client.close().await.unwrap();
}
#[tokio::test]
async fn dropping_client_aborts_inflight_callback_and_releases_probe() {
    let (transport, _, _, _) = ScriptTransport::new(Mode::Cancel);
    let started = Arc::new(Notify::new());
    let dropped = Arc::new(AtomicBool::new(false));
    let callback_started = Arc::clone(&started);
    let callback_dropped = Arc::clone(&dropped);
    let callback: PermissionCallback = Arc::new(move |_tool, _input, _context| {
        let callback_started = Arc::clone(&callback_started);
        let callback_dropped = Arc::clone(&callback_dropped);
        Box::pin(async move {
            let _probe = DropProbe(callback_dropped);
            callback_started.notify_one();
            sleep(Duration::from_secs(10)).await;
            Ok(PermissionResult::allow())
        })
    });
    let options = ClaudeAgentOptions {
        permission_callback: Some(callback),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    client.send_prompt("write a file").await.unwrap();
    timeout(Duration::from_secs(1), started.notified())
        .await
        .unwrap();
    drop(client);
    timeout(Duration::from_secs(1), async {
        while !dropped.load(Ordering::Acquire) {
            sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
}
#[tokio::test]
async fn hanging_callback_response_send_is_bounded_and_closes_stream() {
    let (transport, _, writes, _) = ScriptTransport::new(Mode::HangCallback);
    let callback: PermissionCallback =
        Arc::new(|_tool, _input, _context| Box::pin(async { Ok(PermissionResult::allow()) }));
    let options = ClaudeAgentOptions {
        permission_callback: Some(callback),
        initialize_timeout: Duration::from_millis(20),
        shutdown_timeout: Duration::from_millis(100),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    client.send_prompt("write a file").await.unwrap();
    let _ = wait_for_write(&writes, |frame| {
        frame["type"] == "control_response" && frame["response"]["request_id"] == "permission-1"
    })
    .await;
    let error = timeout(Duration::from_secs(1), client.next_message())
        .await
        .unwrap()
        .unwrap_err();
    assert!(matches!(
        error,
        claude_agent_sdk::ClaudeSdkError::Timeout { .. }
            | claude_agent_sdk::ClaudeSdkError::Transport(_)
    ));
    client.close().await.unwrap();
}
#[tokio::test]
async fn permission_deny_preserves_message_and_wire_fields() {
    let (transport, _, writes, _) = ScriptTransport::new(Mode::Cancel);
    let callback: PermissionCallback = Arc::new(|_tool, _input, _context| {
        Box::pin(async move {
            assert_eq!(_context.control.request_id, "permission-1");
            assert_eq!(_context.control.raw["type"], "control_request");
            assert_eq!(_context.control.raw["request"]["subtype"], "can_use_tool");
            Ok(PermissionResult::deny("policy denied"))
        })
    });
    let options = ClaudeAgentOptions {
        permission_callback: Some(callback),
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    client.send_prompt("write a file").await.unwrap();
    let response = wait_for_write(&writes, |frame| {
        frame["type"] == "control_response" && frame["response"]["request_id"] == "permission-1"
    })
    .await;
    assert_eq!(response["response"]["subtype"], "success");
    assert_eq!(response["response"]["response"]["behavior"], "deny");
    assert_eq!(response["response"]["response"]["message"], "policy denied");
    assert!(response["response"]["response"].get("interrupt").is_none());
    client.close().await.unwrap();
}
#[tokio::test]
async fn hook_callback_uses_cli_field_names_and_mcp_wraps_json_rpc_response() {
    let (hook_transport, _, hook_writes, _) = ScriptTransport::new(Mode::Hook);
    let mut hook_options = ClaudeAgentOptions::default();
    hook_options.hooks.insert(
        "PreToolUse".into(),
        vec![HookMatcher {
            matcher: Some("Write".into()),
            hooks: vec![claude_agent_sdk::HookCallback::new(|_, _, _| async {
                let mut output = HookOutput {
                    continue_: Some(false),
                    ..HookOutput::default()
                };
                output.extra.insert("decision".into(), json!("deny"));
                Ok(output)
            })],
            timeout: None,
        }],
    );
    let hook_client = ClaudeClient::connect_with_transport(hook_transport, hook_options)
        .await
        .unwrap();
    let hook_response = wait_for_write(&hook_writes, |frame| {
        frame["type"] == "control_response" && frame["response"]["request_id"] == "hook-1"
    })
    .await;
    assert_eq!(hook_response["response"]["response"]["continue"], false);
    assert_eq!(hook_response["response"]["response"]["decision"], "deny");
    hook_client.close().await.unwrap();

    let (mcp_transport, _, mcp_writes, _) = ScriptTransport::new(Mode::Mcp);
    let mcp_options = ClaudeAgentOptions {
        mcp_callback_with_context: Some(Arc::new(|_server, _message, context| {
            Box::pin(async move {
                assert_eq!(context.request_id, "mcp-1");
                assert_eq!(context.raw["vendor_envelope"], "preserve-me");
                assert_eq!(context.raw["request"]["vendor_field"]["trace"], true);
                Ok(Some(
                    json!({ "jsonrpc": "2.0", "id": 1, "result": { "tools": [] } }),
                ))
            })
        })),
        ..ClaudeAgentOptions::default()
    };
    let mcp_client = ClaudeClient::connect_with_transport(mcp_transport, mcp_options)
        .await
        .unwrap();
    mcp_client.send_prompt("list tools").await.unwrap();
    let mcp_response = wait_for_write(&mcp_writes, |frame| {
        frame["type"] == "control_response" && frame["response"]["request_id"] == "mcp-1"
    })
    .await;
    assert_eq!(
        mcp_response["response"]["response"]["mcp_response"]["result"]["tools"],
        json!([])
    );
    mcp_client.close().await.unwrap();
}

#[tokio::test]
async fn result_frames_do_not_close_a_stateful_client_between_turns() {
    let (transport, _, _, _) = ScriptTransport::new(Mode::Turns);
    let client = ClaudeClient::connect_with_transport(transport, ClaudeAgentOptions::default())
        .await
        .unwrap();
    for prompt in ["first", "second"] {
        client.send_prompt(prompt).await.unwrap();
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
        assert!(!client.is_closed());
    }
    client.close().await.unwrap();
}
