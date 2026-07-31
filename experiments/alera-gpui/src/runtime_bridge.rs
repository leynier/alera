use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use alera_runtime_client::{
    RuntimeClientConnection, RuntimeClientEvent, RuntimeClientHandle, RuntimeClientOptions,
};
use async_channel::{Receiver, Sender};
use serde_json::Value;

const COMMAND_CAPACITY: usize = 64;
const EVENT_CAPACITY: usize = 256;
const RECONNECT_DELAY: Duration = Duration::from_secs(2);

#[derive(Clone, Debug)]
pub enum BridgeEvent {
    Connected,
    Unavailable,
    Notification { name: String, payload: Value },
    TerminalOutput { session_id: String, data: Vec<u8> },
    Disconnected { reason: String },
}

#[derive(Clone)]
pub struct RuntimeBridge {
    commands: Sender<BridgeCommand>,
    events: Receiver<BridgeEvent>,
}

enum BridgeCommand {
    Request {
        request_type: String,
        payload: Value,
        deadline: Duration,
        reply: Sender<Result<Value, String>>,
    },
    Close,
}

impl RuntimeBridge {
    pub fn start(runtime_dir: PathBuf) -> Self {
        let (command_tx, command_rx) = async_channel::bounded(COMMAND_CAPACITY);
        let (event_tx, event_rx) = async_channel::bounded(EVENT_CAPACITY);
        thread::Builder::new()
            .name("alera-gpui-runtime".to_string())
            .spawn(move || {
                let runtime = tokio::runtime::Runtime::new()
                    .expect("failed to create the GPUI runtime bridge");
                runtime.block_on(run_bridge(runtime_dir, command_rx, event_tx));
            })
            .expect("failed to start the GPUI runtime bridge thread");
        Self {
            commands: command_tx,
            events: event_rx,
        }
    }

    pub fn events(&self) -> Receiver<BridgeEvent> {
        self.events.clone()
    }

    pub async fn request(
        &self,
        request_type: impl Into<String>,
        payload: Value,
    ) -> Result<Value, String> {
        self.request_with_timeout(request_type, payload, Duration::from_secs(3))
            .await
    }

    pub async fn request_with_timeout(
        &self,
        request_type: impl Into<String>,
        payload: Value,
        deadline: Duration,
    ) -> Result<Value, String> {
        let (reply_tx, reply_rx) = async_channel::bounded(1);
        self.commands
            .send(BridgeCommand::Request {
                request_type: request_type.into(),
                payload,
                deadline,
                reply: reply_tx,
            })
            .await
            .map_err(|_| "Runtime bridge is closed.".to_string())?;
        reply_rx
            .recv()
            .await
            .map_err(|_| "Runtime bridge closed before replying.".to_string())?
    }
}

impl Drop for RuntimeBridge {
    fn drop(&mut self) {
        if self.commands.sender_count() == 1 {
            let _ = self.commands.try_send(BridgeCommand::Close);
        }
    }
}

async fn run_bridge(
    runtime_dir: PathBuf,
    commands: Receiver<BridgeCommand>,
    events: Sender<BridgeEvent>,
) {
    loop {
        let connection =
            RuntimeClientConnection::connect(&runtime_dir, RuntimeClientOptions::default()).await;
        match connection {
            Ok(Some(connection)) => {
                if events.send(BridgeEvent::Connected).await.is_err() {
                    return;
                }
                if !serve_connection(connection, &commands, &events).await {
                    return;
                }
            }
            Ok(None) => {
                if events.send(BridgeEvent::Unavailable).await.is_err() {
                    return;
                }
                if !wait_for_reconnect(&commands).await {
                    return;
                }
            }
            Err(error) => {
                if events
                    .send(BridgeEvent::Disconnected {
                        reason: error.to_string(),
                    })
                    .await
                    .is_err()
                {
                    return;
                }
                if !wait_for_reconnect(&commands).await {
                    return;
                }
            }
        }
    }
}

async fn serve_connection(
    mut connection: RuntimeClientConnection,
    commands: &Receiver<BridgeCommand>,
    events: &Sender<BridgeEvent>,
) -> bool {
    loop {
        tokio::select! {
            command = commands.recv() => {
                match command {
                    Ok(BridgeCommand::Request {
                        request_type,
                        payload,
                        deadline,
                        reply,
                    }) => {
                        dispatch_request(
                            connection.handle.clone(),
                            request_type,
                            payload,
                            deadline,
                            reply,
                        );
                    }
                    Ok(BridgeCommand::Close) | Err(_) => {
                        connection.handle.close().await;
                        return false;
                    }
                }
            }
            event = connection.events.recv() => {
                match event {
                    Some(RuntimeClientEvent::Notification { name, payload }) => {
                        if events.send(BridgeEvent::Notification { name, payload }).await.is_err() {
                            return false;
                        }
                    }
                    Some(RuntimeClientEvent::TerminalOutput { session_id, data }) => {
                        if events.send(BridgeEvent::TerminalOutput { session_id, data }).await.is_err() {
                            return false;
                        }
                    }
                    Some(RuntimeClientEvent::Disconnected { reason }) => {
                        let _ = events.send(BridgeEvent::Disconnected { reason }).await;
                        return true;
                    }
                    None => return true,
                }
            }
        }
    }
}

fn dispatch_request(
    handle: RuntimeClientHandle,
    request_type: String,
    payload: Value,
    deadline: Duration,
    reply: Sender<Result<Value, String>>,
) {
    tokio::spawn(async move {
        let result = handle
            .request_with_timeout(request_type, &payload, deadline)
            .await
            .map_err(|error| error.to_string());
        let _ = reply.send(result).await;
    });
}

async fn wait_for_reconnect(commands: &Receiver<BridgeCommand>) -> bool {
    tokio::select! {
        _ = tokio::time::sleep(RECONNECT_DELAY) => true,
        command = commands.recv() => {
            match command {
                Ok(BridgeCommand::Request { reply, .. }) => {
                    let _ = reply.send(Err("Alera Runtime Is Unavailable.".to_string())).await;
                    true
                }
                Ok(BridgeCommand::Close) | Err(_) => false,
            }
        }
    }
}
