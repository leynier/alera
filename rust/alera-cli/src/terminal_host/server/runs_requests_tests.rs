use std::collections::HashMap;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::client::{ClientFrame, ClientHandle};

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::ServerActor;

async fn answer(
    actor: &mut ServerActor,
    events: &mut UnboundedReceiver<ClientFrame>,
    client: u64,
    id: i64,
    request_type: &str,
    payload: Value,
) -> Value {
    let line = json!({"id": id, "type": request_type, "payload": payload}).to_string();
    actor.handle_line(client, line).await;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let frame = tokio::time::timeout_at(deadline, events.recv())
            .await
            .unwrap()
            .unwrap();
        let frame = frame.as_json().unwrap();
        if frame.get("id") == Some(&json!(id)) {
            return frame;
        }
    }
}

#[tokio::test]
async fn runs_and_recipes_are_advertised_instead_of_workflows() {
    let dir = tempfile::tempdir().unwrap();
    let actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    let status = actor.host_status_payload();
    let capabilities = status["runtimeCapabilities"].as_array().unwrap();
    assert!(capabilities.contains(&json!("runsV1")));
    assert!(capabilities.contains(&json!("recipesV1")));
    assert!(!capabilities.iter().any(|capability| {
        capability.as_str().is_some_and(|value| {
            value.starts_with("workflow") || value == "orchestrationRunBoardV1"
        })
    }));
}

#[tokio::test]
async fn run_board_answers_one_camel_case_snapshot_without_launching_a_coordinator() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
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
    let response = answer(&mut actor, &mut rx, 1, 42, "runs.board", json!({})).await;
    assert_eq!(response["ok"], true, "{response}");
    let item = &response["payload"]["items"][0];
    assert_eq!(item["objective"], "read only");
    assert_eq!(item["isolation"], "shared");
    assert_eq!(item["pendingGateKinds"], json!([]));
    assert_eq!(item["pendingGates"], json!([]));
    assert_eq!(response["payload"]["counts"]["active"], 1);
    let snapshot = answer(
        &mut actor,
        &mut rx,
        1,
        46,
        "runs.snapshot",
        json!({"runId": item["id"]}),
    )
    .await;
    assert_eq!(snapshot["ok"], true, "{snapshot}");
    assert_eq!(snapshot["payload"]["resourceCount"], 0);
    assert_eq!(snapshot["payload"]["run"]["pendingGates"], json!([]));
    assert!(
        actor.coordinators.is_empty(),
        "reading must never launch a coordinator"
    );
    let invalid = answer(
        &mut actor,
        &mut rx,
        1,
        43,
        "runs.board",
        json!({"limit": 1000}),
    )
    .await;
    assert_eq!(invalid["ok"], false);
    let unknown = answer(&mut actor, &mut rx, 1, 44, "runs.unknown", json!({})).await;
    assert_eq!(unknown["ok"], false);
    for removed in [
        "workflows.decide",
        "orchestration.boardSnapshot",
        "orchestration.gateResolve",
        "orchestration.runPolicyShow",
    ] {
        let refused = answer(&mut actor, &mut rx, 1, 45, removed, json!({})).await;
        assert_eq!(refused["ok"], false, "{removed}: {refused}");
    }
    actor.dispose().await;
}

#[tokio::test]
async fn runs_changed_reaches_every_authenticated_client_once_per_revision() {
    let dir = tempfile::tempdir().unwrap();
    let (local, mut local_rx) = ClientHandle::test_channels();
    let (mobile, mut mobile_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
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
    for rx in [&mut local_rx, &mut mobile_rx] {
        let event = rx.recv().await.unwrap().as_json().unwrap();
        assert_eq!(event["event"], "runsChanged");
        assert!(event["payload"]["revision"].as_i64().unwrap() > 0);
    }
    actor.broadcast_orchestration_board_change().await;
    assert!(local_rx.try_recv().is_err());
    assert!(mobile_rx.try_recv().is_err());
    actor.dispose().await;
}

#[tokio::test]
async fn run_mutations_enforce_their_guards() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(2, mobile_client(handle, "pixel"))]),
        HashMap::new(),
    )
    .await;
    let run = actor
        .runtime_store
        .create_orchestration_coordinator_run("guarded", Some("coordinator"), 2000)
        .await
        .unwrap();
    let missing = answer(
        &mut actor,
        &mut rx,
        2,
        1,
        "runs.control",
        json!({"requestId": "cancel-1", "runId": run.id, "action": "cancel"}),
    )
    .await;
    assert_eq!(missing["ok"], false);
    assert!(missing["error"]
        .as_str()
        .unwrap()
        .contains("expectedSequence"));
    let unconfirmed = answer(
        &mut actor,
        &mut rx,
        2,
        2,
        "runs.applyCleanup",
        json!({"id": uuid::Uuid::new_v4().to_string(), "digest": "abc"}),
    )
    .await;
    assert_eq!(unconfirmed["ok"], false);
    assert!(unconfirmed["error"].as_str().unwrap().contains("confirm"));
    let stale = answer(
        &mut actor,
        &mut rx,
        2,
        3,
        "runs.control",
        json!({"requestId": "pause-1", "runId": run.id, "action": "pause", "expectedSequence": 9}),
    )
    .await;
    assert_eq!(stale["ok"], false);
    assert_eq!(stale["errorCode"], "run_sequence_stale", "{stale}");
    let paused = answer(
        &mut actor,
        &mut rx,
        2,
        4,
        "runs.control",
        json!({"requestId": "pause-2", "runId": run.id, "action": "pause", "expectedSequence": 0}),
    )
    .await;
    assert_eq!(paused["ok"], true, "{paused}");
    assert_eq!(paused["payload"]["status"], "paused");
    let recipes = answer(&mut actor, &mut rx, 2, 5, "recipes.catalog", json!({})).await;
    assert_eq!(recipes["ok"], true, "{recipes}");
    let write = answer(
        &mut actor,
        &mut rx,
        2,
        6,
        "recipes.savePersonal",
        json!({"document": "version: 1"}),
    )
    .await;
    assert_eq!(write["ok"], false);
    actor.dispose().await;
}
