use std::collections::HashMap;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::client_delivery::LocalClientRole;
use super::ServerActor;
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::session::Session;

pub(super) const CLI: u64 = 1;
pub(super) const DESKTOP: u64 = 2;
pub(super) const PHONE: u64 = 3;

pub(super) struct Fixture {
    _dir: tempfile::TempDir,
    pub(super) actor: ServerActor,
    receivers: HashMap<u64, UnboundedReceiver<ClientFrame>>,
    next_request: i64,
}

fn session(id: &str, workspace: &str) -> (String, Session) {
    let mut session = Session::driver_test_stub(id, 80, 24);
    session.workspace_id = workspace.to_string();
    session.tab_id = format!("tab-{id}");
    (id.to_string(), session)
}

pub(super) async fn fixture() -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let mut receivers = HashMap::new();
    for id in [CLI, DESKTOP, PHONE] {
        let (handle, events) = ClientHandle::test_channels();
        let client = match id {
            PHONE => mobile_client(handle, "pixel"),
            DESKTOP => {
                let mut client = local_client(handle);
                client.local_role = LocalClientRole::App;
                client
            }
            _ => local_client(handle),
        };
        clients.insert(id, client);
        receivers.insert(id, events);
    }
    let sessions = HashMap::from([
        session("claude-term", "ws-1"),
        session("codex-term", "ws-1"),
        session("shell-term", "ws-1"),
        session("lonely-term", "ws-2"),
    ]);
    let mut actor = test_actor(&dir, clients, sessions).await;
    // Working agents keep questions queued, so these tests never paste.
    for (handle, agent) in [
        ("claude-term", "claude"),
        ("codex-term", "codex"),
        ("lonely-term", "codex"),
    ] {
        actor
            .agent_presence
            .update(handle, agent.to_string(), AgentPresenceState::Working);
    }
    Fixture {
        _dir: dir,
        actor,
        receivers,
        next_request: 100,
    }
}

impl Fixture {
    pub(super) async fn send(&mut self, client: u64, request_type: &str, payload: Value) -> i64 {
        self.next_request += 1;
        let id = self.next_request;
        let line = json!({"id": id, "type": request_type, "payload": payload}).to_string();
        self.actor.handle_line(client, line).await;
        id
    }

    pub(super) fn take_response(&mut self, client: u64, id: i64) -> Option<Value> {
        let events = self.receivers.get_mut(&client).unwrap();
        while let Ok(frame) = events.try_recv() {
            let frame = frame.as_json().unwrap();
            if frame.get("id") == Some(&json!(id)) {
                return Some(frame);
            }
        }
        None
    }

    pub(super) async fn request(
        &mut self,
        client: u64,
        request_type: &str,
        payload: Value,
    ) -> Value {
        let id = self.send(client, request_type, payload).await;
        self.take_response(client, id)
            .expect("the request was answered")
    }

    pub(super) async fn ok(&mut self, client: u64, request_type: &str, payload: Value) -> Value {
        let response = self.request(client, request_type, payload).await;
        assert_eq!(response["ok"], true, "{response}");
        response["payload"].clone()
    }

    pub(super) fn events_named(&mut self, client: u64, name: &str) -> usize {
        let events = self.receivers.get_mut(&client).unwrap();
        let mut count = 0;
        while let Ok(frame) = events.try_recv() {
            if frame.as_json().unwrap()["event"] == name {
                count += 1;
            }
        }
        count
    }

    pub(super) async fn reply(&mut self, question_id: &str, body: &str) -> Value {
        self.ok(
            CLI,
            "orchestration.reply",
            json!({"id": question_id, "body": body}),
        )
        .await
    }
}
