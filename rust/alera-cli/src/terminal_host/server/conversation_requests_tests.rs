use std::collections::HashMap;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::ServerActor;
use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::session::Session;

const CLI: u64 = 1;
const PHONE: u64 = 2;
const WAITER: u64 = 3;

struct Fixture {
    _dir: tempfile::TempDir,
    actor: ServerActor,
    receivers: HashMap<u64, UnboundedReceiver<ClientFrame>>,
    next: i64,
}

async fn fixture() -> Fixture {
    let dir = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let mut receivers = HashMap::new();
    for id in [CLI, PHONE, WAITER] {
        let (handle, events) = ClientHandle::test_channels();
        let client = if id == PHONE {
            mobile_client(handle, "pixel")
        } else {
            local_client(handle)
        };
        clients.insert(id, client);
        receivers.insert(id, events);
    }
    let sessions = ["worker", "coord"]
        .into_iter()
        .map(|id| {
            let mut session = Session::driver_test_stub(id, 80, 24);
            session.workspace_id = "ws".into();
            (id.to_string(), session)
        })
        .collect();
    let mut actor = test_actor(&dir, clients, sessions).await;
    for handle in ["worker", "coord"] {
        actor
            .agent_presence
            .update(handle, "codex".into(), AgentPresenceState::Working);
    }
    Fixture {
        _dir: dir,
        actor,
        receivers,
        next: 0,
    }
}

impl Fixture {
    async fn send(&mut self, client: u64, request_type: &str, payload: Value) -> i64 {
        self.next += 1;
        let line = json!({"id": self.next, "type": request_type, "payload": payload}).to_string();
        self.actor.handle_line(client, line).await;
        self.next
    }

    fn response(&mut self, client: u64, id: i64) -> Option<Value> {
        let events = self.receivers.get_mut(&client).unwrap();
        while let Ok(frame) = events.try_recv() {
            let frame = frame.as_json().unwrap();
            if frame.get("id") == Some(&json!(id)) {
                return Some(frame);
            }
        }
        None
    }

    async fn ok(&mut self, client: u64, request_type: &str, payload: Value) -> Value {
        let id = self.send(client, request_type, payload).await;
        let response = self.response(client, id).expect("answered");
        assert_eq!(response["ok"], true, "{response}");
        response["payload"].clone()
    }
}

#[tokio::test]
async fn an_agent_can_ask_without_waiting_and_read_the_answer_later() {
    let mut fixture = fixture().await;
    let asked = fixture
        .ok(
            CLI,
            "orchestration.ask",
            json!({"from": "worker", "to": "coord", "question": "Which branch?", "wait": false}),
        )
        .await;
    let question_id = asked["questionId"].as_str().unwrap().to_string();
    assert_eq!(asked["to"], "coord");

    let wait_id = fixture
        .send(
            WAITER,
            "inbox.wait",
            json!({"questionId": question_id, "timeoutMs": 60000}),
        )
        .await;
    assert!(fixture.response(WAITER, wait_id).is_none());
    fixture
        .ok(
            CLI,
            "orchestration.reply",
            json!({"id": question_id, "body": "main"}),
        )
        .await;
    let woken = fixture
        .response(WAITER, wait_id)
        .expect("the reply woke it");
    assert_eq!(woken["payload"]["outcome"], "answered");
    assert_eq!(woken["payload"]["messages"][0]["body"], "main");
    // Reading it consumed the reply, so it is not pasted into the asker later.
    let pending = fixture
        .actor
        .runtime_store
        .undelivered_unread_orchestration_messages("worker")
        .await
        .unwrap();
    assert!(pending.is_empty());
}

#[tokio::test]
async fn conversations_are_visible_read_only_on_every_surface() {
    let mut fixture = fixture().await;
    fixture
        .ok(
            CLI,
            "orchestration.send",
            json!({"from": "coord", "to": "worker", "subject": "Plan", "body": "Start with the store"}),
        )
        .await;
    let listed = fixture.ok(PHONE, "inbox.conversations", json!({})).await;
    assert_eq!(listed["kind"], "conversations");
    let thread = &listed["items"][0];
    assert_eq!(thread["participants"], json!(["coord", "worker"]));
    let thread_id = thread["threadId"].as_str().unwrap().to_string();
    let detail = fixture
        .ok(PHONE, "inbox.conversation", json!({"threadId": thread_id}))
        .await;
    assert_eq!(detail["messages"][0]["body"], "Start with the store");
    let unread = fixture
        .actor
        .runtime_store
        .unread_orchestration_messages("worker", None)
        .await
        .unwrap();
    assert_eq!(
        unread.len(),
        1,
        "viewing must not consume the agent's message"
    );
    // WAITER made no requests, so nothing drained its event stream.
    let events = fixture.receivers.get_mut(&WAITER).unwrap();
    let mut saw_event = false;
    while let Ok(frame) = events.try_recv() {
        saw_event |= frame.as_json().unwrap()["event"] == "conversationsChanged";
    }
    assert!(saw_event);
}

#[tokio::test]
async fn waiting_on_a_follow_up_question_finds_its_reply_in_the_root_thread() {
    let mut fixture = fixture().await;
    let root = fixture
        .ok(
            CLI,
            "orchestration.ask",
            json!({"from": "worker", "to": "coord", "question": "Root?", "wait": false}),
        )
        .await;
    let root_id = root["questionId"].as_str().unwrap().to_string();
    let follow_up = fixture
        .ok(
            CLI,
            "orchestration.send",
            json!({"from": "worker", "to": "coord", "subject": "And?", "type": "decision_gate", "threadId": root_id}),
        )
        .await;
    let follow_up_id = follow_up["messages"][0]["id"].as_str().unwrap().to_string();
    fixture
        .ok(
            CLI,
            "orchestration.reply",
            json!({"id": root_id, "body": "Answer to the root"}),
        )
        .await;
    // The root's answer is not the follow-up's.
    let early = fixture
        .ok(
            WAITER,
            "inbox.wait",
            json!({"questionId": follow_up_id, "timeoutMs": 0}),
        )
        .await;
    assert_eq!(early["outcome"], "pending", "{early}");
    fixture
        .ok(
            CLI,
            "orchestration.reply",
            json!({"id": follow_up_id, "body": "Answer to the follow-up"}),
        )
        .await;
    let waited = fixture
        .ok(
            WAITER,
            "inbox.wait",
            json!({"questionId": follow_up_id, "timeoutMs": 0}),
        )
        .await;
    assert_eq!(waited["outcome"], "answered", "{waited}");
    assert_eq!(waited["messages"][0]["body"], "Answer to the follow-up");
    assert_eq!(waited["messages"].as_array().unwrap().len(), 1, "{waited}");
}
