use alera_agent_transport::{JsonTransport, TransportError};
use async_trait::async_trait;
use serde_json::Value;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct ScriptedTransport {
    incoming: Arc<Mutex<VecDeque<Value>>>,
    pub writes: Arc<Mutex<Vec<Value>>>,
}

impl ScriptedTransport {
    pub fn new(incoming: impl IntoIterator<Item = Value>) -> Self {
        Self {
            incoming: Arc::new(Mutex::new(incoming.into_iter().collect())),
            writes: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

#[async_trait]
impl JsonTransport for ScriptedTransport {
    async fn send(&mut self, value: Value) -> Result<(), TransportError> {
        self.writes.lock().unwrap().push(value);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        loop {
            if let Some(value) = self.incoming.lock().unwrap().pop_front() {
                return Ok(Some(value));
            }
            tokio::task::yield_now().await;
        }
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        Ok(())
    }
}

pub fn response(id: i64, result: Value) -> Value {
    serde_json::json!({"jsonrpc":"2.0","id":id,"result":result})
}

pub fn initialize_response() -> Value {
    initialize_response_with_grants([])
}

pub fn initialize_response_with_grants(
    granted_capabilities: impl IntoIterator<Item = &'static str>,
) -> Value {
    response(
        1,
        serde_json::json!({
            "experimentalApi": false,
            "grantedCapabilities": granted_capabilities.into_iter().collect::<Vec<_>>(),
            "sessionDurability": "durable"
        }),
    )
}

pub fn session_response(id: i64, session_id: &str) -> Value {
    response(
        id,
        serde_json::json!({
            "session": {
                "sessionId": session_id,
                "status": "idle",
                "activeTurnId": null,
                "modelId": "muse-default",
                "workspaceRoot": "/tmp"
            },
            "viewCursor": "v:1"
        }),
    )
}
