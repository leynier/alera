use super::super::{
    checkout_buffer_guards_tests::fixture,
    runtime_mutations::{run_runtime_mutation, RuntimeMutationRequest},
    ServerActor,
};
use crate::shared_workspace::{prepare_fresh_shared_workspace, SharedWorkspaceCreateRequest};
use alera_core::runtime::*;
use chrono::{Duration, Utc};
use serde_json::json;

fn definition() -> AutomationDefinition {
    let now = Utc::now();
    let actor = AutomationActor {
        kind: AutomationActorKind::LocalCli,
        id: None,
        label: None,
    };
    AutomationDefinition {
        id: "automation-expire".into(),
        slug: "expire".into(),
        name: "Expire".into(),
        description: String::new(),
        project_id: None,
        tag_ids: Vec::new(),
        prompt_template: "Run".into(),
        schedule: AutomationSchedule::OneTime {
            at: now + Duration::hours(1),
            timezone: "UTC".into(),
        },
        target: AutomationTarget::FreshTab {
            workspace_id: "task".into(),
            agent_profile_id: "profile".into(),
        },
        setup_policy: AutomationSetupPolicy::Wait,
        cleanup_policy: None,
        overlap_policy: AutomationOverlapPolicy::Skip,
        queue_cap: 10,
        inactivity_timeout_seconds: 7200,
        heartbeat_interval_seconds: 60,
        misfire_grace_seconds: 900,
        misfire_policy: AutomationMisfirePolicy::Skip,
        retry_max_attempts: 3,
        retry_backoff_seconds: 60,
        circuit_failure_threshold: 3,
        circuit_open_seconds: 900,
        precheck: None,
        notify_on_success: false,
        circuit_opened: false,
        circuit_opened_at: None,
        state: AutomationState::Active,
        revision: 1,
        approved_revision: Some(1),
        created_by: actor.clone(),
        modified_by: actor,
        created_at: now,
        updated_at: now,
    }
}

async fn successful() -> (tempfile::TempDir, ServerActor, AutomationRun) {
    let (root, actor) = fixture().await;
    sqlx::query("INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) VALUES ('profile', 'Profile', 'codex', 'codex', datetime('now'), datetime('now'))")
        .execute(actor.runtime_store.pool()).await.unwrap();
    let mut definition = definition();
    definition.project_id = Some("project".into());
    definition.cleanup_policy = Some(AutomationCleanupPolicy::OnSuccess);
    definition.target = AutomationTarget::ProjectCheckout {
        project_id: "project".into(),
        host_id: "local".into(),
        name_template: "owned".into(),
        agent_profile_id: "profile".into(),
    };
    let definition = actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "occurrence".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-09-12T00:00".into(),
    };
    let mut run = actor
        .runtime_store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    let run = actor.runtime_store.save_automation_run(&run).await.unwrap();
    let workspace = prepare_fresh_shared_workspace(
        &actor.runtime_store,
        SharedWorkspaceCreateRequest {
            id: Some("owned".into()),
            project_id: "project".into(),
            name: Some("owned".into()),
            host_id: None,
            parent_workspace_id: None,
        },
    )
    .await
    .unwrap();
    let (mut run, _) = actor
        .runtime_store
        .allocate_automation_shared_workspace(&run, workspace)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Success;
    run.finished_at = Some(Utc::now());
    let run = actor.runtime_store.save_automation_run(&run).await.unwrap();
    (root, actor, run)
}

async fn mutation(actor: &mut ServerActor, run: &AutomationRun) -> RuntimeMutationRequest {
    let payload = json!({"automationCleanupRunId":run.id});
    let cleanup = actor
        .requested_automation_shared_cleanup("owned", &payload)
        .await
        .unwrap();
    let acquired = actor
        .checkout_buffer_guard_request(
            3,
            "workspace.bufferGuard.acquire",
            &json!({"id":"owned","operation":"removeShared"}),
        )
        .await
        .unwrap();
    let id = acquired["guardId"].as_str().unwrap();
    for client in [1, 2] {
        actor
            .acknowledge_buffer_guard(client, &json!({"guardId":id,"blockers":[]}))
            .unwrap();
    }
    let proof = actor
        .claim_checkout_buffer_guard(3, 9, "owned", "removeShared", &json!({"bufferGuardId":id}))
        .unwrap();
    RuntimeMutationRequest::RemoveSharedWorkspace {
        remote_automation_cleanup: None,
        automation_cleanup: cleanup,
        request: crate::managed_workspace::ManagedWorkspaceRemoveRequest {
            id: "owned".into(),
            close_sessions: true,
            delete_branch: Some(false),
            active_workspace_id: None,
        },
        buffer_guard: proof,
        remote_retirement: None,
    }
}

#[tokio::test]
async fn malformed_or_missing_run_never_falls_back_to_ordinary_removal() {
    let (_root, mut actor) = fixture().await;
    let mut session = crate::terminal_host::session::Session::driver_test_stub("session", 80, 24);
    session.workspace_id = "task".into();
    actor.sessions.insert("session".into(), session);
    for value in [
        json!(null),
        json!(false),
        json!(17),
        json!({}),
        json!(""),
        json!("  "),
        json!("missing"),
    ] {
        let error = actor
            .try_start_deferred_request(
                3,
                7,
                "workspace.removeShared",
                &json!({"id":"task","closeSessions":true,"automationCleanupRunId":value}),
            )
            .await
            .unwrap_err();
        assert!(
            error.to_string().contains("automationCleanupRunId")
                || error.to_string().contains("run no longer exists"),
            "{error}"
        );
        assert!(actor.sessions["session"].running());
        assert!(actor
            .runtime_store
            .find_workspace("task")
            .await
            .unwrap()
            .is_some());
        assert!(actor
            .runtime_store
            .find_workspace_tab("task-editor")
            .await
            .unwrap()
            .is_some());
        assert!(!actor.mutation_queue.has_runtime_mutations());
    }
}

#[tokio::test]
async fn successful_cleanup_still_requires_a_buffer_guard() {
    let (_root, mut actor, run) = successful().await;
    let error = actor
        .try_start_deferred_request(
            3,
            7,
            "workspace.removeShared",
            &json!({"id":"owned","closeSessions":true,"automationCleanupRunId":run.id}),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("buffer"), "{error}");
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn takeover_before_preparation_preserves_running_sessions() {
    let (_root, mut actor, mut run) = successful().await;
    let request = mutation(&mut actor, &run).await;
    let mut session = crate::terminal_host::session::Session::driver_test_stub("session", 80, 24);
    session.workspace_id = "owned".into();
    actor.sessions.insert("session".into(), session);
    run.taken_over = true;
    actor.runtime_store.save_automation_run(&run).await.unwrap();
    let error = actor
        .prepare_runtime_mutation(&request)
        .await
        .err()
        .unwrap();
    assert!(
        error.to_string().contains("Automation run changed"),
        "{error}"
    );
    assert!(actor.sessions["session"].running());
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn takeover_after_preparation_is_rejected_by_retirement_transaction() {
    let (_root, mut actor, mut run) = successful().await;
    let request = mutation(&mut actor, &run).await;
    actor.prepare_runtime_mutation(&request).await.unwrap();
    run.taken_over = true;
    actor.runtime_store.save_automation_run(&run).await.unwrap();
    let outcome = run_runtime_mutation(actor.runtime_store.clone(), request).await;
    assert!(outcome
        .result
        .err()
        .unwrap()
        .to_string()
        .contains("Automation run changed"));
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn verified_cleanup_preserves_shared_files_siblings_and_history() {
    let (root, mut actor, run) = successful().await;
    let file = root.path().join("notes.md");
    std::fs::write(&file, "uncommitted shared content").unwrap();
    let request = mutation(&mut actor, &run).await;
    actor.prepare_runtime_mutation(&request).await.unwrap();
    let outcome = run_runtime_mutation(actor.runtime_store.clone(), request).await;
    if let Err(error) = outcome.result {
        panic!("{error}");
    }
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_none());
    assert!(actor
        .runtime_store
        .find_workspace("sibling")
        .await
        .unwrap()
        .is_some());
    assert!(actor
        .runtime_store
        .find_workspace_tab("sibling-editor")
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        std::fs::read_to_string(file).unwrap(),
        "uncommitted shared content"
    );
    assert!(actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .is_some());
}

#[path = "automation_shared_cleanup_jobs_tests.rs"]
mod jobs;

#[tokio::test]
async fn ssh_tab_ownership_tracks_dispatch_and_rejects_a_different_bound_tab() {
    let (_root, actor, previous) = successful().await;
    let store = &actor.runtime_store;
    let definition = store
        .find_automation(&previous.automation_id)
        .await
        .unwrap()
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "ssh-owner-launch".into(),
        scheduled_at: Utc::now(),
        local_time: "2026-09-12T00:01".into(),
    };
    let mut run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    run.target_identity = Some(AutomationTargetIdentity {
        workspace_id: Some("owned".into()),
        tab_id: None,
        session_id: None,
        profile_id: None,
        conversation_id: None,
        terminal_handle: None,
    });
    let mut run = store.save_automation_run(&run).await.unwrap();
    let workspace = store.find_workspace("owned").await.unwrap().unwrap();
    crate::remote_owner_terminal_ownership::register_tab(
        store,
        &workspace,
        "dispatch-tab",
        "dispatch-session",
        Some(&run.id),
    )
    .await
    .unwrap();
    assert_eq!(
        crate::remote_owner_terminal_ownership::automation_run_id(
            store,
            &workspace,
            "dispatch-tab"
        )
        .await
        .unwrap(),
        Some(run.id.clone())
    );
    run.workspace_id = Some(workspace.id.clone());
    run.tab_id = Some("dispatch-tab".into());
    run.owned_tab = true;
    let mut run = store.save_automation_run(&run).await.unwrap();
    assert_eq!(
        crate::remote_owner_terminal_ownership::automation_run_id(
            store,
            &workspace,
            "dispatch-tab"
        )
        .await
        .unwrap(),
        Some(run.id.clone())
    );
    run.tab_id = Some("different-tab".into());
    store.save_automation_run(&run).await.unwrap();
    assert!(crate::remote_owner_terminal_ownership::automation_run_id(
        store,
        &workspace,
        "dispatch-tab"
    )
    .await
    .is_err());
    let sibling = store.find_workspace("sibling").await.unwrap().unwrap();
    assert!(crate::remote_owner_terminal_ownership::automation_run_id(
        store,
        &sibling,
        "dispatch-tab"
    )
    .await
    .is_err());
}
