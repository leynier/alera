use super::*;
use std::time::Duration;

#[path = "automation_ssh_precheck_tests.rs"]
mod ssh_owner;

#[cfg(target_os = "linux")]
#[path = "automation_precheck_recovery_tests.rs"]
mod reboot_recovery;

#[path = "automation_precheck_shutdown_retry_tests.rs"]
mod shutdown_retry;

#[cfg(unix)]
#[path = "automation_owner_precheck_execution_tests.rs"]
mod owner_execution;

#[cfg(unix)]
#[path = "automation_owner_precheck_rpc_tests.rs"]
mod owner_rpc;

#[tokio::test]
async fn missing_precheck_worker_retains_unverified_process_evidence() {
    let (mut fixture, mut definition) = empty_project().await;
    definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
        command: "fixture-never-executed".into(),
        timeout_seconds: 10,
    });
    let store = fixture.actor.runtime_store.clone();
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let mut run = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "lost-precheck-worker".into(),
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
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            "unverified-launch",
            "linux",
            Some("fixture-boot".into()),
        )
        .await
        .unwrap();
    store
        .request_automation_cancel(&run.id, definition.created_by.clone())
        .await
        .unwrap();
    // No native process is spawned. The persisted intent models the crash gap.
    fixture
        .actor
        .handle(crate::terminal_host::server::ServerCommand::AutomationTick)
        .await;
    let retained = store.find_automation_run(&run.id).await.unwrap().unwrap();
    assert_eq!(retained.status, AutomationRunStatus::WaitingForUser);
    fixture
        .actor
        .finish_automation_precheck(
            definition,
            run.clone(),
            "local".into(),
            intent.path.clone(),
            Ok(true),
        )
        .await;
    assert_eq!(
        store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        AutomationRunStatus::WaitingForUser
    );
    assert_eq!(store.list_active_automation_runs().await.unwrap().len(), 1);
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
    assert_eq!(
        store.automation_precheck_processes(&run.id).await.unwrap(),
        vec![intent]
    );
}

#[cfg(unix)]
#[tokio::test]
async fn cancellation_keeps_dependency_reserved_while_precheck_command_is_running() {
    let (mut fixture, mut definition) = empty_project().await;
    declare(&fixture.repo_path);
    let ready = fixture.repo_path.join("precheck-ready");
    let release = fixture.repo_path.join("precheck-release");
    definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
        command: format!(
            "sleep 60 & printf %s \"$!\" > {}; while [ ! -f {} ]; do sleep 0.02; done",
            crate::ssh_bootstrap::shell_quote(ready.to_str().unwrap()),
            crate::ssh_bootstrap::shell_quote(release.to_str().unwrap())
        ),
        timeout_seconds: 30,
    });
    definition.overlap_policy = alera_core::runtime::AutomationOverlapPolicy::Skip;
    let store = fixture.actor.runtime_store.clone();
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let occurrence = AutomationOccurrence {
        automation_id: definition.id.clone(),
        key: "running-command".into(),
        scheduled_at: Utc::now(),
        local_time: "fixture".into(),
    };
    let run = store
        .create_automation_run(&definition, &occurrence, AutomationRunTrigger::Scheduled)
        .await
        .unwrap();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    fixture.actor.inbox = inbox;
    fixture
        .actor
        .start_automation_run(&definition, run.clone(), true)
        .await;
    let reached_command = tokio::time::timeout(Duration::from_secs(3), async {
        while std::fs::read_to_string(&ready)
            .ok()
            .and_then(|value| value.parse::<u32>().ok())
            .is_none()
        {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .is_ok();
    let descendant = std::fs::read_to_string(&ready)
        .ok()
        .and_then(|value| value.parse::<u32>().ok());
    let cancellation_started = tokio::time::Instant::now();
    store
        .request_automation_cancel(&run.id, definition.created_by.clone())
        .await
        .unwrap();
    fixture
        .actor
        .handle(crate::terminal_host::server::ServerCommand::AutomationTick)
        .await;
    let during = store.find_automation_run(&run.id).await.unwrap().unwrap();
    let successor = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                key: "next-command".into(),
                ..occurrence
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    fixture
        .actor
        .start_automation_run(&definition, successor.clone(), true)
        .await;
    let next_status = store
        .find_automation_run(&successor.id)
        .await
        .unwrap()
        .unwrap()
        .status;
    store
        .request_automation_cancel(&successor.id, definition.created_by.clone())
        .await
        .unwrap();
    // Do not release the fixture command: cancellation must close its tree.
    // On a failed deadline, release it and drain cleanup before asserting.
    let mut completed_without_release = true;
    while !fixture.actor.automation_precheck_jobs.is_empty() {
        let completion = match tokio::time::timeout(Duration::from_secs(15), commands.recv()).await
        {
            Ok(completion) => completion.unwrap(),
            Err(_) => {
                completed_without_release = false;
                std::fs::write(&release, "release").unwrap();
                tokio::time::timeout(Duration::from_secs(45), commands.recv())
                    .await
                    .unwrap()
                    .unwrap()
            }
        };
        fixture.actor.handle(completion).await;
    }
    let after = store.find_automation_run(&run.id).await.unwrap().unwrap();
    assert!(reached_command);
    assert!(completed_without_release);
    assert!(cancellation_started.elapsed() < Duration::from_secs(15));
    use crate::process_identity::{
        ProcessIdentityProbe, ProcessLookup, SystemProcessIdentityProbe,
    };
    assert!(matches!(
        SystemProcessIdentityProbe.lookup(descendant.unwrap()),
        ProcessLookup::Exited
    ));
    let evidence = store.automation_precheck_processes(&run.id).await.unwrap();
    assert_eq!(evidence.len(), 1);
    assert_eq!(
        evidence[0].phase,
        alera_core::runtime::WorkspaceProcessJobPhase::ClosureVerified
    );
    assert_eq!(during.status, AutomationRunStatus::Dispatching);
    assert_eq!(next_status, AutomationRunStatus::OverlapSkipped);
    assert_eq!(after.status, AutomationRunStatus::Cancelled);
    assert_eq!(after.attempt_count, 0);
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
    assert!(fixture.actor.automation_precheck_jobs.is_empty());
}

struct Declaration(Option<bool>);
impl crate::ssh_remote::RemoteHostExecutor for Declaration {
    async fn probe_windows(&self, _: &alera_core::runtime::SshTarget) -> Option<bool> {
        Some(false)
    }
    async fn run(
        &self,
        _: &alera_core::runtime::SshTarget,
        _: bool,
        _: &str,
    ) -> anyhow::Result<String> {
        Ok(json!({"version":1,"path":"/fixture/remote","kind":"folder","branch":null,"automationDeclared":self.0}).to_string())
    }
}

#[tokio::test]
async fn remote_precheck_command_is_not_polled_without_repository_authorization() {
    let (fixture, mut definition) = empty_project().await;
    let store = &fixture.actor.runtime_store;
    store.upsert_ssh_target(serde_json::from_value(json!({
        "id":"ssh", "alias":"Fixture", "host":"fixture.invalid", "port":22,
        "username":"fixture", "authKind":"agent", "createdAt":Utc::now(), "updatedAt":Utc::now(),
        "installDir":"/fixture/sidecar", "bootstrapStatus":"installed"
    })).unwrap()).await.unwrap();
    store
        .register_project_checkout("project-1", "ssh", "/fixture/remote")
        .await
        .unwrap();
    if let AutomationTarget::ProjectCheckout { host_id, .. } = &mut definition.target {
        *host_id = "ssh".into();
    }
    let definition = store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let mut run = store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "authorization".into(),
                scheduled_at: Utc::now(),
                local_time: "fixture".into(),
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    run.status = AutomationRunStatus::Dispatching;
    let run = store.save_automation_run(&run).await.unwrap();
    for declaration in [None, Some(false), Some(true)] {
        let polled = std::cell::Cell::new(false);
        let result = crate::terminal_host::server::automation_dispatch::automation_precheck_authorization::execute_authorized_precheck(
            store, &definition, &run, "ssh", "/fixture/remote", &Declaration(declaration), async {
                polled.set(true);
                Ok(true)
            },
        ).await;
        assert_eq!(result.is_ok(), declaration == Some(true));
        assert_eq!(polled.get(), declaration == Some(true));
    }
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
}

#[tokio::test]
async fn deferred_precheck_revalidates_before_allocation_and_preserves_attempt_count() {
    for scenario in [
        "skip", "failure", "edit", "location", "cancel", "policy", "restart",
    ] {
        let (mut fixture, mut definition) = empty_project().await;
        declare(&fixture.repo_path);
        definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
            command: "exit 1".into(),
            timeout_seconds: 5,
        });
        let store = fixture.actor.runtime_store.clone();
        let definition = store
            .upsert_automation(definition.clone(), definition.created_by.clone())
            .await
            .unwrap();
        let run = store
            .create_automation_run(
                &definition,
                &AutomationOccurrence {
                    automation_id: definition.id.clone(),
                    key: scenario.into(),
                    scheduled_at: Utc::now(),
                    local_time: "fixture".into(),
                },
                AutomationRunTrigger::Scheduled,
            )
            .await
            .unwrap();
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
        fixture.actor.inbox = inbox;
        fixture
            .actor
            .start_automation_run(&definition, run.clone(), true)
            .await;
        assert!(
            fixture.actor.automation_precheck_jobs.contains(&run.id),
            "{scenario}"
        );
        let reserved = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(reserved.status, AutomationRunStatus::Dispatching);
        assert_eq!(reserved.attempt_count, 0);
        match scenario {
            "edit" => {
                let mut edited = definition.clone();
                edited.prompt_template.push_str(" edited");
                store
                    .upsert_automation(edited, definition.created_by.clone())
                    .await
                    .unwrap();
            }
            "cancel" => {
                store
                    .request_automation_cancel(&run.id, definition.created_by.clone())
                    .await
                    .unwrap();
            }
            "policy" => {
                store
                    .set_automation_agent_policy(AutomationAgentPolicy {
                        profile_id: "profile-1".into(),
                        may_execute: false,
                        may_activate_or_edit_active: false,
                        updated_at: Utc::now(),
                    })
                    .await
                    .unwrap();
            }
            _ => {}
        }
        let mut command = tokio::time::timeout(Duration::from_secs(10), commands.recv())
            .await
            .unwrap()
            .unwrap();
        if scenario == "location" {
            let other = fixture.repo_path.join("moved");
            std::fs::create_dir(&other).unwrap();
            // Closure is verified, but the actor has not allocated the task yet.
            sqlx::query("UPDATE repositoryCheckouts SET path = ? WHERE projectId = 'project-1' AND hostId = 'local' AND kind = 'project'")
                .bind(other.to_str().unwrap()).execute(store.pool()).await.unwrap();
        }
        if let crate::terminal_host::server::ServerCommand::AutomationPrecheckFinished {
            result,
            ..
        } = &mut command
        {
            if matches!(scenario, "skip" | "failure" | "restart") {
                assert!(matches!(result, Ok(false)), "{scenario}: {result:?}");
            } else {
                assert!(
                    !matches!(result, Ok(true)),
                    "changed reservations cannot pass"
                );
            }
            if scenario == "failure" {
                *result = Err("automation precheck timed out".into());
            } else if scenario != "skip" {
                *result = Ok(true);
            }
        } else {
            panic!("expected precheck completion");
        }
        if scenario == "restart" {
            fixture.actor.automation_precheck_jobs.clear();
            assert!(
                fixture
                    .actor
                    .recover_interrupted_automation_precheck(&reserved)
                    .await
            );
        }
        fixture.actor.handle(command).await;
        let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(
            current.status,
            match scenario {
                "skip" | "failure" => AutomationRunStatus::PrecheckSkipped,
                "cancel" => AutomationRunStatus::Cancelled,
                _ => AutomationRunStatus::Blocked,
            },
            "{scenario}"
        );
        assert_eq!(current.attempt_count, 0, "{scenario}");
        assert!(current.workspace_id.is_none());
        assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
        assert!(fixture.actor.automation_precheck_jobs.is_empty());
    }
}
