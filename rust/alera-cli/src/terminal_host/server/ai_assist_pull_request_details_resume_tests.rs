use std::collections::HashMap;

use super::super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::super::{ClientHandle, ClientState};
use super::*;

fn mcp(client: &str, call: &str) -> Value {
    json!({ "transport": "remote", "clientId": client, "grantId": "g-1", "callId": call })
}

async fn actor_with_clients(root: &tempfile::TempDir) -> ServerActor {
    let mut clients = HashMap::new();
    clients.insert(1, local_client(ClientHandle::test_channels().0));
    clients.insert(2, ClientState::local(ClientHandle::test_channels().0, true));
    clients.insert(3, mobile_client(ClientHandle::test_channels().0, "pixel"));
    test_actor(root, clients, HashMap::new()).await
}

#[test]
fn only_a_request_with_a_wait_is_resumable() {
    assert!(is_resumable_pull_request_details(
        VERB,
        &json!({ "waitMs": 0 })
    ));
    assert!(!is_resumable_pull_request_details(VERB, &json!({})));
    assert!(!is_resumable_pull_request_details(
        VERB,
        &json!({ "waitMs": null })
    ));
    assert!(!is_resumable_pull_request_details(
        "aiText.commitMessage.generate",
        &json!({ "waitMs": 10 })
    ));
}

#[test]
fn waits_are_bounded_and_must_be_integers() {
    assert_eq!(
        requested_wait(&json!({ "waitMs": 1500 })).unwrap(),
        Duration::from_millis(1500)
    );
    assert_eq!(
        requested_wait(&json!({ "waitMs": u64::MAX })).unwrap(),
        MAX_WAIT
    );
    assert!(requested_wait(&json!({ "waitMs": -1 })).is_err());
    assert!(requested_wait(&json!({ "waitMs": "10" })).is_err());
}

#[test]
fn answers_name_the_status_and_the_callers_operation() {
    assert_eq!(
        resumable_answer(None, "op-1"),
        json!({ "status": "running", "operationId": "op-1" })
    );
    assert_eq!(
        resumable_answer(
            Some(json!({ "title": "Fix", "body": null, "agentLabel": "Codex" })),
            "op-1"
        ),
        json!({
            "status": "completed",
            "operationId": "op-1",
            "title": "Fix",
            "body": null,
            "agentLabel": "Codex",
        })
    );
}

#[tokio::test]
async fn retry_keys_are_scoped_to_the_caller() {
    let root = tempfile::tempdir().unwrap();
    let actor = actor_with_clients(&root).await;
    let scope = |client_id, payload: Value| {
        actor
            .pull_request_details_scope(client_id, &payload)
            .unwrap()
    };
    assert_eq!(scope(1, json!({})), json!(["cli"]));
    assert_eq!(scope(2, json!({})), json!(["desktop"]));
    assert_eq!(scope(3, json!({})), json!(["mobile", "pixel"]));
    let first = scope(1, json!({ "origin": mcp("chatgpt", "c-1") }));
    assert_eq!(first, json!(["mcp", "remote", "chatgpt", "g-1"]));
    assert_ne!(
        first,
        scope(1, json!({ "origin": mcp("other-client", "c-1") }))
    );
    // The call id changes on every call, so it never splits one client's key.
    assert_eq!(first, scope(1, json!({ "origin": mcp("chatgpt", "c-2") })));
    // Only a local connection may name the MCP client it acts for.
    assert_eq!(
        scope(3, json!({ "origin": mcp("chatgpt", "c-1") })),
        json!(["mobile", "pixel"])
    );
    assert!(actor
        .pull_request_details_scope(1, &json!({ "origin": { "transport": "carrier" } }))
        .is_err());
}

#[tokio::test]
async fn malformed_resumable_requests_are_refused_before_starting() {
    let root = tempfile::tempdir().unwrap();
    let mut actor = actor_with_clients(&root).await;
    for overrides in [
        json!({ "waitMs": -1 }),
        json!({ "waitMs": "soon" }),
        json!({ "operationId": "x".repeat(OPERATION_ID_MAX_CHARS + 1) }),
        json!({ "operationId": " " }),
        json!({ "baseBranch": "" }),
    ] {
        let mut payload = json!({
            "operationId": "op-1",
            "workspaceId": "ws-1",
            "baseBranch": "main",
            "waitMs": 10,
        });
        for (key, value) in overrides.as_object().unwrap() {
            payload[key] = value.clone();
        }
        assert!(
            actor
                .start_resumable_pull_request_details(1, 7, &payload)
                .is_err(),
            "{overrides}"
        );
    }
}

#[tokio::test]
async fn a_job_for_a_missing_workspace_fails_without_generating() {
    let root = tempfile::tempdir().unwrap();
    let actor = actor_with_clients(&root).await;
    let job = DetailsJob {
        store: actor.runtime_store.clone(),
        links: actor.host_links.clone(),
        workspace_id: "missing".into(),
        base_branch: "main".into(),
        hub_settings: None,
    };
    let error = job.run().await.unwrap_err();
    assert!(error.to_string().contains("Workspace not found"), "{error}");
}
