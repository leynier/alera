use super::*;

#[tokio::test]
async fn owner_precheck_cancellation_before_start_survives_restart_and_prevents_claim() {
    let (directory, store, request) = fixture().await;
    store
        .cancel_owner_automation_precheck(&request)
        .await
        .unwrap();
    let cancelled = store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert!(cancelled.cancel_requested);
    assert!(cancelled.process_id.is_none());
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .register_owner_automation_precheck(&request)
            .await
            .unwrap(),
        cancelled
    );
    assert!(reopened
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .is_none());
    reopened
        .finish_owner_automation_precheck(&request, &OwnerAutomationPrecheckOutcome::Cancelled)
        .await
        .unwrap();
    let mut wrong = request.clone();
    wrong.path = "/another-checkout".into();
    assert!(reopened
        .cancel_owner_automation_precheck(&wrong)
        .await
        .is_err());
    let final_job = reopened
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(final_job.request, request);
    assert_eq!(
        final_job.outcome,
        Some(OwnerAutomationPrecheckOutcome::Cancelled)
    );
}

#[tokio::test]
async fn owner_precheck_result_requires_closure_and_cannot_be_replaced_after_reopen() {
    let (directory, store, request) = fixture().await;
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    let outcome = OwnerAutomationPrecheckOutcome::Passed;
    assert!(store
        .finish_owner_automation_precheck(&request, &outcome)
        .await
        .is_err());
    let intent = store
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .unwrap();
    assert!(store
        .finish_owner_automation_precheck(&request, &outcome)
        .await
        .is_err());
    let spawned = store
        .record_automation_precheck_spawn(&intent, 123, Some(456))
        .await
        .unwrap();
    let exited = store
        .record_automation_precheck_phase(&spawned, WorkspaceProcessJobPhase::RootExited)
        .await
        .unwrap();
    assert!(store
        .finish_owner_automation_precheck(&request, &outcome)
        .await
        .is_err());
    store
        .record_automation_precheck_phase(&exited, WorkspaceProcessJobPhase::ClosureVerified)
        .await
        .unwrap();
    store
        .finish_owner_automation_precheck(&request, &outcome)
        .await
        .unwrap();
    store.pool().close().await;
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    reopened
        .finish_owner_automation_precheck(&request, &outcome)
        .await
        .unwrap();
    assert!(reopened
        .finish_owner_automation_precheck(&request, &OwnerAutomationPrecheckOutcome::Rejected)
        .await
        .is_err());
    assert_eq!(
        reopened
            .find_owner_automation_precheck(&request.operation_id)
            .await
            .unwrap()
            .unwrap()
            .outcome,
        Some(outcome)
    );
    assert!(reopened
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn owner_precheck_cancel_before_launch_and_reboot_do_not_invent_a_command_result() {
    let (_directory, store, request) = fixture().await;
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    store
        .cancel_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert!(store
        .finish_owner_automation_precheck(&request, &OwnerAutomationPrecheckOutcome::Passed)
        .await
        .is_err());
    store
        .finish_owner_automation_precheck(&request, &OwnerAutomationPrecheckOutcome::Cancelled)
        .await
        .unwrap();
    let next = OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        ..request
    };
    store
        .register_owner_automation_precheck(&next)
        .await
        .unwrap();
    let intent = store
        .claim_owner_automation_precheck(&next, "linux", Some(uuid::Uuid::new_v4().to_string()))
        .await
        .unwrap()
        .unwrap();
    store
        .close_automation_precheck_from_previous_boot(&intent, &uuid::Uuid::new_v4().to_string())
        .await
        .unwrap();
    for outcome in [
        OwnerAutomationPrecheckOutcome::Passed,
        OwnerAutomationPrecheckOutcome::Rejected,
    ] {
        assert!(store
            .finish_owner_automation_precheck(&next, &outcome)
            .await
            .is_err());
    }
    store
        .finish_owner_automation_precheck(
            &next,
            &OwnerAutomationPrecheckOutcome::Failed("Command result was lost".into()),
        )
        .await
        .unwrap();
}

async fn fixture() -> (
    tempfile::TempDir,
    RuntimeStore,
    OwnerAutomationPrecheckRequest,
) {
    let (directory, store, project) = crate::runtime::checkout_store_tests::fixture().await;
    store
        .register_project_checkout(&project.id, LOCAL_HOST_ID, &project.repo_path)
        .await
        .unwrap();
    let request = OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        workspace: None,
        origin_id: "home-runtime".into(),
        run_id: "home-run".into(),
        project_id: project.id,
        path: project.repo_path,
        precheck: AutomationPrecheck {
            command: "fixture-command".into(),
            timeout_seconds: 10,
        },
    };
    (directory, store, request)
}

#[tokio::test]
async fn owner_precheck_reservation_is_exact_and_does_not_create_a_workspace() {
    let (_directory, store, request) = fixture().await;
    let initial = store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert_eq!(initial.request, request);
    assert_eq!(
        store
            .register_owner_automation_precheck(&request)
            .await
            .unwrap(),
        initial
    );
    for changed in [
        OwnerAutomationPrecheckRequest {
            workspace: None,
            origin_id: "other-origin".into(),
            ..request.clone()
        },
        OwnerAutomationPrecheckRequest {
            run_id: "other-run".into(),
            ..request.clone()
        },
        OwnerAutomationPrecheckRequest {
            precheck: AutomationPrecheck {
                command: "other-command".into(),
                ..request.precheck.clone()
            },
            ..request.clone()
        },
        OwnerAutomationPrecheckRequest {
            path: "/unregistered".into(),
            ..request.clone()
        },
    ] {
        assert!(store
            .register_owner_automation_precheck(&changed)
            .await
            .is_err());
        assert!(store
            .cancel_owner_automation_precheck(&changed)
            .await
            .is_err());
        assert!(store
            .claim_owner_automation_precheck(&changed, "linux", None)
            .await
            .is_err());
    }
    assert_eq!(
        store
            .find_owner_automation_precheck(&request.operation_id)
            .await
            .unwrap(),
        Some(initial)
    );
    assert!(store
        .list_workspaces(&request.project_id)
        .await
        .unwrap()
        .is_empty());
    assert!(sqlx::query("DELETE FROM projects WHERE id = ?")
        .bind(&request.project_id)
        .execute(store.pool())
        .await
        .is_err());
    store
        .cancel_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert!(store
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .is_none());
    assert!(
        store
            .find_owner_automation_precheck(&request.operation_id)
            .await
            .unwrap()
            .unwrap()
            .cancel_requested
    );
    sqlx::query("DELETE FROM projects WHERE id = ?")
        .bind(&request.project_id)
        .execute(store.pool())
        .await
        .unwrap();
}

#[tokio::test]
async fn owner_precheck_claim_and_cancellation_survive_lost_responses_and_reopen() {
    let (directory, store, request) = fixture().await;
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    let process = store
        .claim_owner_automation_precheck(&request, "linux", Some("boot".into()))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(process.phase, WorkspaceProcessJobPhase::LaunchIntent);
    assert_eq!(process.host_id, LOCAL_HOST_ID);
    assert_ne!(process.run_id, request.run_id);
    assert_eq!(process.path, request.path);
    store.pool().close().await;
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(store
        .claim_owner_automation_precheck(&request, "linux", Some("boot".into()))
        .await
        .unwrap()
        .is_none());
    store
        .cancel_owner_automation_precheck(&request)
        .await
        .unwrap();
    let job = store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    assert!(job.cancel_requested);
    assert_eq!(job.process_id.as_deref(), Some(process.id.as_str()));
    assert!(
        sqlx::query("DELETE FROM ownerAutomationPrechecks WHERE id = ?")
            .bind(&request.operation_id)
            .execute(store.pool())
            .await
            .is_err()
    );
    assert!(sqlx::query("DELETE FROM projects WHERE id = ?")
        .bind(&request.project_id)
        .execute(store.pool())
        .await
        .is_err());
    assert_eq!(
        store
            .automation_precheck_processes(&process.run_id)
            .await
            .unwrap(),
        vec![process]
    );
    assert!(store
        .list_workspaces(&request.project_id)
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn failed_owner_precheck_claim_rolls_back_launch_evidence_and_can_retry() {
    let (_directory, store, request) = fixture().await;
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    sqlx::query("CREATE TRIGGER rejectOwnerPrecheckClaim BEFORE UPDATE OF processId ON ownerAutomationPrechecks BEGIN SELECT RAISE(ABORT, 'fixture claim failure'); END")
        .execute(store.pool()).await.unwrap();
    assert!(store
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .is_err());
    assert!(store
        .find_owner_automation_precheck(&request.operation_id)
        .await
        .unwrap()
        .unwrap()
        .process_id
        .is_none());
    assert!(store
        .automation_precheck_processes(&format!("owner-precheck:{}", request.operation_id))
        .await
        .unwrap()
        .is_empty());
    sqlx::query("DROP TRIGGER rejectOwnerPrecheckClaim")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .claim_owner_automation_precheck(&request, "linux", None)
        .await
        .unwrap()
        .is_some());
}
