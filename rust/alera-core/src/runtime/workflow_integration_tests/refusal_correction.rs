use super::*;
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

#[tokio::test]
async fn terminal_refusal_retains_evidence_and_allows_only_signed_request_changes() {
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
            .workflow_state
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
    let workflow = inspection.workflow.unwrap();
    assert_eq!(workflow.state, "refused");
    assert!(workflow.error.unwrap().contains("submodule changes"));
    let scope = format!("integration:{}", refused.request.id);
    assert!(fixture
        .store
        .workflow_approval_challenge(&fixture.plan.run_id, 1, "plan", "desktop")
        .await
        .is_err());
    assert!(fixture
        .store
        .workflow_approval_challenge(&fixture.plan.run_id, 1, "stage:fix", "desktop")
        .await
        .is_err());
    let challenge = fixture
        .store
        .workflow_approval_challenge(&fixture.plan.run_id, 1, &scope, "desktop")
        .await
        .unwrap();
    let key = DesktopWorkflowCredential::load_or_create(fixture.directory.path()).unwrap();
    for decision in [WorkflowDecision::Approve, WorkflowDecision::Reject] {
        let statement = WorkflowApprovalStatement {
            challenge: challenge.clone(),
            decision,
            reason: "Review".into(),
        };
        let proof = key.sign(&statement).unwrap();
        assert!(fixture
            .store
            .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
            .await
            .is_err());
    }
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::RequestChanges,
        reason: "Prepare a correction without a submodule change".into(),
    };
    let proof = key.sign(&statement).unwrap();
    let decision = fixture
        .store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .unwrap();
    assert_eq!(decision.current_revision, 2);
    let (status, revision): (String, i64) =
        sqlx::query_as("SELECT status, revision FROM workflowRuns WHERE run_id = ?")
            .bind(&fixture.plan.run_id)
            .fetch_one(fixture.store.pool())
            .await
            .unwrap();
    assert_eq!((status.as_str(), revision), ("changesRequested", 2));
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
async fn uncertain_integration_attention_cannot_use_the_correction_scope() {
    let fixture = Fixture::new().await;
    let reserved = fixture.reserve().await;
    fixture
        .store
        .workflow_integration_attention(&reserved.request.id, "checkout outcome unknown")
        .await
        .unwrap();
    assert!(fixture
        .store
        .workflow_approval_challenge(
            &fixture.plan.run_id,
            1,
            &format!("integration:{}", reserved.request.id),
            "desktop"
        )
        .await
        .is_err());
}

#[tokio::test]
async fn correction_challenge_becomes_stale_when_refusal_evidence_changes() {
    let fixture = Fixture::new().await;
    let reserved = fixture.reserve().await;
    fixture
        .store
        .record_workflow_integration_preparation(
            &reserved.request.id,
            &WorkflowGitPreparation::Refused {
                paths: vec!["module".into()],
                truncated: false,
                reason: "submodule changes require explicit integration outside this workflow"
                    .into(),
            },
        )
        .await
        .unwrap();
    let challenge = fixture
        .store
        .workflow_approval_challenge(
            &fixture.plan.run_id,
            1,
            &format!("integration:{}", reserved.request.id),
            "desktop",
        )
        .await
        .unwrap();
    sqlx::query("UPDATE workflowIntegrations SET error = ? WHERE id = ?")
        .bind("reviewed refusal details changed")
        .bind(&reserved.request.id)
        .execute(fixture.store.pool())
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::RequestChanges,
        reason: "Correct this result".into(),
    };
    let key = DesktopWorkflowCredential::load_or_create(fixture.directory.path()).unwrap();
    let proof = key.sign(&statement).unwrap();
    assert!(fixture
        .store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .unwrap_err()
        .to_string()
        .contains("stale"));
}
