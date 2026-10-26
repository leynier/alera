//! Frames and transports shared by the `/goal` scenarios.

#![allow(dead_code)]

use std::sync::{Arc, Mutex};

use alera_provider_codex::{CodexProvider, CodexProviderConfig, JsonTransport, MockTransport};
use alera_provider_protocol::transport::TransportError;
use alera_provider_protocol::{EventKind, Provider, ProviderEvent, SessionStartInput};
use async_trait::async_trait;
use serde_json::{json, Value};
use tokio::sync::mpsc;

pub fn response(id: i64, result: Value) -> Value {
    json!({ "id": id, "result": result })
}

pub fn notification(method: &str, params: Value) -> Value {
    json!({ "method": method, "params": params })
}

pub fn goal(objective: &str, status: &str) -> Value {
    json!({
        "threadId": "native",
        "objective": objective,
        "status": status,
        "tokensUsed": 1200,
        "tokenBudget": null,
        "timeUsedSeconds": 90,
        "createdAt": 1,
        "updatedAt": 2,
    })
}

pub fn goal_response(id: i64, objective: &str, status: &str) -> Value {
    response(id, json!({ "goal": goal(objective, status) }))
}

pub fn goal_updated(objective: &str, status: &str) -> Value {
    notification(
        "thread/goal/updated",
        json!({ "threadId": "native", "goal": goal(objective, status) }),
    )
}

pub fn turn_started(turn: &str) -> Value {
    notification(
        "turn/started",
        json!({ "threadId": "native", "turn": { "id": turn, "status": "inProgress", "items": [] } }),
    )
}

pub fn turn_completed(turn: &str, status: &str) -> Value {
    notification(
        "turn/completed",
        json!({ "threadId": "native", "turn": { "id": turn, "status": status, "items": [] } }),
    )
}

pub fn agent_message(turn: &str, text: &str) -> Value {
    notification(
        "item/completed",
        json!({
            "threadId": "native",
            "turnId": turn,
            "item": { "id": format!("{turn}-answer"), "type": "agentMessage", "text": text },
        }),
    )
}

fn session_frames() -> [Value; 2] {
    [
        response(1, json!({ "codexHome": "/tmp/codex", "userAgent": "test" })),
        response(2, json!({ "thread": { "id": "native" } })),
    ]
}

/// A started session over [frames]; its commands update is consumed.
pub async fn mock_session(frames: impl IntoIterator<Item = Value>) -> CodexProvider<MockTransport> {
    let frames = session_frames().into_iter().chain(frames);
    let mut provider =
        CodexProvider::new(MockTransport::new(frames), CodexProviderConfig::default());
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    provider
}

/// The requests a provider wrote after its session started.
pub fn requests(writes: &[Value]) -> Vec<(String, Value)> {
    writes[3..]
        .iter()
        .map(|write| {
            (
                write["method"].as_str().unwrap_or_default().to_owned(),
                write["params"].clone(),
            )
        })
        .collect()
}

/// Every queued event until the stream ends.
pub async fn drain(provider: &mut impl Provider) -> Vec<ProviderEvent> {
    let mut events = Vec::new();
    while let Some(event) = provider.next_event().await.unwrap() {
        events.push(event);
    }
    events
}

/// A transport the test feeds while the provider runs, so a read can wait
/// out the goal's continuation window.
pub struct ChannelTransport {
    rx: mpsc::UnboundedReceiver<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
}

#[derive(Clone)]
pub struct ChannelFeed {
    tx: mpsc::UnboundedSender<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
}

impl ChannelFeed {
    pub fn push(&self, frame: Value) {
        self.tx.send(frame).unwrap();
    }

    pub fn requests(&self) -> Vec<(String, Value)> {
        requests(&self.writes.lock().unwrap())
    }
}

#[async_trait]
impl JsonTransport for ChannelTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        self.writes.lock().unwrap().push(message);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        Ok(self.rx.recv().await)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        Ok(())
    }
}

pub async fn channel_session() -> (CodexProvider<ChannelTransport>, ChannelFeed) {
    let (tx, rx) = mpsc::unbounded_channel();
    let writes = Arc::new(Mutex::new(Vec::new()));
    let feed = ChannelFeed {
        tx,
        writes: writes.clone(),
    };
    for frame in session_frames() {
        feed.push(frame);
    }
    let mut provider = CodexProvider::new(
        ChannelTransport { rx, writes },
        CodexProviderConfig::default(),
    );
    provider
        .start_session(SessionStartInput::new("app"))
        .await
        .unwrap();
    let commands = provider.next_event().await.unwrap().unwrap();
    assert_eq!(commands.kind, EventKind::SessionCommandsUpdated);
    (provider, feed)
}
