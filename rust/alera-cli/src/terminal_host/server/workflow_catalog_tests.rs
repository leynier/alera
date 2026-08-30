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
    let actor = test_actor(
        &dir,
        HashMap::from([
            (1, local_client(handle)),
            (2, mobile_client(mobile, "device")),
        ]),
        HashMap::new(),
    )
    .await;
    let payload = json!({"document":builtin_workflow_recipes()[0].portable_document().unwrap()});
    actor
        .start_workflow_catalog_request(1, 9, "workflows.savePersonalRecipe", &payload)
        .unwrap();
    let event = response(&mut rx).await;
    assert_eq!(event["event"], "workflowCatalogChanged");
    assert_eq!(event["payload"]["catalogRevision"], 1);
    assert_eq!(event["payload"]["source"]["origin"], "personal");
    assert_eq!(response(&mut rx).await["ok"], true);
    assert!(mobile_rx.try_recv().is_err());
    actor
        .start_workflow_catalog_request(1, 10, "workflows.savePersonalRecipe", &payload)
        .unwrap();
    let error = response(&mut rx).await;
    assert_eq!(error["id"], 10);
    assert_eq!(error["ok"], false);
    assert!(rx.try_recv().is_err());
    assert!(actor.coordinators.is_empty());
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
