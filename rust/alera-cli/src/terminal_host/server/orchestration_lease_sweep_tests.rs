use std::collections::HashMap;

use alera_core::runtime::{
    ActivityOutcome, NewOrchestrationTask, NewRunPlan, OrchestrationDispatchStatus,
    OrchestrationGateStatus, OrchestrationTaskStatus, RunGateKind, STALL_GATE_RESUMED,
};
use serde_json::json;

use super::actor_test_harness::{local_client, test_actor};
use super::ServerActor;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::orchestration::agent_presence::AgentPresenceState;
use crate::terminal_host::orchestration::coordinator_loop::CoordinatorConfig;
use crate::terminal_host::session::Session;

fn session(id: &str) -> (String, Session) {
    let mut session = Session::driver_test_stub(id, 80, 24);
    session.workspace_id = "ws".to_string();
    session.tab_id = format!("tab-{id}");
    (id.to_string(), session)
}

async fn actor(dir: &tempfile::TempDir, terminals: &[&str]) -> ServerActor {
    let (handle, _rx) = ClientHandle::test_channels();
    test_actor(
        dir,
        HashMap::from([(1, local_client(handle))]),
        terminals.iter().map(|id| session(id)).collect(),
    )
    .await
}

async fn ready_task(actor: &ServerActor, run_id: Option<&str>) -> String {
    actor
        .runtime_store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "do work".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: run_id.map(str::to_string),
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap()
        .id
}

/// A dispatch nobody accepted, dispatched long before the startup deadline.
async fn overdue_dispatch(actor: &ServerActor, handle: &str) -> String {
    let task = ready_task(actor, None).await;
    let dispatch = actor
        .runtime_store
        .create_scoped_orchestration_dispatch(&task, handle, None, "ws", "coord", None, "keep-open")
        .await
        .unwrap();
    sqlx::query(
        "UPDATE orchestrationDispatchContexts SET dispatched_at = '2020-01-01 00:00:00' WHERE id = ?",
    )
    .bind(&dispatch.id)
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
    dispatch.id
}

async fn dispatch_status(actor: &ServerActor, id: &str) -> OrchestrationDispatchStatus {
    actor
        .runtime_store
        .orchestration_dispatch_by_id(id)
        .await
        .unwrap()
        .unwrap()
        .status
}

#[tokio::test]
async fn the_startup_deadline_fails_only_startups_without_a_live_agent() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir, &["silent", "busy"]).await;
    actor
        .agent_presence
        .update("busy", "claude".to_string(), AgentPresenceState::Working);
    let gone = overdue_dispatch(&actor, "gone").await;
    let silent = overdue_dispatch(&actor, "silent").await;
    let busy = overdue_dispatch(&actor, "busy").await;

    actor.sweep_orchestration_leases(chrono::Utc::now()).await;

    assert_eq!(
        dispatch_status(&actor, &gone).await,
        OrchestrationDispatchStatus::StartupFailed
    );
    assert_eq!(
        dispatch_status(&actor, &silent).await,
        OrchestrationDispatchStatus::StartupFailed
    );
    // A detected agent that has not run a command yet is left to the lease.
    assert_eq!(
        dispatch_status(&actor, &busy).await,
        OrchestrationDispatchStatus::AwaitingAcceptance
    );
}

#[tokio::test]
async fn an_expired_lease_stalls_and_later_activity_revives_and_completes() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir, &["worker"]).await;
    let task = ready_task(&actor, None).await;
    let dispatch = actor
        .runtime_store
        .create_orchestration_dispatch(&task, "worker")
        .await
        .unwrap();
    sqlx::query(
        "UPDATE orchestrationDispatchContexts SET last_activity_at = '2020-01-01 00:00:00' WHERE id = ?",
    )
    .bind(&dispatch.id)
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();

    actor.sweep_orchestration_leases(chrono::Utc::now()).await;

    assert_eq!(
        dispatch_status(&actor, &dispatch.id).await,
        OrchestrationDispatchStatus::Stalled
    );
    let gates = actor
        .runtime_store
        .list_orchestration_gates(Some(&task), Some(OrchestrationGateStatus::Pending))
        .await
        .unwrap();
    assert_eq!(
        gates.len(),
        1,
        "a stalled worker opens a stall gate by default"
    );
    assert_eq!(gates[0].kind, RunGateKind::Stall);
    assert_eq!(
        gates[0].options,
        ["killAndFailover", "keepWaiting", "abortStage"]
    );

    let stalled = actor
        .runtime_store
        .orchestration_dispatch_by_id(&dispatch.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        actor.record_dispatch_activity(&stalled).await,
        ActivityOutcome::Revived
    );
    let gate = actor
        .runtime_store
        .orchestration_gate_by_id(&gates[0].id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(gate.resolution.as_deref(), Some(STALL_GATE_RESUMED));

    // Stall it again: a worker that finishes while stalled may still complete.
    actor
        .runtime_store
        .stall_expired_orchestration_dispatches("9999-01-01 00:00:00")
        .await
        .unwrap();
    let completed = actor
        .handle_orchestration_request(
            1,
            2,
            "orchestration.complete",
            &json!({"terminal": "worker", "result": {"summary": "done after all"}}),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(completed["taskStatus"], "completed", "{completed}");
    let stored = actor
        .runtime_store
        .orchestration_task_by_id(&task)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(stored.status, OrchestrationTaskStatus::Completed);
    let result: serde_json::Value =
        serde_json::from_str(stored.result.as_deref().unwrap()).unwrap();
    assert_eq!(result["completionKind"], "success");
    assert_eq!(result["artifacts"], json!([]));
}

#[tokio::test]
async fn a_pending_plan_gate_holds_scheduling_until_it_is_approved() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = actor(&dir, &["worker"]).await;
    actor
        .agent_presence
        .update("worker", "claude".to_string(), AgentPresenceState::Done);
    let _pasted = actor
        .sessions
        .get_mut("worker")
        .unwrap()
        .attach_test_input();
    let run = actor
        .runtime_store
        .create_planned_orchestration_coordinator_run(
            "ship it",
            Some("coord"),
            2000,
            "ws",
            4,
            NewRunPlan {
                approval_required: true,
                ..NewRunPlan::default()
            },
        )
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
         VALUES ('worker-profile', 'Worker', 'codex', 'codex', datetime('now'), datetime('now'))",
    )
    .execute(actor.runtime_store.pool())
    .await
    .unwrap();
    let proposed = actor
        .runtime_store
        .propose_run_plan(
            &run.id,
            alera_core::runtime::RunPlanInput {
                stages: vec![alera_core::runtime::RunPlanStageInput {
                    id: "work".into(),
                    title: None,
                    profile: Some("Worker".into()),
                    fallbacks: Vec::new(),
                    gate: false,
                }],
                ..Default::default()
            },
            &alera_core::runtime::RunActor::runtime(),
        )
        .await
        .unwrap();
    assert_eq!(proposed.status, "awaitingApproval");
    let task = ready_task(&actor, Some(&run.id)).await;
    let config = CoordinatorConfig {
        run_id: run.id.clone(),
        coordinator_handle: Some("coord".to_string()),
        poll_interval_ms: 2000,
        max_concurrent: 4,
        workspace_id: Some("ws".to_string()),
        agent_type: "claude".to_string(),
    };

    actor
        .coordinator_dispatch_ready_tasks(&config)
        .await
        .unwrap();
    assert!(actor
        .runtime_store
        .active_orchestration_dispatch_for_handle("worker")
        .await
        .unwrap()
        .is_none());

    let gate = actor
        .runtime_store
        .list_run_gates(&run.id)
        .await
        .unwrap()
        .remove(0);
    let digest = actor
        .runtime_store
        .run_gate(&gate.id)
        .await
        .unwrap()
        .and_then(|gate| gate.evidence_digest);
    let desktop =
        alera_core::runtime::RunActor::new(alera_core::runtime::RunActorKind::Desktop, None);
    actor
        .runs_resolve_gate(
            &json!({
                "requestId": "approve-plan",
                "gateId": gate.id,
                "decision": "approve",
                "expectedEvidenceDigest": digest,
            }),
            &desktop,
        )
        .await
        .unwrap();
    actor
        .coordinator_dispatch_ready_tasks(&config)
        .await
        .unwrap();

    let dispatch = actor
        .runtime_store
        .active_orchestration_dispatch_for_handle("worker")
        .await
        .unwrap()
        .expect("approval releases scheduling");
    assert_eq!(dispatch.task_id, task);
}
