use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

#[tokio::test]
async fn correction_review_displays_conflicts_and_rejects_changed_conflict_evidence() {
    use super::workflow_integration_tests::fixture::Fixture;
    use crate::git::WorkflowGitPreparation;
    let fixture = Fixture::new().await;
    let record = fixture.reserve().await;
    assert!(fixture
        .store
        .workflow_review(&fixture.plan.run_id, 1, "correction", "desktop")
        .await
        .is_err());
    fixture
        .store
        .record_workflow_integration_preparation(
            &record.request.id,
            &WorkflowGitPreparation::Conflict {
                paths: vec!["result.txt".into()],
                truncated: false,
            },
        )
        .await
        .unwrap();
    let review = fixture
        .store
        .workflow_review(&fixture.plan.run_id, 1, "correction", "desktop")
        .await
        .unwrap();
    let task = review
        .tasks
        .iter()
        .find(|task| task.task_id == fixture.input.task_id)
        .unwrap();
    assert_eq!(task.integration_state.as_deref(), Some("conflict"));
    assert_eq!(task.conflict_paths, ["result.txt"]);
    let controls = fixture
        .store
        .workflow_run_controls(&fixture.plan.run_id, Some(1))
        .await
        .unwrap();
    assert!(controls.can_request_changes);
    let key = DesktopWorkflowCredential::load_or_create(fixture.directory.path()).unwrap();
    let statement = WorkflowApprovalStatement {
        challenge: review.challenge,
        decision: WorkflowDecision::RequestChanges,
        reason: "Resolve the conflict".into(),
    };
    let proof = key.sign(&statement).unwrap();
    sqlx::query("UPDATE workflowIntegrations SET conflict_paths='[\"other.txt\"]' WHERE id=?")
        .bind(&record.request.id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    assert!(fixture
        .store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .is_err());
    fixture.assert_dependent_blocked().await;
}

#[tokio::test]
async fn correction_review_requires_human_changes_and_binds_current_results() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let review = store
        .workflow_review(&plan.run_id, 1, "correction", "desktop")
        .await
        .unwrap();
    assert_eq!(review.tasks.len(), 2);
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    for denied in [WorkflowDecision::Approve, WorkflowDecision::Reject] {
        let statement = WorkflowApprovalStatement {
            challenge: review.challenge.clone(),
            decision: denied,
            reason: "Fix failing work".into(),
        };
        let proof = key.sign(&statement).unwrap();
        assert!(store
            .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
            .await
            .is_err());
    }
    sqlx::query("UPDATE orchestrationTasks SET result='changed evidence' WHERE id=?")
        .bind(&review.tasks[0].task_id)
        .execute(store.pool())
        .await
        .unwrap();
    let stale = WorkflowApprovalStatement {
        challenge: review.challenge,
        decision: WorkflowDecision::RequestChanges,
        reason: "Fix failing work".into(),
    };
    let proof = key.sign(&stale).unwrap();
    assert!(store
        .decide_workflow(key.verify(stale, &proof).unwrap(), "desktop")
        .await
        .is_err());
    let current = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "correction", "desktop")
            .await
            .unwrap(),
        decision: WorkflowDecision::RequestChanges,
        reason: "Fix failing work".into(),
    };
    let proof = key.sign(&current).unwrap();
    let receipt = store
        .decide_workflow(key.verify(current.clone(), &proof).unwrap(), "desktop")
        .await
        .unwrap();
    assert_eq!(receipt.current_revision, 2);
    let replay = store
        .decide_workflow(key.verify(current, &proof).unwrap(), "desktop")
        .await
        .unwrap();
    assert_eq!(receipt.decision_id, replay.decision_id);
    let corrected = store
        .workflow_plan_revision(&plan.run_id, None)
        .await
        .unwrap();
    assert_eq!(corrected.status, "changesRequested");
    assert_eq!(corrected.change_reason.as_deref(), Some("Fix failing work"));
}

#[tokio::test]
async fn correction_review_refuses_running_execution_and_active_tasks() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "start".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Start,
        })
        .await
        .unwrap();
    assert!(store
        .workflow_approval_challenge(&plan.run_id, 1, "correction", "desktop")
        .await
        .is_err());
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "pause".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            expected_sequence: 1,
            action: WorkflowExecutionAction::Pause,
        })
        .await
        .unwrap();
    store
        .workflow_approval_challenge(&plan.run_id, 1, "correction", "desktop")
        .await
        .unwrap();
    sqlx::query("UPDATE orchestrationTasks SET status='stalled' WHERE run_id=?")
        .bind(&plan.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .workflow_approval_challenge(&plan.run_id, 1, "correction", "desktop")
        .await
        .is_err());
}
