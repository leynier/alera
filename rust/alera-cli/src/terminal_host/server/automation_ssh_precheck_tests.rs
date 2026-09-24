use super::*;
use alera_core::runtime::{
    AutomationPrecheckProcess, AutomationRun, OwnerAutomationPrecheck,
    OwnerAutomationPrecheckOutcome, RuntimeStore, WorkspaceProcessJobPhase,
};
use base64::Engine;
use std::sync::Mutex;

struct Owner {
    store: RuntimeStore,
    run: AutomationRun,
    actor: alera_core::runtime::AutomationActor,
    scenario: &'static str,
    calls: Mutex<Vec<(String, String)>>,
}

impl crate::ssh_remote::RemoteHostExecutor for Owner {
    async fn probe_windows(&self, _: &alera_core::runtime::SshTarget) -> Option<bool> {
        panic!("The persisted bootstrap platform must avoid actor-side SSH probing")
    }
    async fn run(
        &self,
        _: &alera_core::runtime::SshTarget,
        windows: bool,
        script: &str,
    ) -> anyhow::Result<String> {
        let encoded = script
            .split("--metadata-base64 '")
            .nth(1)
            .unwrap()
            .split('\'')
            .next()
            .unwrap();
        let envelope: crate::remote_owner_precheck::OwnerPrecheckEnvelope = serde_json::from_slice(
            &base64::engine::general_purpose::STANDARD
                .decode(encoded)
                .unwrap(),
        )
        .unwrap();
        let action = script
            .split("--action ")
            .nth(1)
            .unwrap()
            .split_whitespace()
            .next()
            .unwrap()
            .to_string();
        let count = {
            let mut calls = self.calls.lock().unwrap();
            calls.push((action.clone(), envelope.request.operation_id.clone()));
            calls.len()
        };
        assert!(script.contains("project control-owner-precheck"));
        assert!(!script.contains("fixture-never-run-directly"));
        assert_eq!(windows, self.scenario == "windows");
        if windows {
            assert!(script.contains("alera.exe"));
        } else {
            assert!(script.contains("exec \"$install/current/alera\""));
        }
        let records = self
            .store
            .automation_precheck_processes(&self.run.id)
            .await
            .unwrap();
        assert_eq!(records.len(), 1);
        let home = &records[0];
        assert_eq!(home.remote_owner_request().unwrap(), envelope.request);
        assert!(self
            .store
            .update_automation_run_status(&self.run.id, AutomationRunStatus::Cancelled, None)
            .await
            .is_err());
        if self.scenario == "lost" && count == 1 {
            anyhow::bail!("injected lost Start response");
        }
        let process_id = format!("owner-precheck:{}", home.id);
        let mut job = OwnerAutomationPrecheck {
            request: envelope.request,
            cancel_requested: action == "cancel",
            process_id: Some(process_id.clone()),
            outcome: Some(OwnerAutomationPrecheckOutcome::Passed),
            attention: None,
        };
        let mut process = AutomationPrecheckProcess {
            id: process_id.clone(),
            run_id: process_id,
            host_id: "local".into(),
            phase: WorkspaceProcessJobPhase::ClosureVerified,
            pid: Some(42),
            start_marker: Some(123),
            ..home.clone()
        };
        if self.scenario == "lost" {
            if count == 2 {
                job.outcome = None;
                process.phase = WorkspaceProcessJobPhase::Spawned;
                self.store
                    .request_automation_cancel(&self.run.id, self.actor.clone())
                    .await
                    .unwrap();
            } else {
                assert_eq!(action, "cancel");
                job.outcome = Some(OwnerAutomationPrecheckOutcome::Cancelled);
            }
        }
        if self.scenario == "wrong" {
            process.path = "/wrong-checkout".into();
        }
        Ok(json!({"version":1,"job":job,"processes":[process]}).to_string())
    }
}

async fn remote_fixture(platform: &str) -> (Harness, AutomationDefinition, AutomationRun) {
    let (fixture, mut definition) = empty_project().await;
    let store = &fixture.actor.runtime_store;
    store.upsert_ssh_target(serde_json::from_value(json!({
        "id":"ssh", "alias":"Fixture", "host":"fixture.invalid", "port":22,
        "username":"fixture", "authKind":"agent", "createdAt":Utc::now(), "updatedAt":Utc::now(),
        "installDir":"/fixture/sidecar", "bootstrapStatus":"installed", "runtimePlatform":platform
    })).unwrap()).await.unwrap();
    store
        .register_project_checkout("project-1", "ssh", "/fixture/remote")
        .await
        .unwrap();
    if let AutomationTarget::ProjectCheckout { host_id, .. } = &mut definition.target {
        *host_id = "ssh".into();
    }
    definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
        command: "fixture-never-run-directly".into(),
        timeout_seconds: 10,
    });
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let mut run = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "remote-owner".into(),
                scheduled_at: Utc::now(),
                local_time: "fixture".into(),
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    run.precheck = Some(true);
    let run = store.save_automation_run(&run).await.unwrap();
    (fixture, definition, run)
}

#[tokio::test]
async fn ssh_precheck_uses_stable_owner_identity_after_lost_start_and_cancels_with_proof() {
    let (fixture, definition, run) = remote_fixture("linux").await;
    let store = &fixture.actor.runtime_store;
    let owner = Owner {
        store: store.clone(),
        run: run.clone(),
        actor: definition.created_by.clone(),
        scenario: "lost",
        calls: Mutex::new(Vec::new()),
    };
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        crate::automation_ssh_precheck::run_remote_precheck(
            store,
            &definition,
            &run,
            "ssh",
            "/fixture/remote",
            &owner,
        ),
    )
    .await
    .unwrap();
    assert!(result.unwrap_err().contains("cancelled"));
    {
        let calls = owner.calls.lock().unwrap();
        assert_eq!(
            calls.iter().map(|call| call.0.as_str()).collect::<Vec<_>>(),
            ["start", "start", "cancel"]
        );
        assert!(calls.iter().all(|call| call.1 == calls[0].1));
    }
    assert_eq!(
        store.automation_precheck_processes(&run.id).await.unwrap()[0].phase,
        WorkspaceProcessJobPhase::ClosureVerified
    );
    assert!(store
        .find_automation_run(&run.id)
        .await
        .unwrap()
        .unwrap()
        .cancel_requested_at
        .is_some());
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
}

#[tokio::test]
async fn ssh_precheck_replays_verified_result_without_transport_on_each_platform() {
    for platform in ["linux", "macos", "windows"] {
        let (fixture, definition, run) = remote_fixture(platform).await;
        let store = &fixture.actor.runtime_store;
        let owner = Owner {
            store: store.clone(),
            run: run.clone(),
            actor: definition.created_by.clone(),
            scenario: platform,
            calls: Mutex::new(Vec::new()),
        };
        for _ in 0..2 {
            assert!(crate::automation_ssh_precheck::run_remote_precheck(
                store,
                &definition,
                &run,
                "ssh",
                "/fixture/remote",
                &owner
            )
            .await
            .unwrap());
        }
        assert_eq!(owner.calls.lock().unwrap().len(), 1);
        assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
    }
}

#[tokio::test]
async fn ssh_precheck_rejects_mismatched_closure_without_releasing_run_dependencies() {
    let (fixture, definition, run) = remote_fixture("linux").await;
    let store = &fixture.actor.runtime_store;
    let owner = Owner {
        store: store.clone(),
        run: run.clone(),
        actor: definition.created_by.clone(),
        scenario: "wrong",
        calls: Mutex::new(Vec::new()),
    };
    assert!(crate::automation_ssh_precheck::run_remote_precheck(
        store,
        &definition,
        &run,
        "ssh",
        "/fixture/remote",
        &owner
    )
    .await
    .unwrap_err()
    .contains("does not prove closure"));
    let intent = store
        .automation_precheck_processes(&run.id)
        .await
        .unwrap()
        .remove(0);
    assert_eq!(intent.phase, WorkspaceProcessJobPhase::LaunchIntent);
    assert!(store
        .remote_precheck_result(&intent.id)
        .await
        .unwrap()
        .is_none());
    assert!(store
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .is_err());
}

#[tokio::test]
async fn ssh_precheck_recovery_queries_existing_intent_without_repeating_start() {
    let (fixture, definition, run) = remote_fixture("linux").await;
    let store = &fixture.actor.runtime_store;
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let owner = Owner {
        store: store.clone(),
        run: run.clone(),
        actor: definition.created_by.clone(),
        scenario: "linux",
        calls: Mutex::new(Vec::new()),
    };
    assert!(crate::automation_ssh_precheck::run_remote_precheck(
        store,
        &definition,
        &run,
        "ssh",
        "/fixture/remote",
        &owner
    )
    .await
    .unwrap());
    assert_eq!(
        *owner.calls.lock().unwrap(),
        vec![("status".into(), intent.id)]
    );
}

#[tokio::test]
async fn ssh_precheck_actor_recovers_receipt_without_dispatching_a_changed_definition() {
    for cancel in [false, true] {
        let (mut fixture, mut definition, run) = remote_fixture("linux").await;
        let store = fixture.actor.runtime_store.clone();
        let owner = Owner {
            store: store.clone(),
            run: run.clone(),
            actor: definition.created_by.clone(),
            scenario: "linux",
            calls: Mutex::new(Vec::new()),
        };
        assert!(crate::automation_ssh_precheck::run_remote_precheck(
            &store,
            &definition,
            &run,
            "ssh",
            "/fixture/remote",
            &owner
        )
        .await
        .unwrap());
        definition.precheck = None;
        store
            .upsert_automation(definition.clone(), definition.created_by.clone())
            .await
            .unwrap();
        // Cached closure must remain usable when the owner is not bootstrapped
        // or reachable anymore. This fixture must never open a real connection.
        let mut target = store.find_ssh_target("ssh").await.unwrap().unwrap();
        target.bootstrap_status = alera_core::runtime::SshBootstrapStatus::NotInstalled;
        store.upsert_ssh_target(target).await.unwrap();
        if cancel {
            store
                .request_automation_cancel(&run.id, definition.created_by.clone())
                .await
                .unwrap();
        }
        let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
        let (sender, mut inbox) = tokio::sync::mpsc::unbounded_channel();
        fixture.actor.inbox = sender;
        assert!(
            fixture
                .actor
                .resume_remote_automation_precheck(&current)
                .await
        );
        let completed = tokio::time::timeout(Duration::from_secs(5), inbox.recv())
            .await
            .unwrap()
            .unwrap();
        assert!(matches!(
            completed,
            crate::terminal_host::server::ServerCommand::AutomationPrecheckFinished { .. }
        ));
        fixture.actor.handle(completed).await;
        let after = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(
            after.status,
            if cancel {
                AutomationRunStatus::Cancelled
            } else {
                AutomationRunStatus::Blocked
            }
        );
        assert_eq!(after.attempt_count, 0);
        assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
        assert!(fixture.actor.automation_precheck_jobs.is_empty());
    }
}

#[tokio::test]
async fn cli_precheck_cancel_requires_exact_human_target_and_preserves_process_fence() {
    for scenario in [
        "human",
        "planned-agent",
        "wrong-target",
        "managed",
        "started",
        "no-precheck",
    ] {
        let (mut fixture, definition, mut run) = remote_fixture("linux").await;
        let store = fixture.actor.runtime_store.clone();
        fixture.actor.clients.get_mut(&1).unwrap().local_role =
            crate::terminal_host::server::client_delivery::LocalClientRole::Cli;
        let target = alera_core::runtime::AutomationTargetIdentity {
            profile_id: Some("profile-1".into()),
            workspace_id: None,
            tab_id: None,
            session_id: None,
            conversation_id: None,
            terminal_handle: None,
        };
        run.target_identity = Some(target.clone());
        match scenario {
            "managed" => {
                run.actor_kind = Some(alera_core::runtime::AutomationActorKind::ManagedAgent);
                run.started_at = Some(Utc::now());
            }
            "planned-agent" => {
                run.actor_kind = Some(alera_core::runtime::AutomationActorKind::ManagedAgent);
            }
            "started" => run.started_at = Some(Utc::now()),
            "no-precheck" => run.precheck = None,
            _ => {}
        }
        let run = store.save_automation_run(&run).await.unwrap();
        if matches!(scenario, "human" | "planned-agent") {
            store
                .begin_automation_precheck_process(
                    &run,
                    &definition,
                    &uuid::Uuid::new_v4().to_string(),
                    "linux",
                    None,
                )
                .await
                .unwrap();
        }
        let mut supplied = target.clone();
        if scenario == "wrong-target" {
            supplied.profile_id = Some("another-profile".into());
        }
        let response = fixture
            .actor
            .handle_request(
                1,
                "automation.cancel",
                &json!({"run":run.id,"targetIdentity":supplied}),
            )
            .await;
        assert_eq!(
            response.is_ok(),
            matches!(scenario, "human" | "planned-agent"),
            "{scenario}: {response:?}"
        );
        let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(
            current.cancel_requested_at.is_some(),
            matches!(scenario, "human" | "planned-agent")
        );
        if matches!(scenario, "human" | "planned-agent") {
            assert_eq!(current.status, AutomationRunStatus::Dispatching);
            assert!(store
                .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
                .await
                .is_err());
            assert!(fixture
                .actor
                .handle_request(
                    1,
                    "automation.heartbeat",
                    &json!({"run":run.id,"targetIdentity":target})
                )
                .await
                .is_err());
        }
    }
}
