use super::*;

#[tokio::test]
async fn precheck_from_previous_boot_releases_reservation_without_repeating_command() {
    let current_boot = crate::relocation_setup_process::current_boot_id()
        .unwrap()
        .unwrap();
    for cancelled in [false, true] {
        let (mut fixture, mut definition) = empty_project().await;
        definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
            command: "fixture-must-never-run".into(),
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
                    key: "previous-boot".into(),
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
        let previous_boot = uuid::Uuid::new_v4().to_string();
        assert_ne!(previous_boot, current_boot);
        store
            .begin_automation_precheck_process(
                &run,
                &definition,
                "previous-launch",
                "linux",
                Some(previous_boot.clone()),
            )
            .await
            .unwrap();
        store
            .update_automation_run_status(
                &run.id,
                AutomationRunStatus::WaitingForUser,
                Some("Unverified process closure".into()),
            )
            .await
            .unwrap();
        if cancelled {
            store
                .request_automation_cancel(&run.id, definition.created_by.clone())
                .await
                .unwrap();
        }
        fixture
            .actor
            .handle(crate::terminal_host::server::ServerCommand::AutomationTick)
            .await;
        let resolved = store.find_automation_run(&run.id).await.unwrap().unwrap();
        assert_eq!(
            resolved.status,
            if cancelled {
                AutomationRunStatus::Cancelled
            } else {
                AutomationRunStatus::Blocked
            }
        );
        assert_eq!(resolved.attempt_count, 0);
        assert!(resolved.workspace_id.is_none());
        assert!(store
            .list_active_automation_runs()
            .await
            .unwrap()
            .is_empty());
        assert!(fixture.actor.automation_precheck_jobs.is_empty());
        assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
        let records = store.automation_precheck_processes(&run.id).await.unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(
            records[0].phase,
            alera_core::runtime::WorkspaceProcessJobPhase::ClosureVerified
        );
        assert_eq!(records[0].boot_id.as_deref(), Some(previous_boot.as_str()));
        assert_eq!(
            records[0].closure_boot_id.as_deref(),
            Some(current_boot.as_str())
        );
        assert!(records[0].pid.is_none());
    }
}
