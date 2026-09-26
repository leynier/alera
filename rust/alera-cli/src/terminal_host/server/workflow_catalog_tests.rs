use std::collections::HashMap;
use std::time::Duration;

use alera_core::runtime::builtin_workflow_recipes;
use serde_json::{json, Value};

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn workflow_catalog_rpc_is_authenticated_local_only_and_rejects_actor_spoofing() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _rx) = ClientHandle::test_channels();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    for verb in [
        "workflows.catalog",
        "workflows.recipe",
        "workflows.validateRecipe",
        "workflows.savePersonalRecipe",
        "workflows.previewRecipeExport",
        "workflows.applyRecipeExport",
    ] {
        assert!(actor
            .start_workflow_catalog_request(1, 1, verb, &json!({"actor":"app"}))
            .is_err());
        actor
            .clients
            .insert(1, mobile_client(handle.clone(), "device"));
        assert!(actor
            .start_workflow_catalog_request(1, 1, verb, &json!({"actor":"app"}))
            .is_err());
        actor.clients.insert(1, local_client(handle.clone()));
        assert!(actor
            .start_workflow_catalog_request(1, 1, verb, &json!({"actor":"app"}))
            .is_err());
        actor.clients.get_mut(&1).unwrap().authenticated = false;
        assert!(actor
            .start_workflow_catalog_request(1, 1, verb, &json!({}))
            .is_err());
        actor.clients.remove(&1);
    }
}

#[tokio::test]
async fn workflow_catalog_rpc_validates_lists_and_reads_without_creating_tasks_or_workers() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    for (id, verb, payload) in [
        (1, "workflows.catalog", json!({})),
        (
            2,
            "workflows.recipe",
            json!({"source":{"origin":"builtIn","id":"quick-fix"}}),
        ),
        (
            3,
            "workflows.validateRecipe",
            json!({"document":builtin_workflow_recipes()[1].portable_document().unwrap()}),
        ),
        (
            4,
            "workflows.validateRecipe",
            json!({"document":"hooks: dangerous"}),
        ),
    ] {
        assert!(actor
            .try_start_deferred_request(1, id, verb, &payload)
            .await
            .unwrap());
        let value = response(&mut rx).await;
        assert_eq!(value["id"], id);
        assert_eq!(value["ok"], id != 4, "{value}");
        if id == 1 {
            assert_eq!(value["payload"]["entries"].as_array().unwrap().len(), 2);
        }
        if id == 2 {
            assert_eq!(value["payload"]["recipe"]["id"], "quick-fix");
        }
        if id == 3 {
            assert_eq!(
                value["payload"]["stageOrder"],
                json!(["foundation", "implementation", "product"])
            );
        }
    }
    let tasks: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(actor.runtime_store.pool())
        .await
        .unwrap();
    assert_eq!(tasks, 0);
    assert!(actor.coordinators.is_empty());
    assert!(actor.sessions.is_empty());
}

#[tokio::test]
async fn workflow_catalog_rpc_save_emits_local_event_and_rejects_stale_overwrites() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let (mobile, mut mobile_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(handle)),
            (2, mobile_client(mobile, "device")),
        ]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    let payload = json!({"document":builtin_workflow_recipes()[0].portable_document().unwrap()});
    actor
        .start_workflow_catalog_request(1, 9, "workflows.savePersonalRecipe", &payload)
        .unwrap();
    assert_eq!(response(&mut rx).await["ok"], true);
    complete_save(&mut actor, &mut inbox_rx).await;
    let event = response(&mut rx).await;
    assert_eq!(event["event"], "workflowCatalogChanged");
    assert_eq!(event["payload"]["catalogRevision"], 1);
    assert_eq!(event["payload"]["source"]["origin"], "personal");
    assert!(mobile_rx.try_recv().is_err());
    actor
        .start_workflow_catalog_request(1, 10, "workflows.savePersonalRecipe", &payload)
        .unwrap();
    let error = response(&mut rx).await;
    assert_eq!(error["id"], 10);
    assert_eq!(error["ok"], false);
    assert!(rx.try_recv().is_err());
    assert!(inbox_rx.try_recv().is_err());
    assert!(actor.coordinators.is_empty());
}

#[tokio::test]
async fn workflow_catalog_timed_out_save_does_not_emit_a_success_event() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    // Exhaust this test's pool so no save can reach SQLite before the real RPC deadline.
    let mut connections = Vec::new();
    for _ in 0..actor.runtime_store.pool().options().get_max_connections() {
        connections.push(actor.runtime_store.pool().acquire().await.unwrap());
    }
    actor
        .start_workflow_catalog_request(
            1,
            1,
            "workflows.savePersonalRecipe",
            &json!({"document":builtin_workflow_recipes()[0].portable_document().unwrap()}),
        )
        .unwrap();
    let error = tokio::time::timeout(Duration::from_secs(35), rx.recv())
        .await
        .unwrap()
        .unwrap()
        .as_json()
        .unwrap();
    assert_eq!(error["ok"], false);
    assert!(error.to_string().contains("timed out"), "{error}");
    assert!(inbox_rx.try_recv().is_err());
    drop(connections);
    assert_eq!(
        actor
            .runtime_store
            .workflow_catalog(None)
            .await
            .unwrap()
            .entries
            .len(),
        2
    );
    assert!(rx.try_recv().is_err());
}

#[tokio::test]
async fn workflow_catalog_save_notifies_clients_connected_while_persistence_is_pending() {
    pending_save_notifies_current_clients(false).await;
}

#[tokio::test]
async fn workflow_catalog_save_notifies_survivors_after_the_initiator_disconnects() {
    pending_save_notifies_current_clients(true).await;
}

async fn pending_save_notifies_current_clients(disconnect_initiator: bool) {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut initiating_rx) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    let transaction = actor
        .runtime_store
        .pool()
        .begin_with("BEGIN IMMEDIATE")
        .await
        .unwrap();
    actor
        .start_workflow_catalog_request(
            1,
            1,
            "workflows.savePersonalRecipe",
            &json!({"document":builtin_workflow_recipes()[0].portable_document().unwrap()}),
        )
        .unwrap();
    let (late, mut late_rx) = ClientHandle::test_channels();
    actor.clients.insert(2, local_client(late));
    actor
        .start_workflow_catalog_request(2, 2, "workflows.catalog", &json!({}))
        .unwrap();
    let old_catalog = response(&mut late_rx).await;
    assert_eq!(old_catalog["ok"], true);
    assert_eq!(
        old_catalog["payload"]["entries"].as_array().unwrap().len(),
        2
    );
    assert!(inbox_rx.try_recv().is_err());
    if disconnect_initiator {
        actor.clients.remove(&1);
        initiating_rx.close();
    }
    transaction.commit().await.unwrap();
    if !disconnect_initiator {
        assert_eq!(response(&mut initiating_rx).await["ok"], true);
    }
    complete_save(&mut actor, &mut inbox_rx).await;
    let event = response(&mut late_rx).await;
    assert_eq!(event["event"], "workflowCatalogChanged");
    assert_eq!(event["payload"]["catalogRevision"], 1);
    assert_eq!(
        event["payload"]["source"],
        json!({"origin":"personal", "id":"quick-fix"})
    );
    if !disconnect_initiator {
        assert_eq!(
            response(&mut initiating_rx).await["event"],
            "workflowCatalogChanged"
        );
    }
    assert!(inbox_rx.try_recv().is_err());
}

async fn complete_save(
    actor: &mut super::ServerActor,
    inbox: &mut tokio::sync::mpsc::UnboundedReceiver<super::ServerCommand>,
) {
    let command = tokio::time::timeout(Duration::from_secs(10), inbox.recv())
        .await
        .unwrap()
        .unwrap();
    assert!(matches!(
        command,
        super::ServerCommand::WorkflowCatalogChanged { .. }
    ));
    actor.handle(command).await;
}

async fn response(
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<crate::terminal_host::client::ClientFrame>,
) -> Value {
    tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap()
        .unwrap()
        .as_json()
        .unwrap()
}
