use super::integration_regressions::completed;
use super::*;

async fn cancel(fixture: &Fixture) {
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn workflow_cancelled_integration_settles_reserved_receipts_without_new_git_work() {
    for phase in ["pending", "prepared", "applied", "attention"] {
        let fixture = Fixture::new("").await;
        let target = fixture.integration().await;
        let (input, _) = completed(&fixture, "fix", "fixed\n").await;
        let record = fixture
            .store
            .reserve_workflow_integration(&input)
            .await
            .unwrap();
        let receipt = if matches!(phase, "prepared" | "applied") {
            let outcome = core_git::prepare_workflow_integration(&record.request).unwrap();
            if phase == "prepared" {
                fixture
                    .store
                    .record_workflow_integration_preparation(&record.request.id, &outcome)
                    .await
                    .unwrap();
            }
            if phase == "applied" {
                Some(core_git::apply_workflow_integration(&record.request).unwrap())
            } else {
                core_git::inspect_cancelled_workflow_integration(&record.request).unwrap()
            }
        } else {
            None
        };
        if phase == "attention" {
            fixture
                .store
                .workflow_integration_attention(&record.request.id, "interrupted")
                .await
                .unwrap();
        }
        let repo = git2::Repository::open(&target.identity.workspace.path).unwrap();
        let before = repo.head().unwrap().target().unwrap();
        cancel(&fixture).await;
        assert!(fixture
            .store
            .require_workflow_integration_current(&record.request.id)
            .await
            .is_err());
        let reopened = RuntimeStore::open(&fixture.runtime).await.unwrap();
        integration::reconcile(&reopened, &fixture.runtime)
            .await
            .unwrap();
        let settled = reopened
            .workflow_integration(&record.request.id)
            .await
            .unwrap();
        assert_eq!(
            settled.state,
            WorkflowIntegrationState::Cancelled,
            "{phase}: {settled:?}"
        );
        assert_eq!(settled.receipt, receipt);
        assert_eq!(repo.head().unwrap().target().unwrap(), before);
        assert_eq!(
            integration::integrate(&reopened, &fixture.runtime, input.clone())
                .await
                .unwrap()
                .state,
            WorkflowIntegrationState::Cancelled
        );
        let mut new = input.clone();
        new.request_id = "new-after-cancel".into();
        assert!(integration::integrate(&reopened, &fixture.runtime, new)
            .await
            .is_err());
        let evidence: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM workflowTaskEvidence WHERE task_id=?")
                .bind(&input.task_id)
                .fetch_one(reopened.pool())
                .await
                .unwrap();
        assert_eq!(evidence, 0);
        let sha: String =
            sqlx::query_scalar("SELECT integration_sha FROM workflowRuns WHERE run_id=?")
                .bind(&input.run_id)
                .fetch_one(reopened.pool())
                .await
                .unwrap();
        assert_eq!(sha, record.request.expected_sha);
        for target in reopened.workflow_cancellation_page().await.unwrap() {
            reopened
                .settle_workflow_cancellation(&target, None)
                .await
                .unwrap();
        }
        let git = core_git::preview_workflow_cleanup(
            &target.identity.repo_path,
            &target.identity.workspace.path,
            &target.identity.base_sha,
            &target.identity.workspace.id,
        )
        .unwrap();
        reopened
            .publish_workflow_cleanup_preview(
                &Uuid::new_v4().to_string(),
                &input.run_id,
                vec![WorkflowCleanupItem {
                    identity: target.identity.clone(),
                    git,
                    remove_branch: false,
                }],
            )
            .await
            .unwrap();
        let summaries = reopened
            .workflow_integration_summaries(&WorkflowIntegrationQuery {
                run_id: input.run_id.clone(),
                after_row: None,
            })
            .await
            .unwrap();
        assert_eq!(
            summaries.items[0].state,
            WorkflowIntegrationState::Cancelled
        );
        integration::reconcile(&reopened, &fixture.runtime)
            .await
            .unwrap();
        assert_eq!(repo.head().unwrap().target().unwrap(), before);
    }
}

#[tokio::test]
async fn workflow_cancelled_integration_preserves_dirty_attention_until_explicit_recovery() {
    let fixture = Fixture::new("").await;
    let target = fixture.integration().await;
    let (input, _) = completed(&fixture, "fix", "fixed\n").await;
    let record = fixture
        .store
        .reserve_workflow_integration(&input)
        .await
        .unwrap();
    cancel(&fixture).await;
    let dirty = Path::new(&target.identity.workspace.path).join("retained.txt");
    std::fs::write(&dirty, "retain user work").unwrap();
    let settled = integration::integrate(&fixture.store, &fixture.runtime, input.clone())
        .await
        .unwrap();
    assert_eq!(settled.state, WorkflowIntegrationState::Attention);
    let controls = fixture.store.workflow_run_controls(&input.run_id, None).await.unwrap();
    assert!(controls.can_cancel);
    assert_eq!(controls.integration_settlement_pending, 1);
    assert!(controls.cancellation_error.is_some());
    let snapshot = fixture.store.orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
        run_id: input.run_id.clone(), after_task_id: None, revision: None, limit: None,
    }).await.unwrap();
    assert_eq!(snapshot.run.bucket, OrchestrationBoardBucket::Attention);
    assert_eq!(std::fs::read_to_string(&dirty).unwrap(), "retain user work");
    std::fs::remove_file(dirty).unwrap();
    let settled = integration::integrate(&fixture.store, &fixture.runtime, input.clone())
        .await
        .unwrap();
    assert_eq!(settled.state, WorkflowIntegrationState::Cancelled);
    let controls = fixture.store.workflow_run_controls(&input.run_id, None).await.unwrap();
    assert_eq!(controls.integration_settlement_pending, 0);
    let snapshot = fixture.store.orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
        run_id: input.run_id.clone(), after_task_id: None, revision: None, limit: None,
    }).await.unwrap();
    assert_eq!(snapshot.tasks.iter().find(|task| task.id == input.task_id).unwrap().workflow_state.as_deref(), Some("cancelled"));
    assert!(
        core_git::inspect_cancelled_workflow_integration(&record.request)
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn workflow_cancelled_integration_rejects_drift_locks_and_invalid_receipts() {
    for obstruction in ["head", "locked", "receipt"] {
        let fixture = Fixture::new("").await;
        let target = fixture.integration().await;
        let (input, _) = completed(&fixture, "fix", "fixed\n").await;
        let record = fixture
            .store
            .reserve_workflow_integration(&input)
            .await
            .unwrap();
        cancel(&fixture).await;
        let repo = git2::Repository::open(&target.identity.workspace.path).unwrap();
        let root = git2::Repository::open(&target.identity.repo_path).unwrap();
        let parent = repo.head().unwrap().peel_to_commit().unwrap();
        match obstruction {
            "head" => {
                let signature = repo.signature().unwrap();
                repo.commit(
                    Some("HEAD"),
                    &signature,
                    &signature,
                    "external change",
                    &parent.tree().unwrap(),
                    &[&parent],
                )
                .unwrap();
            }
            "locked" => root
                .find_worktree(&target.identity.workspace.id)
                .unwrap()
                .lock(Some("user lock"))
                .unwrap(),
            "receipt" => {
                root.reference(
                    &format!("refs/alera/workflow-integrations/{}", record.request.id),
                    parent.id(),
                    false,
                    "invalid test receipt",
                )
                .unwrap();
            }
            _ => unreachable!(),
        }
        let before = repo.head().unwrap().target().unwrap();
        let settled = integration::integrate(&fixture.store, &fixture.runtime, input)
            .await
            .unwrap();
        assert_eq!(
            settled.state,
            WorkflowIntegrationState::Attention,
            "{obstruction}"
        );
        assert_eq!(repo.head().unwrap().target().unwrap(), before);
        assert!(Path::new(&target.identity.workspace.path).exists());
    }
}
