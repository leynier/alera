use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

async fn integrate_fixture_stage(store: &RuntimeStore, run: &str, stage: &str, sha: &str) {
    let task: String =
        sqlx::query_scalar("SELECT task_id FROM workflowPlanTasks WHERE run_id=? AND logical_id=?")
            .bind(run)
            .bind(stage)
            .fetch_one(store.pool())
            .await
            .unwrap();
    sqlx::query("UPDATE orchestrationTasks SET status='completed',result='validated' WHERE id=?")
        .bind(&task)
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("INSERT INTO workflowTaskEvidence(task_id,result_digest,artifact_digest,integration_sha) VALUES (?,?,?,?)")
        .bind(task).bind(super::workflow_plan::workflow_digest(&Some("validated".to_owned())).unwrap())
        .bind("artifacts").bind(sha).execute(store.pool()).await.unwrap();
}

#[tokio::test]
async fn workflow_controls_project_gate_eligibility_without_exposing_profiles_or_results() {
    let (dir, store, proposal) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    let view = store
        .workflow_run_controls(&plan.run_id, Some(1))
        .await
        .unwrap();
    assert!(!view.can_control);
    assert!(view.execution.is_none());
    assert!(view.stages.iter().all(|stage| !stage.can_review));
    assert!(store
        .workflow_run_controls(&plan.run_id, Some(2))
        .await
        .is_err());
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    integrate_fixture_stage(&store, &plan.run_id, "foundation", &plan.integration_sha).await;
    let view = store
        .workflow_run_controls(&plan.run_id, Some(1))
        .await
        .unwrap();
    assert!(view.can_control);
    assert!(
        view.stages
            .iter()
            .find(|stage| stage.id == "foundation")
            .unwrap()
            .can_review
    );
    assert!(
        !view
            .stages
            .iter()
            .find(|stage| stage.gate == Some(WorkflowHumanGate::Product))
            .unwrap()
            .can_review
    );
    let json = serde_json::to_string(&view).unwrap();
    assert!(!json.contains("User instructions"));
    assert!(!json.contains("command"));
    assert!(!json.contains("validated"));
    sqlx::query(
        "UPDATE orchestrationTasks SET result='changed' WHERE run_id=? AND stage_id='foundation'",
    )
    .bind(&plan.run_id)
    .execute(store.pool())
    .await
    .unwrap();
    let view = store
        .workflow_run_controls(&plan.run_id, None)
        .await
        .unwrap();
    assert!(
        !view
            .stages
            .iter()
            .find(|stage| stage.id == "foundation")
            .unwrap()
            .can_review
    );
}

#[tokio::test]
async fn workflow_controls_require_ancestor_gates_and_active_owner() {
    let (dir, store, proposal) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(proposal, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    for stage in &plan.plan.recipe.recipe.stages {
        integrate_fixture_stage(&store, &plan.run_id, &stage.id, &plan.integration_sha).await;
    }
    let view = store
        .workflow_run_controls(&plan.run_id, None)
        .await
        .unwrap();
    assert!(
        !view
            .stages
            .iter()
            .find(|stage| stage.gate == Some(WorkflowHumanGate::Product))
            .unwrap()
            .can_review
    );
    sqlx::query(
        "UPDATE workflowStageGates SET status='approved' WHERE run_id=? AND stage_id='foundation'",
    )
    .bind(&plan.run_id)
    .execute(store.pool())
    .await
    .unwrap();
    let view = store
        .workflow_run_controls(&plan.run_id, None)
        .await
        .unwrap();
    assert!(
        view.stages
            .iter()
            .find(|stage| stage.gate == Some(WorkflowHumanGate::Product))
            .unwrap()
            .can_review
    );
    store
        .stop_orchestration_coordinator_run(&plan.run_id, "stopped")
        .await
        .unwrap();
    let view = store
        .workflow_run_controls(&plan.run_id, None)
        .await
        .unwrap();
    assert!(!view.can_control);
    assert!(view.stages.iter().all(|stage| !stage.can_review));
}
