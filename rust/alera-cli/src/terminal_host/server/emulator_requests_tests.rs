use std::collections::HashMap;

use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, test_actor};
use crate::terminal_host::server::ServerCommand;

#[test]
fn cli_gesture_shape_becomes_begin_and_end_points() {
    let points = gesture_points(&json!({
        "from": {"x": 0.1, "y": 0.2},
        "to": {"x": 0.8, "y": 0.9},
    }))
    .unwrap();
    assert_eq!(points.len(), 2);
    assert_eq!(points[0].kind.as_deref(), Some("begin"));
    assert_eq!(points[1].kind.as_deref(), Some("end"));
}

#[test]
fn gestures_require_a_bounded_begin_move_end_sequence() {
    assert!(gesture_points(&json!({
        "points": [{"type": "begin", "x": 0.1, "y": 0.1}]
    }))
    .is_err());
    assert!(gesture_points(&json!({
        "points": [
            {"type": "begin", "x": 0.1, "y": 0.1},
            {"type": "begin", "x": 0.2, "y": 0.2}
        ]
    }))
    .is_err());
    assert!(gesture_points(&json!({
        "points": (0..129)
            .map(|index| json!({"x": index as f64 / 128.0, "y": 0.5}))
            .collect::<Vec<_>>()
    }))
    .is_err());
}

#[test]
fn emulator_text_preserves_whitespace_and_rejects_only_empty_or_oversized_input() {
    assert_eq!(required_text(&json!({"text": " \n"})).unwrap(), " \n");
    assert!(required_text(&json!({"text": ""})).is_err());
    assert!(required_text(&json!({"text": "x".repeat(16 * 1024 + 1)})).is_err());
}

#[test]
fn logcat_filters_are_bounded_from_the_tail() {
    let value = "A one\nB two\nA three\nA four";
    let lines = filter_logcat(value, Some("A"), 2);
    assert_eq!(lines, ["A three", "A four"]);
}

#[test]
fn logcat_request_validates_and_converts_native_filters() {
    let request = logcat_request(&json!({
        "maxLines": 25,
        "tags": ["Alera"],
        "level": "warn",
        "contains": "failure",
        "since": "2026-07-27T12:00:00Z",
    }))
    .unwrap();

    assert_eq!(request.max_lines, 25);
    assert_eq!(request.tags, ["Alera"]);
    assert_eq!(request.level.as_deref(), Some("warn"));
    assert_eq!(request.contains.as_deref(), Some("failure"));
    assert_eq!(request.since_epoch.as_deref(), Some("1785153600.000"));
    assert!(logcat_request(&json!({"level": "trace"})).is_err());
    assert!(logcat_request(&json!({"since": "yesterday"})).is_err());
    assert!(logcat_request(&json!({"maxLines": 1001})).is_err());
}

#[tokio::test]
async fn busy_emulator_work_does_not_block_the_server_actor() {
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

    tokio::time::timeout(
        std::time::Duration::from_millis(100),
        actor.handle_line(
            1,
            json!({
                "id": 7,
                "type": "emulator.capabilities",
                "payload": {},
            })
            .to_string(),
        ),
    )
    .await
    .expect("dispatch should return while the emulator manager is busy");

    assert_eq!(actor.emulator_requests.outstanding(), 1);
    drop(guard);
}

#[tokio::test]
async fn closing_a_tab_does_not_wait_for_busy_emulator_work() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let guard = manager.lock().await;

    tokio::time::timeout(
        std::time::Duration::from_millis(100),
        actor.terminate_sessions_for_tab("emulator-tab"),
    )
    .await
    .expect("tab cleanup should be deferred while the emulator manager is busy");

    drop(guard);
}

#[tokio::test]
async fn emulator_requests_start_in_fifo_order() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    let guard = manager.lock().await;

    for request_id in [10, 11] {
        actor
            .handle_line(
                1,
                json!({"id": request_id, "type": "emulator.list", "payload": {}}).to_string(),
            )
            .await;
    }
    assert_eq!(actor.emulator_requests.outstanding(), 2);
    drop(guard);

    for request_id in [10, 11] {
        let command = tokio::time::timeout(std::time::Duration::from_secs(1), inbox_rx.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            &command,
            ServerCommand::EmulatorRequestFinished {
                request_id: completed,
                ..
            } if *completed == request_id
        ));
        actor.handle(command).await;
        assert_eq!(
            receiver.recv().await.unwrap().as_json().unwrap()["id"],
            request_id,
        );
    }
}

#[tokio::test]
async fn queued_pointer_moves_coalesce_without_losing_the_latest_request() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let guard = manager.lock().await;
    actor
        .handle_line(
            1,
            json!({"id": 20, "type": "emulator.list", "payload": {}}).to_string(),
        )
        .await;
    for (request_id, x) in [(21, 0.1), (22, 0.9)] {
        actor
            .handle_line(
                1,
                json!({
                    "id": request_id,
                    "type": "emulator.pointer",
                    "payload": {
                        "tabId": "tab",
                        "interactive": true,
                        "type": "move",
                        "x": x,
                        "y": 0.5,
                    },
                })
                .to_string(),
            )
            .await;
    }

    let coalesced = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(coalesced["id"], 21);
    assert_eq!(coalesced["payload"]["coalesced"], true);
    assert_eq!(actor.emulator_requests.outstanding(), 2);

    actor.cancel_queued_emulator_requests(1);
    assert_eq!(actor.emulator_requests.outstanding(), 1);
    drop(guard);
}

#[tokio::test]
async fn pointer_end_runs_before_queued_noninteractive_work() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.handle_emulator_request_finished(
        1,
        1,
        EmulatorRequestCompletion {
            response: json!({"ok": true}),
            broadcast: None,
            pointer_transition: Some(PointerTransition::Began {
                tab_id: "tab".into(),
                client_id: 1,
            }),
        },
    );
    let _ = receiver.recv().await;
    actor.start_emulator_request(1, 2, "emulator.list".into(), json!({}));
    actor.start_emulator_request(
        1,
        3,
        "emulator.pointer".into(),
        json!({
            "tabId": "tab",
            "interactive": true,
            "type": "end",
            "x": 0.5,
            "y": 0.5,
        }),
    );

    let command = inbox_rx.recv().await.unwrap();

    assert!(matches!(
        command,
        ServerCommand::EmulatorRequestFinished { request_id: 3, .. }
    ));
}

#[tokio::test]
async fn pointer_watchdog_unblocks_queued_work() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.handle_emulator_request_finished(
        1,
        1,
        EmulatorRequestCompletion {
            response: json!({"ok": true}),
            broadcast: None,
            pointer_transition: Some(PointerTransition::Began {
                tab_id: "tab".into(),
                client_id: 1,
            }),
        },
    );
    let _ = receiver.recv().await;
    actor.start_emulator_request(1, 2, "emulator.list".into(), json!({}));
    let pointer = actor.emulator_requests.active_pointers["tab"];

    actor.handle_emulator_pointer_timeout("tab", 1, pointer.generation);

    let command = inbox_rx.recv().await.unwrap();
    assert!(matches!(
        command,
        ServerCommand::EmulatorMaintenanceFinished(_)
    ));
    actor.handle(command).await;
    let command = inbox_rx.recv().await.unwrap();
    assert!(matches!(
        command,
        ServerCommand::EmulatorRequestFinished { request_id: 2, .. }
    ));
    assert!(actor.emulator_requests.active_pointers.is_empty());
}

#[tokio::test]
async fn emulator_request_queue_has_an_explicit_upper_bound() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let guard = manager.lock().await;

    for request_id in 0..=256 {
        actor.start_emulator_request(1, request_id, "emulator.list".into(), json!({}));
    }

    assert_eq!(actor.emulator_requests.outstanding(), 256);
    let busy = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(busy["id"], 256);
    assert_eq!(busy["payload"]["error"]["code"], "emulator_busy");
    actor.cancel_queued_emulator_requests(1);
    drop(guard);
}

#[tokio::test]
async fn deferred_emulator_work_writes_exactly_one_later_response() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_line(
            1,
            json!({
                "id": 8,
                "type": "emulator.capabilities",
                "payload": {},
            })
            .to_string(),
        )
        .await;

    assert!(receiver.try_recv().is_err());
    let command = tokio::time::timeout(std::time::Duration::from_secs(1), inbox_rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        &command,
        ServerCommand::EmulatorRequestFinished { .. }
    ));
    actor.handle(command).await;
    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 8);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["kind"], "emulatorCapabilities");
    assert!(receiver.try_recv().is_err());
}

#[tokio::test]
async fn emulator_messages_without_request_ids_do_not_start_jobs_or_respond() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = ClientHandle::test_channels();
    let mut client = local_client(handle);
    client.authenticated = false;
    let mut actor = test_actor(&dir, HashMap::from([(1, client)]), HashMap::new()).await;

    actor
        .handle_line(
            1,
            json!({
                "type": "emulator.capabilities",
                "payload": {},
            })
            .to_string(),
        )
        .await;

    assert_eq!(actor.emulator_requests.outstanding(), 0);
    assert!(!actor.clients.contains_key(&1));
    assert!(receiver.try_recv().is_err());
}

#[tokio::test]
async fn failed_shutdown_broadcasts_updated_instead_of_terminal_shutdown() {
    let dir = tempfile::tempdir().unwrap();
    let runtime_store = RuntimeStore::open(dir.path()).await.unwrap();
    let now = Utc::now();
    runtime_store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "tab".into(),
            workspace_id: "workspace".into(),
            kind: MOBILE_EMULATOR_TAB_KIND.into(),
            title: "Test Device".into(),
            created_at: now,
            updated_at: now,
            payload: json!({
                "mobileEmulator": {
                    "schemaVersion": 1,
                    "platform": "android",
                    "deviceId": "android:test-device",
                }
            }),
        })
        .await
        .unwrap();
    let mut manager = EmulatorManager::new(dir.path()).await.unwrap();
    manager.insert_owned_android_session_for_shutdown_failure_test(
        "workspace",
        "tab",
        dir.path().join("missing-adb"),
    );

    let completion = run_emulator_request(
        Some(Arc::new(Mutex::new(manager))),
        runtime_store,
        1,
        "emulator.shutdown",
        &json!({"tabId": "tab"}),
    )
    .await;

    assert_eq!(completion.response["stopped"], false);
    assert_eq!(
        completion
            .broadcast
            .expect("failure should refresh clients")
            .reason,
        "updated"
    );
}
