use serde_json::json;

use super::workflow_workspace_eligibility::eligible_task;
use super::*;
use crate::git::{
    apply_workflow_integration, prepare_workflow_integration, WorkflowGitPreparation,
};

pub(super) mod fixture;
use fixture::Fixture;

#[tokio::test]
async fn workflow_integration_store_defers_dependencies_until_git_and_evidence_commit() {
    let fixture = Fixture::new().await;
    let snapshot = fixture
        .store
        .orchestration_run_snapshot(&OrchestrationRunSnapshotQuery {
            run_id: fixture.plan.run_id.clone(),
            after_task_id: None,
            revision: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(
        snapshot
            .tasks
            .iter()
            .find(|task| task.id == fixture.input.task_id)
            .unwrap()
            .workflow_state
            .as_deref(),
        Some("result_ready")
    );
    let inspection = fixture
        .store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: fixture.plan.run_id.clone(),
            task_id: fixture.input.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    let workflow = inspection.workflow.unwrap();
    assert_eq!(workflow.state, "result_ready");
    assert_eq!(workflow.execution_workspace_id, fixture.input.workspace_id);
    let record = fixture.reserve().await;
    fixture.assert_dependent_blocked().await;
    assert_eq!(record.state, WorkflowIntegrationState::Pending);
    let outcome = prepare_workflow_integration(&record.request).unwrap();
    let prepared = fixture
        .store
        .record_workflow_integration_preparation(&record.request.id, &outcome)
        .await
        .unwrap();
    fixture.assert_dependent_blocked().await;
    let receipt = apply_workflow_integration(&prepared.request).unwrap();
    fixture.assert_dependent_blocked().await;
    let done = fixture
        .store
        .complete_workflow_integration(&receipt)
        .await
        .unwrap();
    assert_eq!(done.state, WorkflowIntegrationState::Integrated);
    let inspection = fixture
        .store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: fixture.plan.run_id.clone(),
            task_id: fixture.input.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(inspection.workflow.unwrap().state, "integrated");
    assert!(inspection
        .history
        .iter()
        .any(|entry| entry.kind == "workflowLaunch" && entry.status == "started"));
    assert!(inspection
        .history
        .iter()
        .any(|entry| entry.kind == "workflowIntegration" && entry.status == "integrated"));
    let mut tx = fixture.store.pool().begin().await.unwrap();
    eligible_task(
        &mut tx,
        &fixture.plan.run_id,
        1,
        &fixture.dependent,
        &fixture.plan.plan,
    )
    .await
    .unwrap();
    tx.rollback().await.unwrap();
    let sha: String =
        sqlx::query_scalar("SELECT integration_sha FROM workflowRuns WHERE run_id = ?")
            .bind(&fixture.plan.run_id)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!(sha, receipt.integrated_sha);
    let repeated = fixture
        .store
        .complete_workflow_integration(&receipt)
        .await
        .unwrap();
    assert_eq!(repeated.request, done.request);
    assert_eq!(
        fixture.reserve().await.state,
        WorkflowIntegrationState::Integrated
    );
    let mut other_id = fixture.input.clone();
    other_id.request_id = "second integration".into();
    assert!(fixture
        .store
        .reserve_workflow_integration(&other_id, &fixture.source_sha)
        .await
        .unwrap_err()
        .to_string()
        .contains("already integrated"));
    sqlx::query("UPDATE orchestrationTasks SET result = ? WHERE id = ?")
        .bind(json!({"summary":"changed after integration"}).to_string())
        .bind(&fixture.input.task_id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    let evidence: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM workflowTaskEvidence WHERE task_id = ?")
            .bind(&fixture.input.task_id)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!(evidence, 0);
    fixture.assert_dependent_blocked().await;
    let inspection = fixture
        .store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: fixture.plan.run_id.clone(),
            task_id: fixture.input.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(inspection.workflow.unwrap().state, "attention");
    let board = fixture
        .store
        .orchestration_board_snapshot(&OrchestrationBoardQuery {
            bucket: None,
            project_id: None,
            workspace_id: None,
            search: None,
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    assert_eq!(board.items[0].bucket, OrchestrationBoardBucket::Attention);
}

#[tokio::test]
async fn workflow_integration_store_reconciles_git_before_database_after_restart() {
    let fixture = Fixture::new().await;
    let record = fixture.reserve().await;
    let outcome = prepare_workflow_integration(&record.request).unwrap();
    let receipt = apply_workflow_integration(&record.request).unwrap();
    let reopened = RuntimeStore::open(fixture.directory.path()).await.unwrap();
    let recovered = reopened
        .reserve_workflow_integration(&fixture.input, &fixture.source_sha)
        .await
        .unwrap();
    assert_eq!(recovered.state, WorkflowIntegrationState::Pending);
    assert_eq!(recovered.request, record.request);
    reopened
        .record_workflow_integration_preparation(&record.request.id, &outcome)
        .await
        .unwrap();
    reopened
        .complete_workflow_integration(&receipt)
        .await
        .unwrap();
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM workflowTaskEvidence WHERE task_id = ?")
            .bind(&fixture.input.task_id)
            .fetch_one(reopened.pool())
            .await
            .unwrap();
    assert_eq!(count, 1);
}

#[tokio::test]
async fn workflow_integration_store_serializes_and_binds_request_replay() {
    let fixture = Fixture::new().await;
    let (first, second) = tokio::join!(
        fixture
            .store
            .reserve_workflow_integration(&fixture.input, &fixture.source_sha),
        fixture
            .store
            .reserve_workflow_integration(&fixture.input, &fixture.source_sha),
    );
    let first = first.unwrap();
    assert_eq!(first.request, second.unwrap().request);
    let mut changed = fixture.input.clone();
    changed.revision = 2;
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed, &fixture.source_sha)
        .await
        .unwrap_err()
        .to_string()
        .contains("different contents"));
    changed = fixture.input.clone();
    changed.request_id = "another operation".into();
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed, &fixture.source_sha)
        .await
        .is_err());
    fixture
        .store
        .workflow_integration_attention(&first.request.id, "interrupted checkout")
        .await
        .unwrap();
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed, &fixture.source_sha)
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_integration_store_rejects_stale_results_cancelled_runs_and_unprepared_receipts() {
    for change in ["result", "cancel", "unprepared"] {
        let fixture = Fixture::new().await;
        let record = fixture.reserve().await;
        let outcome = prepare_workflow_integration(&record.request).unwrap();
        let WorkflowGitPreparation::Ready { receipt } = &outcome else {
            panic!()
        };
        if change == "unprepared" {
            assert!(fixture
                .store
                .complete_workflow_integration(receipt)
                .await
                .is_err());
            continue;
        }
        fixture
            .store
            .record_workflow_integration_preparation(&record.request.id, &outcome)
            .await
            .unwrap();
        apply_workflow_integration(&record.request).unwrap();
        if change == "result" {
            sqlx::query("UPDATE orchestrationTasks SET result = ? WHERE id = ?")
                .bind(json!({"summary":"changed"}).to_string())
                .bind(&fixture.input.task_id)
                .execute(fixture.store.pool())
                .await
                .unwrap();
        } else {
            sqlx::query("UPDATE workflowRuns SET status = 'cancelled' WHERE run_id = ?")
                .bind(&fixture.plan.run_id)
                .execute(fixture.store.pool())
                .await
                .unwrap();
        }
        assert!(fixture
            .store
            .complete_workflow_integration(receipt)
            .await
            .is_err());
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowTaskEvidence")
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
        assert_eq!(count, 0);
        assert!(fixture
            .store
            .workflow_integration(&record.request.id)
            .await
            .unwrap()
            .receipt
            .is_some());
    }
}

#[tokio::test]
async fn workflow_integration_store_conflicts_are_inspectable_and_do_not_enable_dependents() {
    let fixture = Fixture::new().await;
    let record = fixture.reserve().await;
    let conflict = WorkflowGitPreparation::Conflict {
        paths: vec!["result.txt".into()],
        truncated: false,
    };
    let record = fixture
        .store
        .record_workflow_integration_preparation(&record.request.id, &conflict)
        .await
        .unwrap();
    assert_eq!(record.state, WorkflowIntegrationState::Conflict);
    assert_eq!(record.conflict_paths, vec!["result.txt"]);
    fixture.assert_dependent_blocked().await;
    let page = fixture
        .store
        .workflow_integrations_page(&fixture.plan.run_id, 0)
        .await
        .unwrap();
    assert_eq!(page.len(), 1);
    assert!(fixture
        .store
        .workflow_integrations_page(&fixture.plan.run_id, page[0].0)
        .await
        .unwrap()
        .is_empty());
    assert!(sqlx::query("DELETE FROM workflowIntegrations WHERE id = ?")
        .bind(&record.request.id)
        .execute(fixture.store.pool())
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_integration_store_rejects_foreign_attempt_and_dispatch() {
    let fixture = Fixture::new().await;
    let mut wrong = fixture.input.clone();
    wrong.task_id = fixture.dependent.clone();
    assert!(fixture
        .store
        .reserve_workflow_integration(&wrong, &fixture.source_sha)
        .await
        .is_err());
    assert!(sqlx::query(
        "UPDATE orchestrationDispatchContexts SET workspace_id = 'workspace' WHERE id = ?"
    )
    .bind(&fixture.dispatch)
    .execute(fixture.store.pool())
    .await
    .is_err());
    assert!(fixture
        .store
        .reserve_workflow_integration(&fixture.input, &fixture.source_sha)
        .await
        .is_ok());
}

#[tokio::test]
async fn workflow_integration_store_blocks_approval_while_git_is_unsettled() {
    let fixture = Fixture::new().await;
    fixture.reserve().await;
    let error = fixture
        .store
        .workflow_approval_challenge(&fixture.plan.run_id, 1, "stage:verify", "desktop")
        .await
        .unwrap_err();
    assert!(error.to_string().contains("pending integration"));
}
