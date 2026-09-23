use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::*;
use crate::workflow_approval::WorkflowDecision;

#[tokio::test]
async fn workflow_controls_preserve_cancellation_sequence_across_correction_revisions() {
    use crate::workflow_approval::{DesktopWorkflowCredential, WorkflowApprovalStatement};
    for prepare_correction in [false, true] {
        let (dir, store, mut proposal) = fixture(false).await;
        let plan = store
            .prepare_workflow_plan(proposal.clone(), valid_profile)
            .await
            .unwrap();
        decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
        let command = |id: &str, revision, expected_sequence, action| ControlWorkflowExecution {
            request_id: id.into(),
            run_id: plan.run_id.clone(),
            revision,
            expected_sequence,
            action,
        };
        store
            .control_workflow_execution(&command("start", 1, 0, WorkflowExecutionAction::Start))
            .await
            .unwrap();
        if prepare_correction {
            assert!(store
                .pause_workflow_execution_for_attention(
                    &plan.run_id,
                    1,
                    1,
                    "Inspect the prior revision",
                )
                .await
                .unwrap());
        } else {
            store
                .control_workflow_execution(&command("pause", 1, 1, WorkflowExecutionAction::Pause))
                .await
                .unwrap();
        }
        let statement = WorkflowApprovalStatement {
            challenge: store
                .workflow_approval_challenge(&plan.run_id, 1, "correction", "desktop")
                .await
                .unwrap(),
            decision: WorkflowDecision::RequestChanges,
            reason: "Review a corrective plan".into(),
        };
        let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
        store
            .decide_workflow(
                key.verify(statement.clone(), &key.sign(&statement).unwrap())
                    .unwrap(),
                "desktop",
            )
            .await
            .unwrap();
        let revision = if prepare_correction {
            proposal.request_id = "corrected-plan".into();
            proposal.run_id = Some(plan.run_id.clone());
            proposal.expected_revision = Some(2);
            store
                .prepare_workflow_plan(proposal, valid_profile)
                .await
                .unwrap()
                .revision
        } else {
            2
        };
        let view = store
            .workflow_run_controls(&plan.run_id, Some(revision))
            .await
            .unwrap();
        assert!(view.can_cancel);
        assert!(!view.can_control);
        let execution = view.execution.unwrap();
        assert_eq!(execution.revision, revision);
        assert_eq!(execution.sequence, 2);
        assert_eq!(execution.status, "paused");
        assert!(execution.attention.is_none());
        if prepare_correction {
            let retained_revision: i64 =
                sqlx::query_scalar("SELECT revision FROM workflowExecutionIssues WHERE run_id=?")
                    .bind(&plan.run_id)
                    .fetch_one(store.pool())
                    .await
                    .unwrap();
            assert_eq!(retained_revision, 1);
        }
        assert!(matches!(
            store
                .workflow_execution_step(&plan.run_id, revision)
                .await
                .unwrap(),
            WorkflowExecutionStep::Waiting
        ));
        assert!(store
            .control_workflow_execution(&command(
                "stale-cancel",
                1,
                2,
                WorkflowExecutionAction::Cancel
            ))
            .await
            .is_err());
        assert!(store
            .control_workflow_execution(&command(
                "unapproved-start",
                revision,
                2,
                WorkflowExecutionAction::Start
            ))
            .await
            .is_err());
        let cancel = command(
            "cancel",
            revision,
            execution.sequence,
            WorkflowExecutionAction::Cancel,
        );
        let receipt = store.control_workflow_execution(&cancel).await.unwrap();
        assert_eq!(receipt.status, "cancelled");
        assert_eq!(receipt.sequence, 3);
        assert_eq!(
            store
                .control_workflow_execution(&cancel)
                .await
                .unwrap()
                .sequence,
            3
        );
    }
}

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
