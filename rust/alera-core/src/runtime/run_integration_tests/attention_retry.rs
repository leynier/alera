use super::*;
use crate::runtime::run_plan_tests::control;

#[tokio::test]
async fn attention_inspection_exposes_only_the_original_integration_retry() {
    let fixture = Fixture::new().await;
    let record = fixture.reserve().await;
    assert_ne!(record.request.id, fixture.input.request_id);
    fixture
        .store
        .workflow_integration_attention(&record.request.id, "integration worktree is dirty")
        .await
        .unwrap();
    control(
        &fixture.store,
        &fixture.input.run_id,
        RunControlAction::Pause,
    )
    .await
    .unwrap();
    let inspection = fixture
        .store
        .orchestration_task_inspection(&OrchestrationTaskInspectionQuery {
            run_id: fixture.input.run_id.clone(),
            task_id: fixture.input.task_id.clone(),
            cursor: None,
            limit: None,
        })
        .await
        .unwrap();
    let workflow = inspection.attempt.unwrap();
    assert_eq!(workflow.state, "attention");
    assert!(workflow.can_retry_integration);
    assert!(!workflow.can_retry);
    assert_eq!(
        workflow.integration_id.as_deref(),
        Some(record.request.id.as_str())
    );
    assert_eq!(
        workflow.integration_request_id.as_deref(),
        Some(fixture.input.request_id.as_str())
    );
    let mut forged = fixture.input.clone();
    forged.request_id = record.request.id;
    assert!(fixture
        .store
        .workflow_integration_for_request(&forged)
        .await
        .unwrap()
        .is_none());
    assert!(fixture
        .store
        .reserve_workflow_integration(&forged)
        .await
        .is_err());
    control(
        &fixture.store,
        &fixture.input.run_id,
        RunControlAction::Resume,
    )
    .await
    .unwrap();
    assert!(matches!(
        fixture
            .store
            .workflow_execution_step(&fixture.input.run_id, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Attention { .. }
    ));
}
