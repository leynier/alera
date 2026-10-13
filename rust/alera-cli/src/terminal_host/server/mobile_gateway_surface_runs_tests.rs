use std::collections::HashMap;

use alera_core::runtime::{
    AgentProfile, AgentProfileLaunchMode, NewRunPlan, RunActor, RunPlanInput, RunPlanStageInput,
};
use chrono::Utc;
use serde_json::json;

use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::server::actor_test_harness::{mobile_client, test_actor};

/// The phone sees every run verb and only reads recipes. Everything else in
/// the run area stays on the desktop and the CLI.
#[test]
fn mobile_reaches_every_run_verb_and_only_reads_recipes() {
    let expected = [
        "runs.board",
        "runs.snapshot",
        "runs.task",
        "runs.timeline",
        "runs.source",
        "runs.create",
        "runs.plan",
        "runs.gates",
        "runs.gate",
        "runs.resolveGate",
        "runs.control",
        "runs.retryTask",
        "runs.retryIntegration",
        "runs.retryCancellation",
        "runs.resources",
        "runs.cleanups",
        "runs.previewCleanup",
        "runs.cleanup",
        "runs.applyCleanup",
        "runs.retryCleanup",
        "runs.abandonCleanup",
        "runs.integrations",
        "runs.integration",
        "recipes.catalog",
        "recipes.recipe",
    ];
    assert_eq!(MOBILE_RUN_VERBS, expected);
    for verb in expected {
        assert!(mobile_request_allowed(verb), "{verb}");
    }
    for verb in [
        "recipes.validate",
        "recipes.savePersonal",
        "recipes.previewExport",
        "recipes.applyExport",
        "orchestration.planPropose",
        "orchestration.planContext",
        "orchestration.reset",
        "orchestration.run",
        "host.process.run",
        "inbox.wait",
        "inbox.conversations",
        "inbox.conversation",
        "runs.unknown",
        "workflows.decide",
        "workflows.createProposal",
    ] {
        assert!(!mobile_request_allowed(verb), "{verb}");
    }
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&"runsV1"));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&"recipesV1"));
    assert!(!MOBILE_HELLO_CAPABILITIES
        .iter()
        .any(|capability| capability.starts_with("workflow")
            || *capability == "orchestrationRunBoardV1"));
}

#[tokio::test]
async fn a_phone_approves_a_plan_and_the_audit_names_its_device() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut events) = ClientHandle::test_channels();
    let mut clients = HashMap::new();
    clients.insert(2, mobile_client(handle, "pixel"));
    let mut actor = test_actor(&dir, clients, HashMap::new()).await;
    let store = actor.runtime_store.clone();
    let now = Utc::now();
    store
        .upsert_agent_profile(
            AgentProfile {
                id: "worker".into(),
                name: "Worker".into(),
                sort_order: 0,
                agent_type: "codex".into(),
                command: "codex".into(),
                launch_mode: AgentProfileLaunchMode::Command,
                managed_config: None,
                custom_prompt: String::new(),
                description: String::new(),
                quota_group: None,
                show_in_new_tab_menu: false,
                revision: 0,
                created_at: now,
                updated_at: now,
            },
            None,
        )
        .await
        .unwrap();
    let run = store
        .create_planned_orchestration_coordinator_run(
            "Ship it",
            Some("coordinator"),
            2000,
            "global",
            2,
            NewRunPlan {
                approval_required: true,
                stall_policy: "ask",
            },
        )
        .await
        .unwrap();
    let proposed = store
        .propose_run_plan(
            &run.id,
            RunPlanInput {
                stages: vec![RunPlanStageInput {
                    id: "work".into(),
                    title: None,
                    profile: Some("Worker".into()),
                    fallbacks: Vec::new(),
                    gate: false,
                }],
                ..RunPlanInput::default()
            },
            &RunActor::runtime(),
        )
        .await
        .unwrap();
    assert_eq!(proposed.status, "awaitingApproval");
    let gate_id = proposed.plan_gate_id.unwrap();
    let digest = proposed.digest;

    let line = json!({"id": 7, "type": "runs.resolveGate", "payload": {
        "requestId": "approve-1",
        "gateId": gate_id,
        "decision": "approve",
        "expectedEvidenceDigest": digest,
    }})
    .to_string();
    actor.handle_line(2, line).await;
    let response = loop {
        let frame = events.try_recv().expect("the request was answered");
        let frame = frame.as_json().unwrap();
        if frame.get("id") == Some(&json!(7)) {
            break frame;
        }
    };
    assert_eq!(response["ok"], true, "{response}");
    assert_eq!(response["payload"]["runStatus"], "running");
    assert_eq!(response["payload"]["gate"]["actorKind"], "mobile");
    assert_eq!(response["payload"]["gate"]["actorId"], "pixel");

    let (actor_handle, actor_kind, actor_id): (String, String, String) = sqlx::query_as(
        "SELECT actor_handle, actor_kind, actor_id FROM orchestrationAuditEvents
        WHERE action = 'gate.resolve' AND target_id = ?",
    )
    .bind(&gate_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(actor_handle, "mobile:pixel");
    assert_eq!(actor_kind, "mobile");
    assert_eq!(actor_id, "pixel");
    let (event_actor,): (String,) =
        sqlx::query_as("SELECT actor_id FROM runEvents WHERE run_id = ? AND kind = 'gateResolved'")
            .bind(&run.id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert_eq!(event_actor, "pixel");
    actor.dispose().await;
}
