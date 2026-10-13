use serde_json::json;

use super::run_integration_tests::fixture::ready_workspace;
use super::run_plan_tests::{control, decision, fixture, valid_profile, WorkflowDecision};
use super::*;

#[tokio::test]
async fn execution_completion_revalidates_evidence_and_human_gates_atomically() {
    let (dir, store, proposal) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    assert!(store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .is_err());
    let tasks: Vec<String> = sqlx::query_scalar(
        "SELECT id FROM orchestrationTasks WHERE run_id=? AND plan_revision IS NOT NULL",
    )
    .bind(&plan.run_id)
    .fetch_all(store.pool())
    .await
    .unwrap();
    for task in tasks {
        sqlx::query(
            "UPDATE orchestrationTasks SET status='completed',result='validated' WHERE id=?",
        )
        .bind(&task)
        .execute(store.pool())
        .await
        .unwrap();
        sqlx::query("INSERT INTO runTaskEvidence(task_id,result_digest,artifact_digest,integration_sha) VALUES (?,?,?,?)")
            .bind(task).bind(super::run_plan::workflow_digest(&Some("validated".to_owned())).unwrap())
            .bind("artifacts").bind(&plan.integration_sha).execute(store.pool()).await.unwrap();
    }
    assert!(store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .unwrap_err()
        .to_string()
        .contains("stage gate"));
    sqlx::query("UPDATE runGates SET status='resolved', resolution='approve', evidence_digest='digest' WHERE run_id=? AND kind='stage'")
        .bind(&plan.run_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(!store
        .complete_workflow_execution(&plan.run_id, 1, 0)
        .await
        .unwrap());
    assert!(store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .unwrap());
    assert!(!store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .unwrap());
    assert_eq!(
        store
            .workflow_execution(&plan.run_id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "completed"
    );
    assert!(store
        .workflow_execution_page(None)
        .await
        .unwrap()
        .is_empty());
    let timeline = store
        .run_timeline(&RunTimelineQuery {
            run_id: plan.run_id.clone(),
            kinds: Some(vec!["completed".into()]),
            ..Default::default()
        })
        .await
        .unwrap();
    let completed = serde_json::to_value(&timeline.items[0]).unwrap();
    assert_eq!(completed["kind"], "completed");
    assert_eq!(completed["sha"], json!(plan.integration_sha));
}

#[tokio::test]
async fn execution_attention_cannot_overwrite_a_later_human_command() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    assert!(store
        .pause_workflow_execution_for_attention(&plan.run_id, 1, 1, "Inspect the workspace.")
        .await
        .unwrap());
    let state = store
        .workflow_execution(&plan.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.status, "paused");
    assert_eq!(state.attention.as_deref(), Some("Inspect the workspace."));
    assert_eq!(
        store
            .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
            .await
            .unwrap()
            .items[0]
            .bucket,
        OrchestrationBoardBucket::Attention
    );
    control(&store, &plan.run_id, RunControlAction::Resume)
        .await
        .unwrap();
    assert!(!store
        .pause_workflow_execution_for_attention(&plan.run_id, 1, 1, "Stale failure")
        .await
        .unwrap());
    let state = store
        .workflow_execution(&plan.run_id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.status, "running");
    assert!(state.attention.is_none());
    assert_eq!(
        store
            .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
            .await
            .unwrap()
            .items[0]
            .bucket,
        OrchestrationBoardBucket::Active
    );
}

#[tokio::test]
async fn execution_step_starts_with_the_plan_and_preserves_operation_identity() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let first = store
        .workflow_execution_step(&plan.run_id, 1)
        .await
        .unwrap();
    let repeated = store
        .workflow_execution_step(&plan.run_id, 1)
        .await
        .unwrap();
    assert_eq!(
        serde_json::to_value(&first).unwrap(),
        serde_json::to_value(&repeated).unwrap()
    );
    assert!(matches!(
        first,
        WorkflowExecutionStep::PrepareWorkspace(PrepareWorkflowWorkspace { task_id: None, .. })
    ));
    ready_workspace(&dir, &store, &plan, None).await;
    let WorkflowExecutionStep::PrepareWorkspace(task) = store
        .workflow_execution_step(&plan.run_id, 1)
        .await
        .unwrap()
    else {
        panic!("expected task preparation")
    };
    let attempt = ready_workspace(&dir, &store, &plan, task.task_id.clone()).await;
    let WorkflowExecutionStep::LaunchTask(launch) = store
        .workflow_execution_step(&plan.run_id, 1)
        .await
        .unwrap()
    else {
        panic!("expected task launch")
    };
    assert_eq!(launch.workspace_id, attempt.identity.workspace.id);
    let (receipt, _) = store
        .reserve_workflow_launch(&launch, &"a".repeat(64))
        .await
        .unwrap();
    store.claim_workflow_launch(&receipt.id).await.unwrap();
    assert!(matches!(
        store
            .workflow_execution_step(&plan.run_id, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    control(&store, &plan.run_id, RunControlAction::Pause)
        .await
        .unwrap();
    assert!(matches!(
        store
            .workflow_execution_step(&plan.run_id, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Waiting
    ));
}

#[tokio::test]
async fn execution_step_integrates_results_before_scheduling_dependents() {
    let f = super::run_integration_tests::fixture::Fixture::new().await;
    let WorkflowExecutionStep::IntegrateResult(input) = f
        .store
        .workflow_execution_step(&f.plan.run_id, 1)
        .await
        .unwrap()
    else {
        panic!("must integrate before dependent preparation")
    };
    assert_eq!(input.task_id, f.input.task_id);
    assert_eq!(input.workspace_id, f.input.workspace_id);
    let record = f.store.reserve_workflow_integration(&input).await.unwrap();
    let repeated = f
        .store
        .workflow_execution_step(&f.plan.run_id, 1)
        .await
        .unwrap();
    let WorkflowExecutionStep::IntegrateResult(repeated) = repeated else {
        panic!("resume integration")
    };
    assert_eq!(repeated.request_id, input.request_id);
    f.store
        .workflow_integration_attention(&record.request.id, "Inspect conflict")
        .await
        .unwrap();
    assert!(matches!(
        f.store
            .workflow_execution_step(&f.plan.run_id, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Attention { .. }
    ));
}
