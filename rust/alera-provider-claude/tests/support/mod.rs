#![allow(dead_code)]

use alera_agent_transport::{JsonTransport, TransportError};
use alera_provider_claude::{ClaudeProvider, ClaudeProviderConfig};
use alera_provider_protocol::{Provider, SessionStartInput};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub(crate) struct ScriptedTransportHandle {
    pub(crate) writes: Arc<Mutex<Vec<Value>>>,
}

pub(crate) struct ScriptedTransport {
    incoming: VecDeque<Value>,
    pub(crate) writes: Arc<Mutex<Vec<Value>>>,
    closed: bool,
    turn_started: bool,
    control_response_released: bool,
}

impl ScriptedTransport {
    pub(crate) fn new(
        incoming: impl IntoIterator<Item = Value>,
    ) -> (Self, ScriptedTransportHandle) {
        let writes = Arc::new(Mutex::new(Vec::new()));
        (
            Self {
                incoming: incoming.into_iter().collect(),
                writes: Arc::clone(&writes),
                closed: false,
                turn_started: false,
                control_response_released: false,
            },
            ScriptedTransportHandle { writes },
        )
    }
}

#[async_trait]
impl JsonTransport for ScriptedTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        if message["type"] == "user" {
            self.turn_started = true;
        }
        if message["type"] == "control_request" && message["request"]["subtype"] != "initialize" {
            self.control_response_released = true;
        }
        self.writes.lock().unwrap().push(message);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        loop {
            if !self.control_response_released
                && self
                    .incoming
                    .front()
                    .is_some_and(|frame| frame["type"] == "control_response")
                && self
                    .incoming
                    .front()
                    .is_some_and(|frame| frame["response"]["request_id"] != "req_1")
            {
                tokio::task::yield_now().await;
                continue;
            }
            if !self.turn_started
                && self
                    .incoming
                    .front()
                    .is_some_and(|frame| frame["type"] == "control_request")
            {
                tokio::task::yield_now().await;
                continue;
            }
            if let Some(frame) = self.incoming.pop_front() {
                return Ok(Some(frame));
            }
            if self.closed {
                return Ok(None);
            }
            tokio::task::yield_now().await;
        }
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed = true;
        Ok(())
    }
}

pub(crate) fn initialize_response() -> Value {
    json!({
        "type": "control_response",
        "response": {
            "subtype": "success",
            "request_id": "req_1",
            "response": {"session_id": "native-session"}
        }
    })
}

pub(crate) fn result_message(is_error: bool, terminal_reason: Option<&str>) -> Value {
    let mut result = json!({
        "type": "result",
        "subtype": if is_error { "error" } else { "success" },
        "session_id": "native-session",
        "is_error": is_error,
        "num_turns": 1,
        "usage": {"input_tokens": 2, "output_tokens": 3},
        "opaque_sentinel": {"kept": true},
        "result": if is_error { "failed" } else { "done" }
    });
    if let Some(reason) = terminal_reason {
        result["terminal_reason"] = Value::String(reason.into());
    }
    result
}

pub(crate) fn result_message_with_usage(usage: Value) -> Value {
    json!({
        "type": "result",
        "subtype": "success",
        "session_id": "native-session",
        "is_error": false,
        "num_turns": 1,
        "usage": usage,
        "result": "done"
    })
}

pub(crate) async fn started_provider(
    incoming: impl IntoIterator<Item = Value>,
) -> (ClaudeProvider, ScriptedTransportHandle) {
    let (transport, handle) = ScriptedTransport::new(incoming);
    let mut provider =
        ClaudeProvider::with_transport(transport, ClaudeProviderConfig::default()).unwrap();
    provider.initialize().await.unwrap();
    provider
        .start_session(SessionStartInput::new("app-thread"))
        .await
        .unwrap();
    (provider, handle)
}
