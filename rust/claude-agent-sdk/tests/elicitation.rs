use async_trait::async_trait;
use claude_agent_sdk::{
    ClaudeAgentOptions, ClaudeClient, ElicitationCallback, ElicitationRequest, ElicitationResult,
    JsonTransport, TransportError,
};
use serde_json::{json, Map, Value};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tokio::time::{sleep, timeout, Duration};

/// Answers initialize, then plays one elicitation request.
struct ElicitingTransport {
    incoming: mpsc::UnboundedReceiver<Value>,
    incoming_tx: mpsc::UnboundedSender<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
    elicitation: Value,
}

#[async_trait]
impl JsonTransport for ElicitingTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        self.writes.lock().await.push(message.clone());
        if message["type"] == "control_request" && message["request"]["subtype"] == "initialize" {
            let _ = self.incoming_tx.send(json!({
                "type": "control_response",
                "response": {"subtype": "success", "request_id": message["request_id"], "response": {}}
            }));
            let _ = self.incoming_tx.send(json!({
                "type": "control_request",
                "request_id": "elicit-1",
                "request": self.elicitation,
            }));
        }
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        Ok(self.incoming.recv().await)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        Ok(())
    }
}

fn form_request() -> Value {
    json!({
        "subtype": "elicitation", "mcp_server_name": "github", "message": "Who reviews?",
        "mode": "form", "elicitation_id": "e-1", "title": "Reviewer", "display_name": "GitHub",
        "requested_schema": {"type": "object", "properties": {"name": {"type": "string"}}},
    })
}

async fn reply(callback: Option<ElicitationCallback>, request: Value) -> Value {
    let (incoming_tx, incoming) = mpsc::unbounded_channel();
    let writes = Arc::new(Mutex::new(Vec::new()));
    let transport = ElicitingTransport {
        incoming,
        incoming_tx,
        writes: Arc::clone(&writes),
        elicitation: request,
    };
    let options = ClaudeAgentOptions {
        elicitation_callback: callback,
        ..ClaudeAgentOptions::default()
    };
    let client = ClaudeClient::connect_with_transport(transport, options)
        .await
        .unwrap();
    let response = timeout(Duration::from_secs(2), async {
        loop {
            if let Some(frame) = writes
                .lock()
                .await
                .iter()
                .find(|frame| frame["response"]["request_id"] == "elicit-1")
            {
                return frame.clone();
            }
            sleep(Duration::from_millis(2)).await;
        }
    })
    .await
    .unwrap();
    client.close().await.unwrap();
    response
}

#[tokio::test]
async fn an_elicitation_reaches_the_callback_and_its_answer_is_written() {
    let seen = Arc::new(Mutex::new(None::<ElicitationRequest>));
    let recorded = Arc::clone(&seen);
    let callback: ElicitationCallback = Arc::new(move |request| {
        let recorded = Arc::clone(&recorded);
        Box::pin(async move {
            *recorded.lock().await = Some(request);
            let mut content = Map::new();
            content.insert("name".into(), json!("x"));
            Ok(ElicitationResult::accept(Some(content)))
        })
    });
    let frame = reply(Some(callback), form_request()).await;
    assert_eq!(frame["type"], "control_response");
    assert_eq!(frame["response"]["subtype"], "success");
    assert_eq!(
        frame["response"]["response"],
        json!({"action": "accept", "content": {"name": "x"}})
    );
    let request = seen.lock().await.clone().unwrap();
    assert_eq!(request.server_name, "github");
    assert_eq!(request.mode.as_deref(), Some("form"));
    assert_eq!(request.elicitation_id.as_deref(), Some("e-1"));
    assert_eq!(request.display_name.as_deref(), Some("GitHub"));
    assert!(request.requested_schema.is_some());
    assert_eq!(request.control.request_id, "elicit-1");
}

#[tokio::test]
async fn without_a_callback_an_elicitation_is_declined() {
    let frame = reply(None, form_request()).await;
    assert_eq!(frame["response"]["subtype"], "success");
    assert_eq!(frame["response"]["response"], json!({"action": "decline"}));
}

#[tokio::test]
async fn decline_and_cancel_carry_no_content() {
    for result in [ElicitationResult::decline(), ElicitationResult::cancel()] {
        let expected = result.to_wire();
        let callback: ElicitationCallback = Arc::new(move |_| {
            let result = result.clone();
            Box::pin(async move { Ok(result) })
        });
        let frame = reply(Some(callback), form_request()).await;
        assert_eq!(frame["response"]["response"], expected);
        assert!(frame["response"]["response"].get("content").is_none());
    }
}
