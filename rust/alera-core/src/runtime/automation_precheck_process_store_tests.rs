use super::*;
use crate::runtime::{AutomationPrecheck, WorkspaceProcessJobPhase};

#[path = "remote_automation_precheck_result_store_tests.rs"]
mod remote_results;

#[path = "automation_precheck_workspace_store_tests.rs"]
mod workspace_scope;

#[tokio::test]
async fn precheck_reboot_recovery_requires_a_different_boot_from_the_owner() {
    use WorkspaceProcessJobPhase::{ClosureVerified, LaunchIntent, RootExited, Spawned};
    let old_boot = uuid::Uuid::new_v4().to_string();
    let new_boot = uuid::Uuid::new_v4().to_string();
    for phase in [LaunchIntent, Spawned, RootExited] {
        let (directory, store, definition, run) = prepared().await;
        let mut record = store
            .begin_automation_precheck_process(
                &run,
                &definition,
                "operation",
                "linux",
                Some(old_boot.clone()),
            )
            .await
            .unwrap();
        if phase != LaunchIntent {
            record = store
                .record_automation_precheck_spawn(&record, 123, Some(456))
                .await
                .unwrap();
        }
        if phase == RootExited {
            record = store
                .record_automation_precheck_phase(&record, RootExited)
                .await
                .unwrap();
        }
        for boot in [
            &old_boot,
            "invalid",
            "",
            "00000000-0000-0000-0000-000000000000",
        ] {
            assert!(store
                .close_automation_precheck_from_previous_boot(&record, boot)
                .await
                .is_err());
        }
        for unsupported in [
            crate::runtime::AutomationPrecheckProcess {
                host_id: "ssh".into(),
                ..record.clone()
            },
            crate::runtime::AutomationPrecheckProcess {
                platform: "windows".into(),
                ..record.clone()
            },
            crate::runtime::AutomationPrecheckProcess {
                boot_id: None,
                ..record.clone()
            },
        ] {
            assert!(store
                .close_automation_precheck_from_previous_boot(&unsupported, &new_boot)
                .await
                .is_err());
        }
        let closed = store
            .close_automation_precheck_from_previous_boot(&record, &new_boot)
            .await
            .unwrap();
        assert_eq!(closed.phase, ClosureVerified);
        assert_eq!(closed.closure_boot_id.as_deref(), Some(new_boot.as_str()));
        assert_eq!(closed.boot_id, record.boot_id);
        assert!(store
            .close_automation_precheck_from_previous_boot(&record, &new_boot)
            .await
            .is_err());
        store
            .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
            .await
            .unwrap();
        store.pool().close().await;
        let reopened = RuntimeStore::open(directory.path()).await.unwrap();
        assert_eq!(
            reopened
                .automation_precheck_processes(&run.id)
                .await
                .unwrap(),
            vec![closed]
        );
    }
}

async fn prepared() -> (TempDir, RuntimeStore, AutomationDefinition, AutomationRun) {
    prepared_for_host("local").await
}

async fn prepared_for_host(
    host: &str,
) -> (TempDir, RuntimeStore, AutomationDefinition, AutomationRun) {
    let (directory, store, project) = crate::runtime::checkout_store_tests::fixture().await;
    store
        .register_project_checkout(&project.id, host, &project.repo_path)
        .await
        .unwrap();
    seed_profile(&store).await;
    let mut definition = definition();
    definition.target = AutomationTarget::ProjectCheckout {
        project_id: project.id,
        host_id: host.into(),
        name_template: "Run".into(),
        agent_profile_id: "profile".into(),
    };
    definition.precheck = Some(AutomationPrecheck {
        command: "fixture-command".into(),
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
                key: "fixture".into(),
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
    (directory, store, definition, run)
}

#[tokio::test]
async fn precheck_process_intent_preserves_run_and_project_until_verified_closure_after_reopen() {
    let (directory, store, definition, run) = prepared().await;
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            "operation",
            "linux",
            Some("boot".into()),
        )
        .await
        .unwrap();
    assert_eq!(intent.path, "/repo");
    assert_eq!(intent.host_id, "local");
    assert_eq!(intent.precheck, definition.precheck.clone().unwrap());
    assert!(store
        .begin_automation_precheck_process(
            &run,
            &definition,
            "another",
            "linux",
            Some("boot".into())
        )
        .await
        .is_err());
    for status in [
        AutomationRunStatus::Cancelled,
        AutomationRunStatus::Blocked,
        AutomationRunStatus::Failure,
        AutomationRunStatus::Timeout,
        AutomationRunStatus::Success,
        AutomationRunStatus::PrecheckSkipped,
        AutomationRunStatus::OverlapSkipped,
        AutomationRunStatus::MisfireSkipped,
        AutomationRunStatus::QueueLimitSkipped,
    ] {
        assert!(
            store
                .update_automation_run_status(&run.id, status, None)
                .await
                .is_err(),
            "{status:?}"
        );
    }
    let mut advanced = run.clone();
    advanced.attempt_count += 1;
    assert!(store.save_automation_run(&advanced).await.is_err());
    store
        .request_automation_cancel(&run.id, definition.created_by.clone())
        .await
        .unwrap();
    for (table, id) in [
        ("automationRuns", run.id.as_str()),
        ("automations", definition.id.as_str()),
        ("projects", "project"),
    ] {
        let query = format!("DELETE FROM {table} WHERE id = ?");
        assert!(sqlx::query(sqlx::AssertSqlSafe(query))
            .bind(id)
            .execute(store.pool())
            .await
            .is_err());
    }
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .automation_precheck_processes(&run.id)
            .await
            .unwrap(),
        vec![intent.clone()]
    );
    assert_eq!(
        reopened.list_active_automation_runs().await.unwrap().len(),
        1
    );
    let spawned = reopened
        .record_automation_precheck_spawn(&intent, 12345, Some(987))
        .await
        .unwrap();
    let exited = reopened
        .record_automation_precheck_phase(&spawned, WorkspaceProcessJobPhase::RootExited)
        .await
        .unwrap();
    assert!(reopened
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .is_err());
    reopened
        .record_automation_precheck_phase(&exited, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .unwrap();
    reopened
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .unwrap();
    assert!(reopened
        .list_active_automation_runs()
        .await
        .unwrap()
        .is_empty());
    sqlx::query("DELETE FROM automationRuns WHERE id = ?")
        .bind(&run.id)
        .execute(reopened.pool())
        .await
        .unwrap();
    assert!(reopened
        .automation_precheck_processes(&run.id)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn precheck_process_phases_reject_stale_or_missing_root_evidence() {
    let (_directory, store, definition, run) = prepared().await;
    let intent = store
        .begin_automation_precheck_process(&run, &definition, "operation", "windows", None)
        .await
        .unwrap();
    assert!(store
        .record_automation_precheck_spawn(&intent, 0, None)
        .await
        .is_err());
    assert!(store
        .record_automation_precheck_phase(&intent, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .is_err());
    let failed = store
        .record_automation_precheck_phase(&intent, WorkspaceProcessJobPhase::SpawnFailed)
        .await
        .unwrap();
    assert!(store
        .record_automation_precheck_spawn(&intent, 123, None)
        .await
        .is_err());
    assert!(store
        .record_automation_precheck_phase(&failed, WorkspaceProcessJobPhase::RootExited)
        .await
        .is_err());
    let next = store
        .begin_automation_precheck_process(&run, &definition, "next-operation", "windows", None)
        .await
        .unwrap();
    assert_ne!(next.id, intent.id);
    let spawned = store
        .record_automation_precheck_spawn(&next, 456, None)
        .await
        .unwrap();
    assert!(store
        .record_automation_precheck_phase(&spawned, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .is_err());
    assert!(store
        .update_automation_run_status(&run.id, AutomationRunStatus::Failure, None)
        .await
        .is_err());
}

#[tokio::test]
async fn cancelled_and_stale_precheck_reservations_cannot_start_process_intents() {
    let (_directory, store, definition, run) = prepared().await;
    let mut stale = run.clone();
    stale.attempt_count += 1;
    assert!(store
        .begin_automation_precheck_process(&stale, &definition, "stale", "linux", None)
        .await
        .is_err());
    let mut old_definition = definition.clone();
    old_definition.revision += 1;
    assert!(store
        .begin_automation_precheck_process(&run, &old_definition, "changed", "linux", None)
        .await
        .is_err());
    store
        .request_automation_cancel(&run.id, definition.created_by.clone())
        .await
        .unwrap();
    assert!(store
        .begin_automation_precheck_process(&run, &definition, "cancelled", "linux", None)
        .await
        .is_err());
    assert!(store
        .automation_precheck_processes(&run.id)
        .await
        .unwrap()
        .is_empty());
}
