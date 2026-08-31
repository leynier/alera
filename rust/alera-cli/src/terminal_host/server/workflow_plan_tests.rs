use std::collections::HashMap;
use std::time::Duration;

use alera_core::workflow_approval::{
    WorkflowApprovalChallenge, WorkflowApprovalStatement, WorkflowDecision,
};
use serde_json::{json, Value};

use super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::client_delivery::LocalClientRole;
use crate::terminal_host::client::ClientHandle;

#[tokio::test]
async fn workflow_plan_rpc_rejects_mobile_and_unauthenticated_clients() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _rx) = ClientHandle::test_channels();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    for verb in [
        "workflows.preparePlan",
        "workflows.plan",
        "workflows.approvalChallenge",
        "workflows.decide",
    ] {
        assert!(actor
            .start_workflow_plan_request(1, 1, verb, &json!({}))
            .is_err());
        actor
            .clients
            .insert(1, mobile_client(handle.clone(), "device"));
        assert!(actor
            .start_workflow_plan_request(1, 1, verb, &json!({}))
            .is_err());
        actor.clients.insert(1, local_client(handle.clone()));
        actor.clients.get_mut(&1).unwrap().authenticated = false;
        assert!(actor
            .start_workflow_plan_request(1, 1, verb, &json!({}))
            .is_err());
        actor.clients.clear();
    }
}

#[tokio::test]
async fn workflow_plan_rpc_cannot_approve_with_self_declared_app_role_or_actor() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut rx) = ClientHandle::test_channels();
    let mut client = local_client(handle);
    client.local_role = LocalClientRole::App;
    let mut actor = test_actor(&dir, HashMap::from([(1, client)]), HashMap::new()).await;
    let statement = WorkflowApprovalStatement {
        challenge: WorkflowApprovalChallenge {
            version: 1,
            nonce: "nonce".into(),
            audience: "client".into(),
            run_id: "run".into(),
            revision: 1,
            scope: "plan".into(),
            plan_digest: "plan".into(),
            evidence_digest: "evidence".into(),
            integration_sha: "sha".into(),
            expires_at: i64::MAX,
        },
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    for (id, input) in [
        json!({"actor":"app", "statement":statement, "proof":vec![0; 32]}),
        json!({"statement":statement, "proof":vec![0; 32]}),
    ]
    .into_iter()
    .enumerate()
    {
        assert!(actor
            .try_start_deferred_request(
                1,
                id as i64,
                "workflows.decide",
                &json!({"document":input.to_string()})
            )
            .await
            .unwrap());
        let response = tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .unwrap()
            .unwrap()
            .as_json()
            .unwrap();
        assert_eq!(response["ok"], false);
        assert!(!response.to_string().contains(&actor.token));
    }
    assert!(actor.sessions.is_empty());
    assert!(actor.coordinators.is_empty());
    assert!(actor
        .start_workflow_plan_request(
            1,
            3,
            "workflows.preparePlan",
            &json!({"document":"x".repeat(alera_core::runtime::WORKFLOW_PLAN_MAX_BYTES + 1)})
        )
        .is_err());
    assert!(actor
        .start_workflow_plan_request(1, 3, "workflows.sign", &Value::Null)
        .is_err());
}
