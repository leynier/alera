use async_trait::async_trait;
use claude_agent_sdk::{
    ClaudeAgentOptions, ClaudeClient, ClaudeSdkError, JsonTransport, RewindFilesResult,
    TransportError,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, Notify};

struct RewindTransport {
    incoming: mpsc::UnboundedReceiver<Value>,
    sender: mpsc::UnboundedSender<Value>,
    response: Option<Value>,
    writes: Arc<Mutex<Vec<Value>>>,
    rewind_sent: Arc<Notify>,
}

#[async_trait]
impl JsonTransport for RewindTransport {
    async fn send(&mut self, frame: Value) -> Result<(), TransportError> {
        self.writes.lock().unwrap().push(frame.clone());
        match frame["request"]["subtype"].as_str() {
            Some("initialize") => {
                self.sender
                    .send(response(&frame["request_id"], json!({})))
                    .unwrap();
            }
            Some("rewind_files") => {
                if let Some(body) = &self.response {
                    self.sender
                        .send(response(&frame["request_id"], body.clone()))
                        .unwrap();
                }
                self.rewind_sent.notify_one();
            }
            _ => {}
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

fn response(request_id: &Value, body: Value) -> Value {
    json!({"type":"control_response","response":{"subtype":"success","request_id":request_id,"response":body}})
}

async fn started(
    response_body: Option<Value>,
) -> (
    Arc<ClaudeClient>,
    mpsc::UnboundedSender<Value>,
    Arc<Mutex<Vec<Value>>>,
    Arc<Notify>,
) {
    let (sender, incoming) = mpsc::unbounded_channel();
    let writes = Arc::new(Mutex::new(Vec::new()));
    let rewind_sent = Arc::new(Notify::new());
    let transport = RewindTransport {
        incoming,
        sender: sender.clone(),
        response: response_body,
        writes: writes.clone(),
        rewind_sent: rewind_sent.clone(),
    };
    let client = ClaudeClient::connect_with_transport(transport, ClaudeAgentOptions::default())
        .await
        .unwrap();
    (Arc::new(client), sender, writes, rewind_sent)
}

#[tokio::test]
async fn native_control_response_retains_exact_typed_outcome_and_statistics() {
    let body = json!({"canRewind":true,"filesChanged":["src/example.rs"],"insertions":3,"deletions":7,"skippedLinks":1,"futureDetail":{"preserved":true}});
    let (client, _, writes, _) = started(Some(body.clone())).await;
    let result = client
        .rewind_files("12345678-1234-4234-8234-123456789abc")
        .await
        .unwrap();
    assert_eq!(result.can_rewind, Some(true));
    assert_eq!(result.files_changed, Some(vec!["src/example.rs".into()]));
    assert_eq!(
        (result.insertions, result.deletions, result.skipped_links),
        (Some(3), Some(7), Some(1))
    );
    assert_eq!(result.raw, body);
    assert_eq!(
        writes.lock().unwrap().last().unwrap()["request"],
        json!({"subtype":"rewind_files","user_message_id":"12345678-1234-4234-8234-123456789abc"})
    );
    client.close().await.unwrap();
}

#[tokio::test]
async fn empty_ack_and_native_refusal_never_become_successful_file_restoration() {
    for body in [
        json!({}),
        json!({"canRewind":false,"error":"No file checkpoint found for this message."}),
    ] {
        let (client, _, _, _) = started(Some(body.clone())).await;
        let result = client
            .rewind_files("12345678-1234-4234-8234-123456789abc")
            .await
            .unwrap();
        assert_ne!(result.can_rewind, Some(true));
        assert_eq!(
            result.error,
            body.get("error").and_then(Value::as_str).map(str::to_owned)
        );
        assert_eq!(result.raw, body);
        client.close().await.unwrap();
    }
}

#[test]
fn malformed_native_fields_are_rejected_without_defaulting_to_success() {
    for body in [
        json!({"canRewind":"true"}),
        json!({"filesChanged":[7]}),
        json!({"insertions":-1}),
        json!({"deletions":1.5}),
        json!(null),
    ] {
        assert!(matches!(
            RewindFilesResult::from_response(body),
            Err(ClaudeSdkError::JsonDecode(_))
        ));
    }
}

#[tokio::test]
async fn cancelling_rewind_wait_does_not_alias_late_acknowledgement_to_a_retry() {
    let (client, sender, writes, rewind_sent) = started(None).await;
    let first_client = client.clone();
    let first =
        tokio::spawn(async move { first_client.rewind_files("first-native-user-uuid").await });
    tokio::time::timeout(std::time::Duration::from_secs(2), rewind_sent.notified())
        .await
        .unwrap();
    let first_id = writes.lock().unwrap().last().unwrap()["request_id"].clone();
    first.abort();
    assert!(first.await.unwrap_err().is_cancelled());
    sender
        .send(response(
            &first_id,
            json!({"canRewind":true,"filesChanged":["old-operation-file"]}),
        ))
        .unwrap();
    let second_client = client.clone();
    let second =
        tokio::spawn(async move { second_client.rewind_files("second-native-user-uuid").await });
    tokio::time::timeout(std::time::Duration::from_secs(2), rewind_sent.notified())
        .await
        .unwrap();
    let second_id = writes.lock().unwrap().last().unwrap()["request_id"].clone();
    assert_ne!(first_id, second_id);
    sender
        .send(response(
            &second_id,
            json!({"canRewind":false,"error":"checkpoint unavailable"}),
        ))
        .unwrap();
    let result = second.await.unwrap().unwrap();
    assert_eq!(result.can_rewind, Some(false));
    assert_eq!(result.error.as_deref(), Some("checkpoint unavailable"));
    assert!(result.files_changed.is_none());
    client.close().await.unwrap();
}
