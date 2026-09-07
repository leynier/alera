use std::collections::HashMap;

use alera_core::runtime::{PrepareWorkflowPlan, WorkflowPlanProposal};
use serde_json::json;

use crate::managed_workspace::workflow::tests::fixture::Fixture;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, mobile_client, test_actor};

#[tokio::test]
async fn workflow_coordinator_launch_rejects_untrusted_connections_and_payloads() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _responses) = ClientHandle::test_channels();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    assert!(actor
        .start_workflow_coordinator_request(1, 1, &json!({"id":"proposal"}))
        .is_err());
    actor
        .clients
        .insert(1, mobile_client(handle.clone(), "device"));
    assert!(actor
        .start_workflow_coordinator_request(1, 1, &json!({"id":"proposal"}))
        .is_err());
    actor.clients.insert(1, local_client(handle));
    for payload in [
        json!({}),
        json!({"id": "x".repeat(161)}),
        json!({"id":"proposal", "profileId":"forged"}),
    ] {
        assert!(actor
            .start_workflow_coordinator_request(1, 1, &payload)
            .is_err());
    }
    assert_eq!(actor.managed_workspace_jobs, 0);
}

#[tokio::test]
async fn workflow_coordinator_launch_replays_one_terminal_with_frozen_profile() {
    let fixture = Fixture::with_command("", "echo workflow-coordinator-test").await;
    let plan = &fixture.plan.plan;
    let request = PrepareWorkflowPlan {
        request_id: "coordinator-proposal".into(),
        workspace_id: "owner".into(),
        run_id: None,
        expected_revision: None,
        proposal: WorkflowPlanProposal {
            objective: "Propose a scoped plan".into(),
            source_sha: plan.source_sha.clone(),
            recipe_source: plan.recipe.source.clone(),
            expected_recipe_digest: plan.recipe.recipe.content_digest().unwrap(),
            coordinator_profile_id: "profile".into(),
            role_profiles: plan
                .recipe
                .recipe
                .roles
                .iter()
                .map(|role| (role.id.clone(), "profile".into()))
                .collect(),
            max_concurrent: 4,
            tasks: vec![],
        },
    };
    let draft = fixture
        .store
        .create_workflow_proposal(request, |_| Ok(()))
        .await
        .unwrap();
    let mut edited = fixture
        .store
        .find_agent_profile("profile")
        .await
        .unwrap()
        .unwrap();
    let revision = edited.revision;
    edited.command = "must-not-run-edited-profile".into();
    fixture
        .store
        .upsert_agent_profile(edited, Some(revision))
        .await
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let first = actor
        .launch_workflow_coordinator(draft.clone())
        .await
        .unwrap();
    let tab = first["tabId"].as_str().unwrap();
    assert_eq!(first["status"], "started");
    let instance = actor.sessions[tab].instance_id();
    let second = actor.launch_workflow_coordinator(draft).await.unwrap();
    assert_eq!(first, second);
    assert_eq!(actor.sessions.len(), 1);
    assert_eq!(actor.sessions[tab].instance_id(), instance);
    let saved = fixture
        .store
        .find_workspace_tab(tab)
        .await
        .unwrap()
        .unwrap();
    let serialized = serde_json::to_string(&saved.payload).unwrap();
    assert!(serialized.contains("echo workflow-coordinator-test"));
    assert!(!serialized.contains("must-not-run-edited-profile"));
    actor.terminate_sessions_for_tab(tab).await;
}
