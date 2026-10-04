use super::*;
use crate::terminal_host::session::{Session, SessionDriver};
use alera_core::runtime::{
    AutomationOccurrence, AutomationRecovery, AutomationRun, AutomationRunStatus,
    AutomationRunTrigger, WorkspaceTabRecord,
};

async fn owned_run(fixture: &mut Harness) -> AutomationRun {
    let definition = upsert_draft(&mut fixture.actor).await;
    let run = fixture
        .actor
        .runtime_store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual-test".into(),
                scheduled_at: Utc::now(),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    let mut run = fixture
        .actor
        .runtime_store
        .begin_automation_attempt(&run.id, 3)
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatched;
    run.workspace_id = Some("workspace-1".into());
    run.tab_id = Some("owned-tab".into());
    run.session_id = Some("owned-session".into());
    run.owned_tab = true;
    let run = fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap();
    fixture
        .actor
        .runtime_store
        .bind_automation_attempt(&run, "initial")
        .await
        .unwrap();
    fixture.actor.runtime_store.upsert_workspace_tab(WorkspaceTabRecord {id:"owned-tab".into(),workspace_id:"workspace-1".into(),kind:"terminal".into(),title:"Automation".into(),created_at:Utc::now(),updated_at:Utc::now(),payload:json!({"terminalSessionId":"owned-session","automationOwned":true,"automationRunId":run.id,"spawnOnCreate":true})}).await.unwrap();
    run
}

fn attach() -> serde_json::Value {
    json!({"sessionId":"owned-session","workspaceId":"workspace-1","tabId":"owned-tab","attachmentMode":"observe","workingDirectory":"/unused"})
}

#[tokio::test]
async fn partial_authoring_is_active_idempotent_and_patch_preserves_state() {
    let mut fixture = harness().await;
    let input = json!({"name":"Review","promptTemplate":"Review {{workspace.name}}","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"workspace-1","agentProfileId":"profile-1"}},"originWorkspaceId":"workspace-1"});
    let created = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.create",
            &json!({"automation":input,"requestKey":"same-key"}),
        )
        .await
        .unwrap();
    assert_eq!(created["state"], "active");
    assert_eq!(created["association"]["workspaceId"], "workspace-1");
    let repeated = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.create",
            &json!({"automation":input,"requestKey":"same-key"}),
        )
        .await
        .unwrap();
    assert_eq!(created["id"], repeated["id"]);
    let patched = fixture.actor.handle_automation_request(1,"automation.patch",&json!({"id":created["id"],"expectedRevision":1,"changes":{"promptTemplate":"New task"}})).await.unwrap();
    assert_eq!(patched["state"], "active");
    assert_eq!(patched["revision"], 2);
    assert!(fixture
        .actor
        .handle_automation_request(
            1,
            "automation.patch",
            &json!({"id":created["id"],"expectedRevision":1,"changes":{"name":"Stale"}})
        )
        .await
        .is_err());
}

#[tokio::test]
async fn readiness_reports_prompt_errors_without_saving() {
    let mut fixture = harness().await;
    let mut input = serde_json::to_value(draft_definition()).unwrap();
    input["promptTemplate"] = json!("Unknown {{unknown.name}}");
    let readiness = fixture
        .actor
        .handle_automation_request(1, "automation.readiness", &json!({"automation":input}))
        .await
        .unwrap();
    assert_eq!(readiness["ready"], false);
    assert_eq!(readiness["issues"][0]["field"], "promptTemplate");
    assert!(fixture
        .actor
        .runtime_store
        .list_automations(false)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn observing_live_terminal_never_takes_over_or_claims_viewport() {
    let mut fixture = harness().await;
    let run = owned_run(&mut fixture).await;
    let mut session = Session::driver_test_stub("owned-session", 120, 40);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "owned-tab".into();
    fixture.actor.sessions.insert(session.id.clone(), session);
    let before = fixture
        .actor
        .runtime_store
        .find_workspace_tab("owned-tab")
        .await
        .unwrap()
        .unwrap();
    let observed = fixture
        .actor
        .handle_request(1, "terminal.observe", &attach())
        .await
        .unwrap();
    assert_eq!(observed["readOnly"], true);
    assert!(fixture
        .actor
        .queue_terminal_input(
            1,
            7,
            &json!({"sessionId":"owned-session","dataBase64":"YQ=="})
        )
        .is_err());
    assert!(fixture
        .actor
        .handle_request(1, "terminate", &json!({"sessionId":"owned-session"}))
        .await
        .is_err());
    assert!(fixture
        .actor
        .handle_request(1, "terminal.restart", &json!({"sessionId":"owned-session"}))
        .await
        .is_err());
    assert!(fixture
        .actor
        .handle_request(
            1,
            "resize",
            &json!({"sessionId":"owned-session","cols":10,"rows":10})
        )
        .await
        .is_err());
    assert!(fixture
        .actor
        .handle_request(1, "terminal.reclaim", &json!({"sessionId":"owned-session"}))
        .await
        .is_err());
    fixture.actor.claim_mobile_terminal_viewport(
        1,
        "owned-session",
        &json!({"cols":10,"rows":10}),
        &mut json!({}),
    );
    let session = &fixture.actor.sessions["owned-session"];
    assert_eq!(session.current_dims, (120, 40));
    assert_eq!(session.driver, SessionDriver::Idle);
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_workspace_tab("owned-tab")
            .await
            .unwrap()
            .unwrap()
            .updated_at,
        before.updated_at
    );
    assert!(
        !fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .taken_over
    );
}

#[tokio::test]
async fn observing_exited_terminal_restores_checkpoint_without_spawn() {
    let mut fixture = harness().await;
    owned_run(&mut fixture).await;
    let mut session = Session::driver_test_stub("owned-session", 80, 24);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "owned-tab".into();
    session.append_output(b"retained output");
    session.terminate(false, &fixture.actor.store).await;
    assert!(fixture.actor.sessions.is_empty());
    let observed = fixture.actor.create_or_attach(1, &attach()).await.unwrap();
    assert_eq!(observed["readOnly"], true);
    assert!(!fixture.actor.sessions["owned-session"].running());
    assert!(fixture.actor.sessions["owned-session"].shell().is_none());
    fixture.actor.sessions.clear();
    fixture.actor.store.delete("owned-session").await.unwrap();
    assert!(fixture
        .actor
        .create_or_attach(1, &attach())
        .await
        .unwrap_err()
        .to_string()
        .contains("No terminal output retained"));
    assert!(fixture.actor.sessions.is_empty());
}

#[tokio::test]
async fn mobile_observe_forwards_mode_and_preserves_driver() {
    let mut fixture = harness().await;
    let run = owned_run(&mut fixture).await;
    let mut session = Session::driver_test_stub("owned-session", 120, 40);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "owned-tab".into();
    fixture.actor.sessions.insert(session.id.clone(), session);
    let client = fixture.actor.clients.get_mut(&1).unwrap();
    client.kind = super::super::ClientKind::Mobile;
    client.mobile_device_id = Some("phone".into());
    let observed = fixture
        .actor
        .attach_mobile_terminal(
            1,
            &json!({"tabId":"owned-tab","attachmentMode":"observe","cols":10,"rows":10}),
        )
        .await
        .unwrap();
    assert!(!observed.is_null());
    assert!(fixture.actor.sessions["owned-session"]
        .observer_clients
        .contains(&1));
    assert_eq!(
        fixture.actor.sessions["owned-session"].current_dims,
        (120, 40)
    );
    assert!(
        !fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .taken_over
    );
}

#[tokio::test]
async fn explicit_and_legacy_takeover_persist_the_tab_signal() {
    for explicit in [true, false] {
        let mut fixture = harness().await;
        fixture.actor.clients.get_mut(&1).unwrap().local_role =
            super::super::client_delivery::LocalClientRole::App;
        let mut run = owned_run(&mut fixture).await;
        run.recovery = Some(AutomationRecovery {
            status: "resuming".into(),
            attempt: 1,
            max_attempts: 3,
            interrupted_at: None,
            code: None,
        });
        fixture
            .actor
            .runtime_store
            .save_automation_run(&run)
            .await
            .unwrap();
        let mut session = Session::driver_test_stub("owned-session", 80, 24);
        session.workspace_id = "workspace-1".into();
        session.tab_id = "owned-tab".into();
        fixture.actor.sessions.insert(session.id.clone(), session);
        fixture.actor.create_or_attach(1, &attach()).await.unwrap();
        if explicit {
            fixture
                .actor
                .handle_automation_request(1, "automation.takeOver", &json!({"runId":run.id}))
                .await
                .unwrap();
        } else {
            let mut payload = attach();
            payload.as_object_mut().unwrap().remove("attachmentMode");
            fixture.actor.create_or_attach(1, &payload).await.unwrap();
        }
        let taken = fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap();
        assert!(taken.taken_over);
        assert_eq!(taken.recovery.unwrap().status, "stoppedByTakeover");
        assert_eq!(
            fixture
                .actor
                .runtime_store
                .find_workspace_tab("owned-tab")
                .await
                .unwrap()
                .unwrap()
                .payload["automationTakenOver"],
            true
        );
        assert!(fixture
            .actor
            .require_terminal_writer(1, "owned-session")
            .is_ok());
    }
}

#[tokio::test]
async fn obsolete_attempt_callback_is_rejected_before_mutation() {
    let mut fixture = harness().await;
    let mut run = owned_run(&mut fixture).await;
    run.attempt_count = 2;
    fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap();
    fixture.actor.clients.get_mut(&1).unwrap().local_role =
        super::super::client_delivery::LocalClientRole::Cli;
    let error = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.complete",
            &json!({"run":run.id,"attemptId":"old","status":"success","summary":"stale"}),
        )
        .await
        .unwrap_err();
    assert!(error.to_string().contains("superseded"));
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        AutomationRunStatus::Dispatched
    );
}

#[tokio::test]
async fn interrupted_manual_run_recovers_while_definition_is_paused() {
    let mut fixture = harness().await;
    let mut run = owned_run(&mut fixture).await;
    run.owner_process = Some(alera_core::runtime::AutomationProcessIdentity {
        pid: u32::MAX,
        start_marker: 1,
        boot_id: None,
    });
    fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap();
    fixture
        .actor
        .runtime_store
        .set_automation_state(
            &run.automation_id,
            AutomationState::Paused,
            draft_definition().created_by,
            None,
        )
        .await
        .unwrap();
    fixture.actor.reconcile_automation_runs().await;
    let recovered = fixture
        .actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, AutomationRunStatus::Pending);
    assert_eq!(recovered.attempt_count, 1);
    assert_eq!(recovered.absolute_deadline_at, run.absolute_deadline_at);
    assert!((recovered.retry_after.unwrap() - Utc::now()).num_seconds() >= 58);
    assert!(recovered.recovery.is_some());
}

#[tokio::test]
async fn unverified_owner_keeps_target_reserved_after_absolute_timeout() {
    let mut fixture = harness().await;
    let mut run = owned_run(&mut fixture).await;
    run.absolute_deadline_at = Some(Utc::now() - chrono::Duration::seconds(1));
    fixture
        .actor
        .runtime_store
        .save_automation_run(&run)
        .await
        .unwrap();
    fixture.actor.reconcile_automation_runs().await;
    fixture.actor.expire_inactive_automation_runs().await;
    let timed_out = fixture
        .actor
        .runtime_store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(timed_out.status, AutomationRunStatus::Timeout);
    assert!(timed_out.owner_reserved);
    assert!(
        fixture
            .actor
            .automation_target_is_reserved(
                timed_out.definition_snapshot.as_ref().unwrap(),
                "new-run"
            )
            .await
    );
    assert!(!fixture
        .actor
        .runtime_store
        .reserved_automation_runs()
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn terminal_exit_preserves_automation_tab_output_and_schedules_recovery() {
    let mut fixture = harness().await;
    let run = owned_run(&mut fixture).await;
    let mut session = Session::driver_test_stub("owned-session", 80, 24);
    session.workspace_id = "workspace-1".into();
    session.tab_id = "owned-tab".into();
    session.append_output(b"attempt diagnostics");
    fixture.actor.sessions.insert(session.id.clone(), session);
    fixture
        .actor
        .handle_session_exit("owned-session".into(), 1)
        .await;
    assert!(fixture
        .actor
        .runtime_store
        .find_workspace_tab("owned-tab")
        .await
        .unwrap()
        .is_some());
    assert!(!fixture.actor.sessions["owned-session"].running());
    fixture.actor.reconcile_automation_runs().await;
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        AutomationRunStatus::Pending
    );
    assert_eq!(
        fixture.actor.create_or_attach(1, &attach()).await.unwrap()["readOnly"],
        true
    );
}

#[path = "automation_catalog_experience_tests.rs"]
mod catalog;

#[path = "automation_authoring_retry_tests.rs"]
mod authoring_retry;
