use std::collections::HashMap;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::client::{ClientFrame, ClientHandle};

use super::super::checkout_buffer_guards_tests::fixture;
use super::super::ClientState;

fn events(receiver: &mut UnboundedReceiver<ClientFrame>) -> Vec<Value> {
    let mut events = Vec::new();
    while let Ok(frame) = receiver.try_recv() {
        let value = match frame {
            ClientFrame::Json(value) => value,
            ClientFrame::OrderedControl { frame, .. } => match *frame {
                ClientFrame::Json(value) => value,
                _ => continue,
            },
            _ => continue,
        };
        if value.get("event").is_some() {
            events.push(value);
        }
    }
    events
}

/// App 1 can save or discard, app 2 is an older desktop, client 3 is the CLI.
async fn acquire(resolution: Value) -> (Value, Vec<Value>, Vec<Value>) {
    let (_root, mut actor) = fixture().await;
    let mut receivers = HashMap::new();
    for (id, save) in [(1, true), (2, false)] {
        let (handle, receiver) = ClientHandle::test_channels();
        let mut client = ClientState::local(handle, true);
        client.checkout_buffer_save = save;
        actor.clients.insert(id, client);
        receivers.insert(id, receiver);
    }
    let status = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared", "resolution": resolution}),
        )
        .await
        .unwrap();
    let saving = events(receivers.get_mut(&1).unwrap());
    let older = events(receivers.get_mut(&2).unwrap());
    (status, saving, older)
}

#[tokio::test]
async fn save_asks_capable_apps_to_save_and_locks_the_others() {
    let (status, saving, older) = acquire(json!("save")).await;

    assert_eq!(status["pendingClients"], 2);
    assert_eq!(saving.len(), 1);
    assert_eq!(saving[0]["event"], "checkoutBuffersSaveRequested");
    assert_eq!(saving[0]["payload"]["guardId"], status["guardId"]);
    assert_eq!(
        saving[0]["payload"]["scope"]["tabIds"],
        json!(["task-editor"])
    );
    assert_eq!(older.len(), 1);
    assert_eq!(older[0]["event"], "checkoutBuffersLock");
    assert!(older[0]["payload"].get("resolution").is_none());
}

#[tokio::test]
async fn discard_rides_on_the_lock_for_capable_apps_only() {
    let (_, saving, older) = acquire(json!("discard")).await;

    assert_eq!(saving[0]["event"], "checkoutBuffersLock");
    assert_eq!(saving[0]["payload"]["resolution"], "discard");
    assert_eq!(older[0]["event"], "checkoutBuffersLock");
    assert!(older[0]["payload"].get("resolution").is_none());
}

#[tokio::test]
async fn a_guard_without_resolution_locks_as_before() {
    let (_, saving, older) = acquire(Value::Null).await;

    for events in [saving, older] {
        assert_eq!(events[0]["event"], "checkoutBuffersLock");
        assert!(events[0]["payload"].get("resolution").is_none());
    }
}

#[tokio::test]
async fn an_unknown_resolution_is_rejected() {
    let (_root, mut actor) = fixture().await;
    let error = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id": "task", "operation": "removeShared", "resolution": "ignore"}),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("save or discard"), "{error}");
    assert!(actor.checkout_buffer_guards.is_empty());
}
