use crate::error::{MuseSdkError, Result};
use crate::types::MuseFrame;
use crate::wire;
use alera_agent_transport::JsonTransport;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::{timeout, Duration};

const MAX_ORPHANED_RESPONSES: usize = 128;

pub(crate) enum Command {
    Request {
        id: Value,
        frame: Value,
        response: oneshot::Sender<Result<Value>>,
    },
    Notify {
        frame: Value,
        done: oneshot::Sender<Result<()>>,
    },
    Reply {
        frame: Value,
        done: oneshot::Sender<Result<()>>,
    },
    Cancel(String),
    Close(oneshot::Sender<Result<()>>),
}

pub(crate) struct Inner {
    pub(crate) commands: mpsc::Sender<Command>,
    pub(crate) frames: Mutex<mpsc::Receiver<Result<MuseFrame>>>,
    pub(crate) next_request: AtomicU64,
    pub(crate) closed: AtomicBool,
    pub(crate) send_timeout: Duration,
    pub(crate) shutdown_timeout: Duration,
}

pub(crate) async fn run(
    inner: Arc<Inner>,
    mut transport: Box<dyn JsonTransport>,
    mut commands: mpsc::Receiver<Command>,
    frame_tx: mpsc::Sender<Result<MuseFrame>>,
) {
    let mut pending: HashMap<String, oneshot::Sender<Result<Value>>> = HashMap::new();
    let mut orphaned: HashMap<String, Value> = HashMap::new();
    loop {
        tokio::select! {
            biased;
            command = commands.recv() => {
                let Some(command) = command else { break; };
                if process_command(
                    command,
                    &mut transport,
                    &mut pending,
                    &mut orphaned,
                    inner.send_timeout,
                    inner.shutdown_timeout,
                )
                .await
                {
                    break;
                }
            }
            incoming = transport.recv() => {
                match incoming {
                    Ok(Some(frame)) => {
                        route_frame(frame, &mut pending, &mut orphaned, &frame_tx).await
                    }
                    Ok(None) => {
                        for (_, waiter) in pending.drain() { let _ = waiter.send(Err(MuseSdkError::Closed)); }
                        for (_, frame) in orphaned.drain() {
                            let _ = frame_tx.send(Ok(MuseFrame::Unknown(frame))).await;
                        }
                        break;
                    }
                    Err(error) => {
                        let message = error.to_string();
                        for (_, waiter) in pending.drain() {
                            let _ = waiter.send(Err(MuseSdkError::Protocol(message.clone())));
                        }
                        let _ = frame_tx.send(Err(MuseSdkError::Transport(error))).await;
                        break;
                    }
                }
            }
        }
    }
    for (_, waiter) in pending.drain() {
        let _ = waiter.send(Err(MuseSdkError::Closed));
    }
    for (_, frame) in orphaned.drain() {
        let _ = frame_tx.send(Ok(MuseFrame::Unknown(frame))).await;
    }
    inner.closed.store(true, Ordering::Release);
}

async fn process_command(
    command: Command,
    transport: &mut Box<dyn JsonTransport>,
    pending: &mut HashMap<String, oneshot::Sender<Result<Value>>>,
    orphaned: &mut HashMap<String, Value>,
    send_timeout: Duration,
    shutdown_timeout: Duration,
) -> bool {
    match command {
        Command::Request {
            id,
            frame,
            response,
        } => {
            let key = wire::id_key(&id);
            pending.insert(key.clone(), response);
            match timeout(send_timeout, transport.send(frame)).await {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    if let Some(waiter) = pending.remove(&key) {
                        let _ = waiter.send(Err(error.into()));
                    }
                    return true;
                }
                Err(_) => {
                    if let Some(waiter) = pending.remove(&key) {
                        let _ = waiter.send(Err(MuseSdkError::Timeout {
                            operation: "send".into(),
                        }));
                    }
                    return true;
                }
            }
            if orphaned.remove(&key).is_some_and(|frame| {
                settle_response(frame, pending, &key);
                true
            }) {
                return false;
            }
            false
        }
        Command::Notify { frame, done } => {
            let result = match timeout(send_timeout, transport.send(frame)).await {
                Ok(result) => result.map_err(MuseSdkError::from),
                Err(_) => Err(MuseSdkError::Timeout {
                    operation: "notify".into(),
                }),
            };
            let failed = result.is_err();
            let _ = done.send(result);
            failed
        }
        Command::Reply { frame, done } => {
            let result = match timeout(send_timeout, transport.send(frame)).await {
                Ok(result) => result.map_err(MuseSdkError::from),
                Err(_) => Err(MuseSdkError::Timeout {
                    operation: "reply".into(),
                }),
            };
            let failed = result.is_err();
            let _ = done.send(result);
            failed
        }
        Command::Cancel(key) => {
            pending.remove(&key);
            false
        }
        Command::Close(done) => {
            let result = match timeout(shutdown_timeout, transport.close()).await {
                Ok(result) => result.map_err(MuseSdkError::from),
                Err(_) => Err(MuseSdkError::Timeout {
                    operation: "close".into(),
                }),
            };
            for (_, waiter) in pending.drain() {
                let _ = waiter.send(Err(MuseSdkError::Closed));
            }
            let _ = done.send(result);
            true
        }
    }
}

async fn route_frame(
    frame: Value,
    pending: &mut HashMap<String, oneshot::Sender<Result<Value>>>,
    orphaned: &mut HashMap<String, Value>,
    frame_tx: &mpsc::Sender<Result<MuseFrame>>,
) {
    let Some(object) = frame.as_object() else {
        let _ = frame_tx.send(Ok(MuseFrame::Unknown(frame))).await;
        return;
    };
    if let Some(method) = object.get("method").and_then(Value::as_str) {
        let params = wire::frame_params(&frame);
        let message = if let Some(id) = wire::frame_id(&frame) {
            MuseFrame::ServerRequest {
                id,
                method: method.into(),
                params,
                raw: frame,
            }
        } else {
            MuseFrame::Notification {
                method: method.into(),
                params,
                raw: frame,
            }
        };
        let _ = frame_tx.send(Ok(message)).await;
        return;
    }
    if let Some(id) = wire::frame_id(&frame) {
        let key = wire::id_key(&id);
        if pending.contains_key(&key) {
            settle_response(frame, pending, &key);
            return;
        }
        if orphaned.len() >= MAX_ORPHANED_RESPONSES {
            if let Some(oldest) = orphaned.keys().next().cloned() {
                if let Some(frame) = orphaned.remove(&oldest) {
                    let _ = frame_tx.send(Ok(MuseFrame::Unknown(frame))).await;
                }
            }
        }
        orphaned.insert(key, frame);
        return;
    }
    let _ = frame_tx.send(Ok(MuseFrame::Unknown(frame))).await;
}

fn settle_response(
    frame: Value,
    pending: &mut HashMap<String, oneshot::Sender<Result<Value>>>,
    key: &str,
) {
    let Some(waiter) = pending.remove(key) else {
        return;
    };
    let Some(object) = frame.as_object() else {
        let _ = waiter.send(Err(MuseSdkError::Protocol(
            "response must be an object".into(),
        )));
        return;
    };
    if let Some(result) = object.get("result") {
        let _ = waiter.send(Ok(result.clone()));
    } else if let Some(error) = object.get("error") {
        let code = error.get("code").and_then(Value::as_i64).unwrap_or(-32603);
        let message = error
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("MSP request failed")
            .to_owned();
        let data = error.get("data").cloned();
        let _ = waiter.send(Err(MuseSdkError::Rpc {
            code,
            message,
            data,
        }));
    } else {
        let _ = waiter.send(Err(MuseSdkError::Protocol(
            "response must contain result or error".into(),
        )));
    }
}
