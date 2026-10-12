use super::*;
use crate::runtime::run_plan_tests::control;

#[tokio::test]
async fn terminal_refusal_retains_evidence_and_allows_a_replan() {
    let fixture = Fixture::new().await;
    let reserved = fixture.reserve().await;
    let outcome = WorkflowGitPreparation::Refused {
        paths: vec!["module".into()],
        truncated: false,
        reason: "submodule changes require explicit integration outside this workflow".into(),
    };
    let refused = fixture
        .store
        .record_workflow_integration_preparation(&reserved.request.id, &outcome)
        .await
        .unwrap();
    assert_eq!(refused.state, WorkflowIntegrationState::Conflict);
    assert!(refused.receipt.is_none());
    assert_eq!(refused.conflict_paths, ["module"]);
    assert!(refused
        .error
        .as_deref()
        .unwrap()
        .contains("submodule changes"));
    fixture.assert_dependent_blocked().await;
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
        Some("refused")
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
    assert_eq!(workflow.state, "refused");
    assert!(workflow.error.unwrap().contains("submodule changes"));
    let changes = control(
        &fixture.store,
        &fixture.plan.run_id,
        RunControlAction::Replan,
    )
    .await
    .unwrap();
    assert!(changes.changes_requested);
    assert_eq!(changes.plan_revision, Some(2));
    assert_eq!(changes.status, "planning");
    let retained = fixture
        .store
        .workflow_integration(&refused.request.id)
        .await
        .unwrap();
    assert_eq!(retained.state, WorkflowIntegrationState::Conflict);
    assert_eq!(retained.request, refused.request);
    assert_eq!(retained.error, refused.error);
    assert_eq!(
        fixture
            .store
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
async fn uncertain_integration_attention_blocks_a_replan() {
    let fixture = Fixture::new().await;
    let reserved = fixture.reserve().await;
    fixture
        .store
        .workflow_integration_attention(&reserved.request.id, "checkout outcome unknown")
        .await
        .unwrap();
    let error = control(
        &fixture.store,
        &fixture.plan.run_id,
        RunControlAction::Replan,
    )
    .await
    .unwrap_err();
    assert!(
        error.to_string().starts_with("run_integration_pending:"),
        "{error}"
    );
}
