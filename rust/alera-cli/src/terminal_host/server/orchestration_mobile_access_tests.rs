use std::collections::HashMap;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::ServerActor;
use crate::terminal_host::client::{ClientFrame, ClientHandle};

const LOCAL: u64 = 1;
const PHONE: u64 = 2;
const RELAY: u64 = 3;
const ANONYMOUS: u64 = 4;

struct Fixture {
    _dir: tempfile::TempDir,
    actor: ServerActor,
    receivers: HashMap<u64, UnboundedReceiver<ClientFrame>>,
}

async fn fixture() -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let mut receivers = HashMap::new();
    for id in [LOCAL, PHONE, RELAY, ANONYMOUS] {
        let (handle, events) = ClientHandle::test_channels();
        let client = match id {
            LOCAL => local_client(handle),
            RELAY => {
                let mut client = mobile_client(handle, "relay");
                client.relay_client_id = Some("relay-client".to_string());
                client
            }
            ANONYMOUS => {
                let mut client = mobile_client(handle, "anonymous");
                client.authenticated = false;
                client
            }
            _ => mobile_client(handle, "phone"),
        };
        clients.insert(id, client);
        receivers.insert(id, events);
    }
    let actor = test_actor(&dir, clients, HashMap::new()).await;
    Fixture {
        _dir: dir,
        actor,
        receivers,
    }
}

impl Fixture {
    async fn request(&mut self, client: u64, request_type: &str, payload: Value) -> Value {
        let line = json!({"id": 7, "type": request_type, "payload": payload}).to_string();
        self.actor.handle_line(client, line).await;
        let events = self.receivers.get_mut(&client).unwrap();
        loop {
            let frame = events.try_recv().expect("the request was answered");
            let frame = frame.as_json().unwrap();
            if frame.get("id") == Some(&json!(7)) {
                return frame;
            }
        }
    }
}

#[tokio::test]
async fn orchestration_requests_follow_the_mobile_allowlist() {
    let mut fixture = fixture().await;
    let payload = json!({"terminal": "worker", "limit": 5});

    let local = fixture
        .request(LOCAL, "orchestration.inbox", payload.clone())
        .await;
    assert_eq!(local["ok"], true, "{local}");

    for client in [PHONE, RELAY] {
        let refused = fixture
            .request(client, "orchestration.inbox", payload.clone())
            .await;
        assert_eq!(refused["ok"], false, "{refused}");
        assert_eq!(
            refused["error"],
            "Mobile clients cannot call terminal host request: orchestration.inbox"
        );
    }

    let anonymous = fixture
        .request(ANONYMOUS, "orchestration.inbox", payload)
        .await;
    assert_eq!(anonymous["ok"], false, "{anonymous}");
    assert_eq!(
        anonymous["error"],
        "Terminal host client is not authenticated."
    );
}

#[tokio::test]
async fn mobile_clients_cannot_mutate_orchestration_state() {
    let mut fixture = fixture().await;
    fixture
        .request(
            LOCAL,
            "orchestration.send",
            json!({"from": "coordinator", "to": "worker", "subject": "Keep"}),
        )
        .await;

    let reset = fixture
        .request(PHONE, "orchestration.reset", json!({}))
        .await;
    assert_eq!(reset["ok"], false, "{reset}");

    let inbox = fixture
        .request(LOCAL, "orchestration.inbox", json!({"terminal": "worker"}))
        .await;
    assert_eq!(inbox["payload"]["items"].as_array().unwrap().len(), 1);
}
