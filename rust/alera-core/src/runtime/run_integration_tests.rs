use serde_json::json;

use super::run_workspace_eligibility::eligible_task;
use super::*;
use crate::git::{
    apply_workflow_integration, prepare_workflow_integration, WorkflowGitPreparation,
};

mod attention_retry;
mod conflict_events;
pub(super) mod fixture;
mod refusal_correction;
use fixture::Fixture;

#[tokio::test]
async fn artifact_overflow_cannot_create_a_durable_integration_reservation() {
    let fixture = Fixture::new().await;
    let raw: String = sqlx::query_scalar("SELECT result FROM orchestrationTasks WHERE id = ?")
        .bind(&fixture.input.task_id)
        .fetch_one(fixture.store.pool())
        .await
        .unwrap();
    let mut result: serde_json::Value = serde_json::from_str(&raw).unwrap();
    result["artifacts"] = json!((0..=crate::git::MAX_WORKFLOW_ARTIFACTS)
        .map(|index| format!("artifact-{index}.txt"))
        .collect::<Vec<_>>());
    sqlx::query("UPDATE orchestrationTasks SET result = ? WHERE id = ?")
        .bind(result.to_string())
        .bind(&fixture.input.task_id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    assert!(fixture
        .store
        .reserve_workflow_integration(&fixture.input)
        .await
        .unwrap_err()
        .to_string()
        .contains("too many artifacts"));
    let reservations: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM runIntegrations WHERE task_id = ?")
            .bind(&fixture.input.task_id)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!(reservations, 0);
}

#[tokio::test]
async fn workflow_completion_retains_one_exact_result_sha_across_retries_and_restart() {
    let fixture = Fixture::new().await;
    let completed = fixture
        .store
        .orchestration_dispatch_by_id(&fixture.dispatch)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        completed.completion_sha.as_deref(),
        Some(fixture.source_sha.as_str())
    );
    let result: String = sqlx::query_scalar("SELECT result FROM orchestrationTasks WHERE id = ?")
        .bind(&fixture.input.task_id)
        .fetch_one(fixture.store.pool())
        .await
        .unwrap();
    let repeated = fixture
        .store
        .complete_workflow_orchestration_dispatch(
            &fixture.dispatch,
            completed.assignee_handle.as_deref().unwrap(),
            &result,
            &fixture.source_sha,
        )
        .await
        .unwrap();
    assert_eq!(repeated.completion_sha, completed.completion_sha);
    assert!(fixture
        .store
        .complete_workflow_orchestration_dispatch(
            &fixture.dispatch,
            completed.assignee_handle.as_deref().unwrap(),
            &result,
            &"f".repeat(40),
        )
        .await
        .unwrap_err()
        .to_string()
        .contains("committed result SHA changed"));
    assert!(fixture
        .store
        .complete_orchestration_dispatch(
            &fixture.dispatch,
            completed.assignee_handle.as_deref().unwrap(),
            &result,
        )
        .await
        .unwrap_err()
        .to_string()
        .contains("must include its exact result SHA"));
    assert!(sqlx::query(
        "UPDATE orchestrationDispatchContexts SET completion_sha = ? WHERE id = ?",
    )
    .bind("f".repeat(40))
    .bind(&fixture.dispatch)
    .execute(fixture.store.pool())
    .await
    .is_err());
    let reopened = RuntimeStore::open(fixture.directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .orchestration_dispatch_by_id(&fixture.dispatch)
            .await
            .unwrap()
            .unwrap()
            .completion_sha
            .as_deref(),
        Some(fixture.source_sha.as_str())
    );
}

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
            .attempt_state
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
    let workflow = inspection.attempt.unwrap();
    assert_eq!(workflow.state, "result_ready");
    assert_eq!(workflow.execution_workspace_id, fixture.input.workspace_id);
    assert_eq!(
        workflow.completion_sha.as_deref(),
        Some(fixture.source_sha.as_str())
    );
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
    let workflow = inspection.attempt.unwrap();
    assert_eq!(workflow.state, "integrated");
    assert_eq!(
        workflow.completion_sha.as_deref(),
        Some(fixture.source_sha.as_str())
    );
    assert_eq!(
        workflow.integrated_sha,
        Some(receipt.integrated_sha.clone())
    );
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
        sqlx::query_scalar("SELECT integration_sha FROM orchestrationCoordinatorRuns WHERE id = ?")
            .bind(&fixture.plan.run_id)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!(sha, receipt.integrated_sha);
    let integrated = fixture
        .store
        .run_events(&fixture.plan.run_id, 1000)
        .await
        .unwrap();
    let integrated = integrated
        .iter()
        .find(|event| event.kind == "integrated")
        .unwrap();
    assert_eq!(integrated.task_id.as_ref(), Some(&fixture.input.task_id));
    assert_eq!(
        integrated.payload.as_ref().unwrap()["sha"],
        json!(receipt.integrated_sha)
    );
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
        .reserve_workflow_integration(&other_id)
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
        sqlx::query_scalar("SELECT COUNT(*) FROM runTaskEvidence WHERE task_id = ?")
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
    assert_eq!(inspection.attempt.unwrap().state, "attention");
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
        .reserve_workflow_integration(&fixture.input)
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
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM runTaskEvidence WHERE task_id = ?")
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
        fixture.store.reserve_workflow_integration(&fixture.input),
        fixture.store.reserve_workflow_integration(&fixture.input),
    );
    let first = first.unwrap();
    assert_eq!(first.request, second.unwrap().request);
    let mut changed = fixture.input.clone();
    changed.revision = 2;
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed)
        .await
        .unwrap_err()
        .to_string()
        .contains("different contents"));
    changed = fixture.input.clone();
    changed.request_id = "another operation".into();
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed)
        .await
        .is_err());
    fixture
        .store
        .workflow_integration_attention(&first.request.id, "interrupted checkout")
        .await
        .unwrap();
    assert!(fixture
        .store
        .reserve_workflow_integration(&changed)
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
            sqlx::query(
                "UPDATE orchestrationCoordinatorRuns SET status = 'cancelled' WHERE id = ?",
            )
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
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM runTaskEvidence")
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
async fn workflow_integration_store_rejects_foreign_attempt_and_dispatch() {
    let fixture = Fixture::new().await;
    let mut wrong = fixture.input.clone();
    wrong.task_id = fixture.dependent.clone();
    assert!(fixture
        .store
        .reserve_workflow_integration(&wrong)
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
        .reserve_workflow_integration(&fixture.input)
        .await
        .is_ok());
}

#[tokio::test]
async fn workflow_integration_store_blocks_changes_while_git_is_unsettled() {
    let fixture = Fixture::new().await;
    fixture.reserve().await;
    let error = super::run_plan_tests::control(
        &fixture.store,
        &fixture.plan.run_id,
        RunControlAction::Replan,
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("pending integration"));
    assert!(fixture
        .store
        .open_due_stage_gates(&fixture.plan.run_id)
        .await
        .unwrap()
        .is_empty());
}
