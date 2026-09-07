use super::workflow_integration_tests::fixture::ready_workspace;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

async fn start(store: &RuntimeStore, plan: &WorkflowPlanRevision) {
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "start-scheduling".into(),
            run_id: plan.run_id.clone(),
            revision: plan.revision,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Start,
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn execution_completion_revalidates_evidence_and_human_gates_atomically() {
    let (dir, store, proposal) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    start(&store, &plan).await;
    assert!(store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .is_err());
    let tasks: Vec<String> =
        sqlx::query_scalar("SELECT task_id FROM workflowPlanTasks WHERE run_id=?")
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
        sqlx::query("INSERT INTO workflowTaskEvidence(task_id,result_digest,artifact_digest,integration_sha) VALUES (?,?,?,?)")
            .bind(task).bind(super::workflow_plan::workflow_digest(&Some("validated".to_owned())).unwrap())
            .bind("artifacts").bind(&plan.integration_sha).execute(store.pool()).await.unwrap();
    }
    assert!(store
        .complete_workflow_execution(&plan.run_id, 1, 1)
        .await
        .unwrap_err()
        .to_string()
        .contains("human stage gate"));
    sqlx::query("UPDATE workflowStageGates SET status='approved' WHERE run_id=?")
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
}

#[tokio::test]
async fn execution_attention_cannot_overwrite_a_later_human_command() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    start(&store, &plan).await;
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
    store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "resume".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            expected_sequence: state.sequence,
            action: WorkflowExecutionAction::Start,
        })
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
async fn execution_step_is_inert_until_started_and_preserves_operation_identity() {
    let (dir, store, proposal) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    assert!(matches!(
        store
            .workflow_execution_step(&plan.run_id, 1)
            .await
            .unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    start(&store, &plan).await;
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
    let f = super::workflow_integration_tests::fixture::Fixture::new().await;
    start(&f.store, &f.plan).await;
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
