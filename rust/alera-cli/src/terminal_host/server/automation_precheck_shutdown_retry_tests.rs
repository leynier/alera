use super::*;
use crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown;
use alera_core::runtime::WorkspaceProcessJobPhase;

#[tokio::test]
async fn precheck_shutdown_retry_retains_reservation_until_guard_verifies_closure() {
    let (mut fixture, mut definition) = empty_project().await;
    definition.precheck = Some(alera_core::runtime::AutomationPrecheck {
        command: "fixture-not-executed".into(),
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
                key: "shutdown-retry".into(),
                scheduled_at: Utc::now(),
                local_time: "fixture".into(),
            },
            AutomationRunTrigger::Scheduled,
        )
        .await
        .unwrap();
    run.precheck = Some(true);
    run.status = AutomationRunStatus::Dispatching;
    let run = store.save_automation_run(&run).await.unwrap();
    let intent = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            "retry-operation",
            std::env::consts::OS,
            None,
        )
        .await
        .unwrap();
    let record = store
        .record_automation_precheck_spawn(&intent, 123, Some(456))
        .await
        .unwrap();
    let worker_store = store.clone();
    let worker_run = run.clone();
    // Inject inspection failures without signaling any native process.
    let worker = tokio::spawn(async move {
        let mut scope = WorkspaceShutdown::default();
        scope.fail_next_waits(2);
        crate::terminal_host::server::automation_dispatch::automation_local_precheck::wait_for_closure(
            &worker_store, &worker_run, &mut scope,
        ).await;
    });
    let observed = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let current = store.find_automation_run(&run.id).await.unwrap().unwrap();
            if current.status == AutomationRunStatus::WaitingForUser {
                return current;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;
    let worker_pending = !worker.is_finished();
    let finalization = store
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await;
    store
        .request_automation_cancel(&run.id, definition.created_by.clone())
        .await
        .unwrap();
    // Always drain the retry worker before asserting its observed state.
    tokio::time::timeout(Duration::from_secs(5), worker)
        .await
        .unwrap()
        .unwrap();
    assert!(observed.is_ok());
    assert!(worker_pending);
    assert!(finalization.is_err());
    assert_eq!(store.list_active_automation_runs().await.unwrap().len(), 1);
    let exited = store
        .record_automation_precheck_phase(&record, WorkspaceProcessJobPhase::RootExited)
        .await
        .unwrap();
    store
        .record_automation_precheck_phase(&exited, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .unwrap();
    fixture
        .actor
        .finish_automation_precheck(
            definition,
            run.clone(),
            "local".into(),
            intent.path,
            Err("fixture cancellation".into()),
        )
        .await;
    assert_eq!(
        store
            .find_automation_run(&run.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        AutomationRunStatus::Cancelled
    );
    assert!(store
        .list_active_automation_runs()
        .await
        .unwrap()
        .is_empty());
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
}
