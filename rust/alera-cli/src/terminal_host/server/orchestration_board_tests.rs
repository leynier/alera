use std::collections::HashMap;
use std::time::Duration;

use serde_json::json;

use crate::terminal_host::client::ClientHandle;

use super::actor_test_harness::{local_client, mobile_client, test_actor};

#[tokio::test]
async fn board_read_is_authenticated_local_only_and_does_not_trust_actor_fields() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _rx) = ClientHandle::test_channels();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    assert!(actor
        .start_orchestration_board_read(1, 10, "orchestration.boardSnapshot", &json!({}))
        .is_err());
    actor
        .clients
        .insert(1, mobile_client(handle.clone(), "device"));
    assert!(actor
        .start_orchestration_board_read(
            1,
            10,
            "orchestration.boardSnapshot",
            &json!({"actor": "app"})
        )
        .is_err());
    actor.clients.insert(1, local_client(handle));
    assert!(actor
        .start_orchestration_board_read(
            1,
            10,
            "orchestration.boardSnapshot",
            &json!({"actor": "app"})
        )
        .is_err());
    assert!(actor
        .start_orchestration_board_read(1, 10, "orchestration.unknown", &json!({}))
        .is_err());
}

#[tokio::test]
async fn board_deferred_read_returns_one_aggregate_snapshot() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    actor
        .runtime_store
        .create_orchestration_coordinator_run("read only", Some("coordinator"), 2000)
        .await
        .unwrap();
    actor
        .start_orchestration_board_read(1, 42, "orchestration.boardSnapshot", &json!({}))
        .unwrap();
    let frame = tokio::time::timeout(Duration::from_secs(5), rx.recv())
        .await
        .unwrap()
        .unwrap();
    let response = frame.as_json().unwrap();
    assert_eq!(response["id"], 42);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["items"][0]["objective"], "read only");
    assert_eq!(response["payload"]["counts"]["active"], 1);
    assert!(
        actor.coordinators.is_empty(),
        "reading must never launch a coordinator"
    );
}

#[tokio::test]
async fn board_change_events_are_coalesced_by_revision_and_never_sent_to_mobile() {
    let dir = tempfile::tempdir().unwrap();
    let (local, mut local_rx) = ClientHandle::test_channels();
    let (mobile, mut mobile_rx) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(local)),
            (2, mobile_client(mobile, "device")),
        ]),
        HashMap::new(),
    )
    .await;
    actor
        .runtime_store
        .create_orchestration_coordinator_run("changes", Some("coordinator"), 2000)
        .await
        .unwrap();
    actor.broadcast_orchestration_board_change().await;
    let event = local_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(event["event"], "orchestrationBoardChanged");
    assert!(event["payload"]["revision"].as_i64().unwrap() > 0);
    actor.broadcast_orchestration_board_change().await;
    assert!(local_rx.try_recv().is_err());
    assert!(mobile_rx.try_recv().is_err());
}

#[tokio::test]
async fn invalid_limits_return_errors_without_starting_workers() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    actor
        .start_orchestration_board_read(
            1,
            43,
            "orchestration.boardSnapshot",
            &json!({"limit": 1000}),
        )
        .unwrap();
    let response = tokio::time::timeout(Duration::from_secs(5), rx.recv())
        .await
        .unwrap()
        .unwrap()
        .as_json()
        .unwrap();
    assert_eq!(response["ok"], false);
    assert!(actor.coordinators.is_empty());
}
