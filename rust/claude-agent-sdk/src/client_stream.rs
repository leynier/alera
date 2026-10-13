use super::{ClientInner, TransportCommand};
use crate::control::{
    control_subtype, error_control_response, hook_callback_from_map, hook_response,
    permission_context, permission_response, response_result, success_control_response,
};
use crate::error::{ClaudeSdkError, Result};
use crate::message::Message;
use crate::types::ControlRequestContext;
use alera_agent_transport::JsonTransport;
use serde_json::{Map, Value};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{timeout, timeout_at, Duration, Instant};

pub(super) async fn transport_loop(
    inner: Arc<ClientInner>,
    mut transport: Box<dyn JsonTransport>,
    mut commands: mpsc::Receiver<TransportCommand>,
    shutdown_timeout: Duration,
    transport_timeout: Duration,
) {
    let mut transport_closed = false;
    let mut terminal_error = ClaudeSdkError::Closed;
    loop {
        tokio::select! {
            biased;
            command = commands.recv() => match command {
                Some(TransportCommand::Send(frame, sender)) => {
                    let result = match timeout(transport_timeout, transport.send(frame)).await {
                        Ok(result) => result
                            .map_err(|error| ClaudeSdkError::transport(error.to_string())),
                        Err(_) => Err(ClaudeSdkError::Timeout {
                            operation: "transport send".into(),
                            timeout_ms: transport_timeout.as_millis() as u64,
                        }),
                    };
                    if let Err(error) = &result { terminal_error = error.clone(); }
                    let failed = result.is_err();
                    let _ = sender.send(result);
                    if failed {
                        let _ = send_message(&inner, Err(terminal_error.clone())).await;
                        break;
                    }
                }
                Some(TransportCommand::Close(sender)) => {
                    let result = close_transport(&mut transport, shutdown_timeout).await;
                    let _ = sender.send(result);
                    transport_closed = true;
                    break;
                }
                None => break,
            },
            next = transport.recv() => match next {
                Ok(Some(frame)) => {
                    if let Err(error) = route_frame(&inner, frame).await {
                        terminal_error = error;
                        break;
                    }
                }
                Ok(None) => break,
                Err(error) => {
                    let error = ClaudeSdkError::transport(error.to_string());
                    terminal_error = error.clone();
                    let _ = send_message(&inner, Err(error)).await;
                    break;
                }
            },
        }
    }
    if !transport_closed {
        let _ = close_transport(&mut transport, shutdown_timeout).await;
    }
    inner.closed.store(true, Ordering::Release);
    close_message_stream(&inner).await;
    abort_inflight_callbacks(&inner).await;
    fail_pending(&inner, terminal_error).await;
}

async fn route_frame(inner: &Arc<ClientInner>, frame: Value) -> Result<()> {
    match frame.get("type").and_then(Value::as_str) {
        Some("control_response") => {
            let response = frame.get("response").cloned().unwrap_or(Value::Null);
            let Some(request_id) = response.get("request_id").and_then(Value::as_str) else {
                let error = ClaudeSdkError::Control {
                    subtype: "response".into(),
                    message: "control response is missing request_id".into(),
                };
                let _ = send_message(inner, Err(error.clone())).await;
                return Err(error);
            };
            if let Some(sender) = inner.pending.lock().await.remove(request_id) {
                let _ = sender.send(response_result(&frame));
            }
            Ok(())
        }
        Some("control_request") => spawn_control_handler(inner, frame).await,
        Some("control_cancel_request") => {
            let Some(request_id) = frame.get("request_id").and_then(Value::as_str) else {
                let error = ClaudeSdkError::Control {
                    subtype: "cancel".into(),
                    message: "control cancellation is missing request_id".into(),
                };
                let _ = send_message(inner, Err(error.clone())).await;
                return Err(error);
            };
            if let Some(task) = inner.inflight_callbacks.lock().await.remove(request_id) {
                task.abort();
            }
            Ok(())
        }
        _ => {
            if send_message(inner, Ok(Message::from_value(frame))).await {
                Ok(())
            } else {
                Err(ClaudeSdkError::Transport(
                    "message queue overflowed or was closed".into(),
                ))
            }
        }
    }
}

async fn spawn_control_handler(inner: &Arc<ClientInner>, frame: Value) -> Result<()> {
    let Some(request_id) = frame
        .get("request_id")
        .and_then(Value::as_str)
        .map(str::to_owned)
    else {
        let error = ClaudeSdkError::Control {
            subtype: "request".into(),
            message: "control request is missing request_id".into(),
        };
        let _ = send_message(inner, Err(error.clone())).await;
        return Err(error);
    };
    let request = frame.get("request").cloned().unwrap_or(Value::Null);
    let child = Arc::downgrade(inner);
    let task_id = request_id.clone();
    let callback_request_id = request_id.clone();
    let task = tokio::spawn(async move {
        let Some(inner) = child.upgrade() else {
            return;
        };
        let response = handle_control_request(&inner, &frame, &callback_request_id, &request).await;
        let frame = match response {
            Ok(value) => success_control_response(&task_id, value),
            Err(error) => error_control_response(&task_id, error.to_string()),
        };
        let _ = send_inner_frame(&inner, frame).await;
        inner.inflight_callbacks.lock().await.remove(&task_id);
    });
    inner
        .inflight_callbacks
        .lock()
        .await
        .insert(request_id, task);
    Ok(())
}

async fn handle_control_request(
    inner: &Arc<ClientInner>,
    envelope: &Value,
    request_id: &str,
    request: &Value,
) -> Result<Value> {
    match control_subtype(request) {
        "can_use_tool" => {
            let callback = inner.permission_callback.clone().ok_or_else(|| {
                ClaudeSdkError::Callback("permission callback is not configured".into())
            })?;
            let tool_name = request
                .get("tool_name")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let input = request
                .get("input")
                .cloned()
                .unwrap_or(Value::Object(Map::new()));
            let result = callback(
                tool_name,
                input,
                permission_context(request_id, envelope, request),
            )
            .await?;
            Ok(permission_response(request, &result))
        }
        "hook_callback" => {
            let callback_id = request
                .get("callback_id")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let callback = {
                let callbacks = inner.hook_callbacks.lock().await;
                hook_callback_from_map(&callbacks, callback_id)?.clone()
            };
            let output = (callback.callback)(
                request.get("input").cloned().unwrap_or(Value::Null),
                request
                    .get("tool_use_id")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                serde_json::json!({ "signal": null, "controlRequest": envelope }),
            )
            .await?;
            Ok(hook_response(output))
        }
        "mcp_message" => {
            if inner.mcp_callback.is_none() && inner.mcp_callback_with_context.is_none() {
                return Err(ClaudeSdkError::Callback(
                    "MCP callback is not configured".into(),
                ));
            }
            let callback = inner.mcp_callback.clone();
            let server = request
                .get("server_name")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let message = request.get("message").cloned().unwrap_or(Value::Null);
            let response = if let Some(callback) = &inner.mcp_callback_with_context {
                callback(
                    server,
                    message,
                    ControlRequestContext::from_envelope(request_id, envelope),
                )
                .await?
            } else {
                callback.expect("MCP callback presence checked above")(server, message).await?
            }
            .unwrap_or_else(|| serde_json::json!({ "jsonrpc": "2.0", "result": {} }));
            Ok(serde_json::json!({ "mcp_response": response }))
        }
        subtype => Err(ClaudeSdkError::Unsupported(format!(
            "incoming control request subtype {subtype}"
        ))),
    }
}

async fn send_inner_frame(inner: &Arc<ClientInner>, frame: Value) -> Result<()> {
    if inner.closed.load(Ordering::Acquire) {
        return Err(ClaudeSdkError::Closed);
    }
    let (sender, receiver) = oneshot::channel();
    let deadline = Instant::now() + inner.transport_timeout;
    timeout_at(
        deadline,
        inner
            .transport_commands
            .send(TransportCommand::Send(frame, sender)),
    )
    .await
    .map_err(|_| ClaudeSdkError::Timeout {
        operation: "queueing control response".into(),
        timeout_ms: inner.transport_timeout.as_millis() as u64,
    })?
    .map_err(|_| ClaudeSdkError::Closed)?;
    timeout_at(deadline, receiver)
        .await
        .map_err(|_| ClaudeSdkError::Timeout {
            operation: "sending control response".into(),
            timeout_ms: inner.transport_timeout.as_millis() as u64,
        })?
        .map_err(|_| ClaudeSdkError::Closed)?
}

async fn fail_pending(inner: &Arc<ClientInner>, error: ClaudeSdkError) {
    for (_, sender) in inner.pending.lock().await.drain() {
        let _ = sender.send(Err(error.clone()));
    }
}

async fn send_message(inner: &Arc<ClientInner>, message: Result<Message>) -> bool {
    if let Some(sender) = inner.message_tx.lock().await.as_ref().cloned() {
        match sender.try_send(message) {
            Ok(()) => true,
            Err(mpsc::error::TrySendError::Full(_)) => {
                inner.message_overflowed.store(true, Ordering::Release);
                false
            }
            Err(mpsc::error::TrySendError::Closed(_)) => false,
        }
    } else {
        false
    }
}

async fn close_message_stream(inner: &Arc<ClientInner>) {
    inner.message_tx.lock().await.take();
}

async fn abort_inflight_callbacks(inner: &Arc<ClientInner>) {
    let tasks = inner
        .inflight_callbacks
        .lock()
        .await
        .drain()
        .map(|(_, task)| task)
        .collect::<Vec<_>>();
    for task in tasks {
        task.abort();
    }
    inner.hook_callbacks.lock().await.clear();
}

async fn close_transport(
    transport: &mut Box<dyn JsonTransport>,
    shutdown_timeout: Duration,
) -> Result<()> {
    match timeout(shutdown_timeout, transport.close()).await {
        Err(_) => Err(ClaudeSdkError::Timeout {
            operation: "transport close".into(),
            timeout_ms: shutdown_timeout.as_millis() as u64,
        }),
        Ok(Err(error)) => Err(ClaudeSdkError::transport(error.to_string())),
        Ok(Ok(())) => Ok(()),
    }
}
