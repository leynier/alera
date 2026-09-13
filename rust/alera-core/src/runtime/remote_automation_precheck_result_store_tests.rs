use super::*;
use crate::runtime::{
    AutomationPrecheckProcess, OwnerAutomationPrecheck, OwnerAutomationPrecheckOutcome,
};

fn completed(
    home: &AutomationPrecheckProcess,
) -> (OwnerAutomationPrecheck, AutomationPrecheckProcess) {
    let process_id = format!("owner-precheck:{}", home.id);
    let job = OwnerAutomationPrecheck {
        request: home.remote_owner_request().unwrap(),
        cancel_requested: false,
        process_id: Some(process_id.clone()),
        outcome: Some(OwnerAutomationPrecheckOutcome::Passed),
        attention: None,
    };
    let process = AutomationPrecheckProcess {
        id: process_id.clone(),
        run_id: process_id,
        host_id: "local".into(),
        phase: WorkspaceProcessJobPhase::ClosureVerified,
        pid: Some(123),
        start_marker: Some(456),
        boot_id: Some(uuid::Uuid::new_v4().to_string()),
        ..home.clone()
    };
    (job, process)
}

#[tokio::test]
async fn remote_precheck_result_requires_exact_closed_owner_evidence_and_survives_reopen() {
    let (directory, store, definition, run) = prepared_for_host("ssh").await;
    let home = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let (job, process) = completed(&home);
    for invalid in [
        AutomationPrecheckProcess {
            phase: WorkspaceProcessJobPhase::RootExited,
            ..process.clone()
        },
        AutomationPrecheckProcess {
            phase: WorkspaceProcessJobPhase::SpawnFailed,
            ..process.clone()
        },
        AutomationPrecheckProcess {
            host_id: "other-host".into(),
            ..process.clone()
        },
        AutomationPrecheckProcess {
            path: "/other".into(),
            ..process.clone()
        },
        AutomationPrecheckProcess {
            platform: "windows".into(),
            ..process.clone()
        },
        AutomationPrecheckProcess {
            run_id: "other-run".into(),
            ..process.clone()
        },
        AutomationPrecheckProcess {
            closure_boot_id: Some(uuid::Uuid::new_v4().to_string()),
            ..process.clone()
        },
    ] {
        assert!(store
            .record_remote_precheck_result(&home, &job, &[invalid])
            .await
            .is_err());
    }
    let mut other_job = job.clone();
    other_job.request.origin_id = "another-home".into();
    assert!(store
        .record_remote_precheck_result(&home, &other_job, std::slice::from_ref(&process))
        .await
        .is_err());
    assert!(store
        .record_remote_precheck_result(&home, &job, &[])
        .await
        .is_err());
    assert!(store
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .is_err());
    assert!(store
        .remote_precheck_result(&home.id)
        .await
        .unwrap()
        .is_none());
    let closed = store
        .record_remote_precheck_result(&home, &job, std::slice::from_ref(&process))
        .await
        .unwrap();
    assert!(store
        .record_remote_precheck_result(&home, &job, &[process])
        .await
        .is_err());
    assert_eq!(closed.phase, WorkspaceProcessJobPhase::ClosureVerified);
    assert_eq!(closed.pid, None);
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened.remote_precheck_result(&home.id).await.unwrap(),
        Some(job)
    );
    assert_eq!(
        reopened
            .automation_precheck_processes(&run.id)
            .await
            .unwrap(),
        vec![closed]
    );
    reopened
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .unwrap();
}

#[tokio::test]
async fn remote_precheck_result_accepts_only_explicit_unclaimed_cancellation() {
    let (_directory, store, definition, run) = prepared_for_host("ssh").await;
    let home = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let (mut job, _) = completed(&home);
    job.process_id = None;
    job.outcome = Some(OwnerAutomationPrecheckOutcome::Cancelled);
    assert!(store
        .record_remote_precheck_result(&home, &job, &[])
        .await
        .is_err());
    job.cancel_requested = true;
    store
        .record_remote_precheck_result(&home, &job, &[])
        .await
        .unwrap();
    sqlx::query("DELETE FROM automationRuns WHERE id = ?")
        .bind(&run.id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .remote_precheck_result(&home.id)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn remote_precheck_result_write_failure_does_not_release_the_home_fence() {
    let (_directory, store, definition, run) = prepared_for_host("ssh").await;
    let home = store
        .begin_automation_precheck_process(
            &run,
            &definition,
            &uuid::Uuid::new_v4().to_string(),
            "linux",
            None,
        )
        .await
        .unwrap();
    let (job, process) = completed(&home);
    sqlx::query("CREATE TRIGGER failRemoteReceipt BEFORE INSERT ON remoteAutomationPrecheckResults BEGIN SELECT RAISE(ABORT, 'injected write failure'); END").execute(store.pool()).await.unwrap();
    assert!(store
        .record_remote_precheck_result(&home, &job, &[process])
        .await
        .is_err());
    assert_eq!(
        store.automation_precheck_processes(&run.id).await.unwrap(),
        vec![home]
    );
    assert!(store
        .update_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .is_err());
}
