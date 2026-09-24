use std::collections::HashMap;

use alera_core::runtime::{PrepareWorkflowPlan, WorkflowPlanProposal};
use serde_json::json;

use crate::managed_workspace::workflow::tests::fixture::Fixture;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{local_client, mobile_client, test_actor};
use crate::terminal_host::server::workflow_launch_requests::CancellationShutdown;

#[tokio::test]
async fn workflow_coordinator_lookup_uses_nonblocking_job_accounting() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut responses) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor
        .start_workflow_coordinator_request(1, 1, &json!({"id":"missing"}))
        .unwrap();
    assert_eq!(actor.workflow_workspace_jobs, 1);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(!actor.has_blocking_managed_workspace_jobs());
    actor
        .handle_line(
            1,
            json!({"id":2,"type":"write","payload":{"sessionId":"missing","data":"x"}}).to_string(),
        )
        .await;
    let response = responses.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 2);
    assert_ne!(
        response["error"],
        "A runtime mutation is in progress. Wait for it to finish and retry."
    );
    let command = tokio::time::timeout(std::time::Duration::from_secs(5), commands.recv())
        .await
        .unwrap()
        .unwrap();
    actor.handle(command).await;
    assert_eq!(actor.workflow_workspace_jobs, 0);
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(!actor.has_blocking_managed_workspace_jobs());
}

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
    let second = actor
        .launch_workflow_coordinator(draft.clone())
        .await
        .unwrap();
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
    // A second host has no process-local winner permit, even while the durable
    // receipt says started and no cancellation has happened yet.
    let mut restored = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    restored.runtime_store = fixture.store.clone();
    restored.runtime_dir = fixture.runtime.clone();
    restored.reconcile_spawn_on_create_tabs().await;
    assert!(restored.sessions.is_empty());
    assert!(restored
        .runtime_store
        .find_workspace_tab(tab)
        .await
        .unwrap()
        .is_some());
    let mut interrupted_request = draft.request.clone();
    interrupted_request.request_id = "interrupted-coordinator".into();
    let interrupted = fixture
        .store
        .create_workflow_proposal(interrupted_request, |_| Ok(()))
        .await
        .unwrap();
    let (reserved, created) = fixture
        .store
        .reserve_workflow_coordinator(&interrupted)
        .await
        .unwrap();
    assert!(created);
    let mut interrupted_tab = saved.clone();
    interrupted_tab.id = reserved.tab_id.clone();
    interrupted_tab.payload["terminalSessionId"] = json!(reserved.tab_id);
    fixture
        .store
        .upsert_workspace_tab(interrupted_tab)
        .await
        .unwrap();
    restored.reconcile_spawn_on_create_tabs().await;
    assert!(
        restored.sessions.is_empty(),
        "reserved state is not a launch permit"
    );
    fixture.store.recover_workflow_coordinators().await.unwrap();
    restored.reconcile_spawn_on_create_tabs().await;
    assert!(restored.sessions.is_empty());
    assert_eq!(
        fixture
            .store
            .workflow_coordinator(&interrupted.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "attention"
    );
    let cancellation = fixture
        .store
        .cancel_workflow_proposal("coordinator-proposal")
        .await
        .unwrap();
    let mut forged = cancellation.clone();
    forged.workspace_id = "different-owner".into();
    assert!(actor
        .cancel_workflow_proposal_terminal(&forged)
        .await
        .is_err());
    assert!(actor.sessions.contains_key(tab));
    let shutdown = actor
        .cancel_workflow_proposal_terminal(&cancellation)
        .await
        .unwrap();
    assert!(!actor.sessions.contains_key(tab));
    let checkpoint = actor.store.read(tab, 1024 * 1024).await.unwrap().unwrap();
    assert!(!checkpoint.running);
    assert_eq!(checkpoint.tab_id, tab);
    let mut restarted_before_verification = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    restarted_before_verification.runtime_store = fixture.store.clone();
    assert!(restarted_before_verification
        .cancel_workflow_proposal_terminal(&cancellation)
        .await
        .is_err());
    assert!(fixture
        .store
        .settle_workflow_proposal_cancellation(&cancellation, None)
        .await
        .is_err());
    let CancellationShutdown::Wait(mut guard) = shutdown else {
        panic!("live coordinator requires process closure verification");
    };
    guard.wait().await.unwrap();
    fixture
        .store
        .verify_workflow_terminal_shutdown(tab, "owner")
        .await
        .unwrap();
    fixture
        .store
        .settle_workflow_proposal_cancellation(&cancellation, None)
        .await
        .unwrap();
    assert!(fixture
        .store
        .pending_workflow_proposal_cancellations()
        .await
        .unwrap()
        .is_empty());
    assert!(actor
        .cancel_workflow_proposal_terminal(&cancellation)
        .await
        .is_err());
    let mut restarted = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    restarted.runtime_store = alera_core::runtime::RuntimeStore::open(&fixture.runtime)
        .await
        .unwrap();
    restarted.runtime_dir = fixture.runtime.clone();
    restarted.reconcile_spawn_on_create_tabs().await;
    assert!(restarted.sessions.is_empty());
    assert!(restarted
        .runtime_store
        .find_workspace_tab(tab)
        .await
        .unwrap()
        .is_some());
    assert!(restarted
        .require_workflow_spawn_permit(tab, "owner", tab, None)
        .await
        .is_err());
    assert!(restarted
        .require_workflow_spawn_permit("other-session", "owner", tab, None)
        .await
        .is_err());
    // Attachment may restore only an exited checkpoint, never a new process.
    let _ = restarted
        .attach_workflow_terminal(1, tab, "owner", tab)
        .await;
    assert!(restarted
        .sessions
        .values()
        .all(|session| !session.running()));
}
