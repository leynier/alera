use async_trait::async_trait;
use muse_agent_sdk::{JsonTransport, MuseClient, MuseClientOptions, MuseFrame};
use serde_json::Map;
use serde_json::Value;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct Scripted {
    incoming: Arc<Mutex<VecDeque<Value>>>,
    writes: Arc<Mutex<Vec<Value>>>,
}

impl Scripted {
    fn new(incoming: impl IntoIterator<Item = Value>) -> Self {
        Self {
            incoming: Arc::new(Mutex::new(incoming.into_iter().collect())),
            writes: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

#[async_trait]
impl JsonTransport for Scripted {
    async fn send(&mut self, value: Value) -> Result<(), alera_agent_transport::TransportError> {
        self.writes.lock().unwrap().push(value);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, alera_agent_transport::TransportError> {
        loop {
            if let Some(value) = self.incoming.lock().unwrap().pop_front() {
                return Ok(Some(value));
            }
            tokio::task::yield_now().await;
        }
    }

    async fn close(&mut self) -> Result<(), alera_agent_transport::TransportError> {
        Ok(())
    }
}

#[tokio::test]
async fn handshake_orders_initialize_before_initialized() {
    let transport = Scripted::new([serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "result": {"experimentalApi": false, "grantedCapabilities": []}
    })]);
    let writes = Arc::clone(&transport.writes);
    let client = MuseClient::connect_with_transport(transport, MuseClientOptions::default())
        .await
        .unwrap();
    {
        let writes = writes.lock().unwrap();
        assert_eq!(writes[0]["method"], "initialize");
        assert_eq!(writes[1]["method"], "initialized");
    }
    client.close().await.unwrap();
}

#[tokio::test]
async fn server_requests_are_retained_with_native_id() {
    let transport = Scripted::new([
        serde_json::json!({"jsonrpc":"2.0","id":1,"result":{}}),
        serde_json::json!({"jsonrpc":"2.0","id":22,"method":"approval/request","params":{"approvalId":"a1"}}),
    ]);
    let client = MuseClient::connect_with_transport(transport, MuseClientOptions::default())
        .await
        .unwrap();
    let frame = client.next_frame().await.unwrap().unwrap();
    match frame {
        MuseFrame::ServerRequest {
            id, method, params, ..
        } => {
            assert_eq!(id, serde_json::json!(22));
            assert_eq!(method, "approval/request");
            assert_eq!(params["approvalId"], "a1");
        }
        other => panic!("unexpected frame: {other:?}"),
    }
    client.close().await.unwrap();
}

#[tokio::test]
async fn command_replay_returns_ack_without_a_second_wire_request() {
    let transport = Scripted::new([
        serde_json::json!({"jsonrpc":"2.0","id":1,"result":{}}),
        serde_json::json!({
            "jsonrpc":"2.0","id":2,
            "result":{"commandId":"fixed-command","status":"accepted"}
        }),
    ]);
    let writes = Arc::clone(&transport.writes);
    let client = MuseClient::connect_with_transport(transport, MuseClientOptions::default())
        .await
        .unwrap();
    let mut params = Map::new();
    params.insert("sessionId".into(), Value::String("session-1".into()));
    client
        .command("session/read", params.clone(), Some("fixed-command".into()))
        .await
        .unwrap();
    client
        .command("session/read", params, Some("fixed-command".into()))
        .await
        .unwrap();
    let writes = writes.lock().unwrap().clone();
    assert_eq!(
        writes
            .iter()
            .filter(|frame| frame["method"] == "session/read")
            .count(),
        1
    );
    client.close().await.unwrap();
}
