use std::collections::HashMap;
use std::sync::Arc;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::json;
use tokio::sync::Mutex;

use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::emulator::EmulatorManager;
use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;

use super::super::actor_test_harness::{local_client, test_actor};
use super::super::emulator_request_payloads::PointerTransition;
use super::super::ServerCommand;
use super::ActivePointerState;

#[tokio::test]
async fn unauthenticated_disconnect_does_not_enqueue_emulator_cleanup() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    actor.clients.get_mut(&1).unwrap().authenticated = false;

    actor.dispose_client(1).await;

    assert_eq!(actor.emulator_requests.outstanding(), 0);
}

#[tokio::test]
async fn repeated_resume_park_requests_are_coalesced() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let guard = manager.lock().await;

    actor.queue_emulator_park_all();
    actor.queue_emulator_park_all();

    assert_eq!(actor.emulator_requests.outstanding(), 1);
    drop(guard);
}

#[tokio::test]
async fn resume_parks_before_starting_a_request_blocked_by_an_active_pointer() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    manager
        .lock()
        .await
        .insert_owned_android_session_for_shutdown_failure_test(
            "workspace",
            "emulator-tab",
            dir.path().join("missing-adb"),
        );
    actor.emulators = Some(manager);
    actor.emulator_requests.active_pointers.insert(
        "tab".into(),
        ActivePointerState {
            client_id: 1,
            generation: 1,
        },
    );
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.start_emulator_request(1, 7, "emulator.list".into(), json!({}));

    actor.queue_emulator_park_all();

    let first = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        &first,
        ServerCommand::EmulatorMaintenanceFinished(completion)
            if completion.changed_emulators == [("emulator-tab".into(), "workspace".into())]
    ));
    actor.handle(first).await;
    let changed = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(changed["event"], "mobileEmulatorChanged");
    assert_eq!(changed["payload"]["tabId"], "emulator-tab");
    assert_eq!(changed["payload"]["workspaceId"], "workspace");
    let second = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        second,
        ServerCommand::EmulatorRequestFinished { request_id: 7, .. }
    ));
}

#[tokio::test]
async fn resume_clears_a_pointer_from_an_in_flight_completion_before_advancing() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let manager_guard = manager.lock().await;
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.start_emulator_request(1, 1, "emulator.list".into(), json!({}));
    actor.queue_emulator_park_all();
    actor.start_emulator_request(1, 2, "emulator.list".into(), json!({}));
    drop(manager_guard);

    let first = inbox_receiver.recv().await.unwrap();
    let ServerCommand::EmulatorRequestFinished {
        client_id,
        request_id,
        mut completion,
    } = first
    else {
        panic!("the in-flight emulator request should finish first");
    };
    completion.pointer_transition = Some(PointerTransition::Began {
        tab_id: "tab".into(),
        client_id: 1,
    });
    actor
        .handle(ServerCommand::EmulatorRequestFinished {
            client_id,
            request_id,
            completion,
        })
        .await;
    assert!(actor.emulator_requests.active_pointers.contains_key("tab"));

    let maintenance = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        maintenance,
        ServerCommand::EmulatorMaintenanceFinished(_)
    ));
    actor.handle(maintenance).await;
    assert!(actor.emulator_requests.active_pointers.is_empty());
    let next = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        next,
        ServerCommand::EmulatorRequestFinished { request_id: 2, .. }
    ));
}

#[tokio::test]
async fn last_client_release_finishes_before_a_reconnected_client_acquires() {
    let dir = tempfile::tempdir().unwrap();
    let tab = emulator_tab("emulator-tab", "workspace");
    let (first_handle, _first_receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(first_handle))]),
        HashMap::new(),
    )
    .await;
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    manager
        .lock()
        .await
        .insert_owned_android_session_for_shutdown_failure_test(
            "workspace",
            "emulator-tab",
            dir.path().join("missing-adb"),
        );
    actor.emulators = Some(manager);
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor.dispose_client(1).await;
    let (second_handle, _second_receiver) = ClientHandle::test_channels();
    actor.clients.insert(2, local_client(second_handle));
    actor.start_emulator_request(
        2,
        8,
        "emulator.acquire".into(),
        json!({"tabId": "emulator-tab"}),
    );

    let first = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        first,
        ServerCommand::EmulatorMaintenanceFinished(_)
    ));
    actor.handle(first).await;
    let second = inbox_receiver.recv().await.unwrap();
    assert!(matches!(
        second,
        ServerCommand::EmulatorRequestFinished { request_id: 8, .. }
    ));
}

fn emulator_tab(tab_id: &str, workspace_id: &str) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: tab_id.to_string(),
        workspace_id: workspace_id.to_string(),
        kind: MOBILE_EMULATOR_TAB_KIND.to_string(),
        title: "Test Device".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "mobileEmulator": {
                "schemaVersion": 1,
                "platform": "android",
                "deviceId": "android:test-device",
            },
        }),
    }
}
