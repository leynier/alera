use serde_json::json;
use sqlx::Row;

use super::workflow_plan::workflow_digest;
use super::workflow_plan_tests::{decision, fixture, valid_profile};

#[tokio::test]
async fn workflow_concurrent_approval_is_idempotent_and_other_challenges_become_stale() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let statement = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
            .await
            .unwrap(),
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let other = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
            .await
            .unwrap(),
        ..statement.clone()
    };
    let proof = key.sign(&statement).unwrap();
    let (first, second) = tokio::join!(
        store.decide_workflow(key.verify(statement.clone(), &proof).unwrap(), "desktop"),
        store.decide_workflow(key.verify(statement, &proof).unwrap(), "desktop"),
    );
    assert_eq!(first.unwrap().decision_id, second.unwrap().decision_id);
    let proof = key.sign(&other).unwrap();
    assert!(store
        .decide_workflow(key.verify(other, &proof).unwrap(), "desktop")
        .await
        .is_err());
    let tasks: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks WHERE run_id = ?")
        .bind(&plan.run_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(tasks, 2);
}

#[tokio::test]
async fn workflow_approval_rejects_a_replaced_owner_workspace() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let statement = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "plan", "desktop")
            .await
            .unwrap(),
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let proof = key.sign(&statement).unwrap();
    sqlx::query("UPDATE workspaces SET instanceId = 'replacement' WHERE id = 'workspace'")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .is_err());
    let tasks: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(tasks, 0);
}
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

#[tokio::test]
async fn workflow_stage_gate_binds_artifact_evidence_and_preserves_completed_correction_history() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let rows = sqlx::query("SELECT task_id, logical_id FROM workflowPlanTasks WHERE run_id = ?")
        .bind(&plan.run_id)
        .fetch_all(store.pool())
        .await
        .unwrap();
    for row in &rows {
        let result = json!({"summary":"Completed"}).to_string();
        let task_id: String = row.try_get("task_id").unwrap();
        sqlx::query("UPDATE orchestrationTasks SET status = 'completed', result = ? WHERE id = ?")
            .bind(&result)
            .bind(&task_id)
            .execute(store.pool())
            .await
            .unwrap();
        sqlx::query("INSERT INTO workflowTaskEvidence(task_id,result_digest,artifact_digest,integration_sha) VALUES(?,?,?,?)")
            .bind(&task_id).bind(workflow_digest(&result).unwrap())
            .bind("artifact-content-digest").bind(&plan.integration_sha).execute(store.pool()).await.unwrap();
    }
    // Completed Product work cannot substitute for human Foundation approval.
    assert!(store
        .workflow_approval_challenge(&plan.run_id, 1, "stage:product", "desktop")
        .await
        .is_err());
    let challenge = store
        .workflow_approval_challenge(&plan.run_id, 1, "stage:foundation", "desktop")
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let proof = key.sign(&statement).unwrap();
    let foundation_id: String = rows
        .iter()
        .find(|row| row.try_get::<String, _>("logical_id").unwrap() == "foundation")
        .unwrap()
        .try_get("task_id")
        .unwrap();
    sqlx::query("UPDATE workflowTaskEvidence SET artifact_digest = 'changed' WHERE task_id = ?")
        .bind(&foundation_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .is_err());
    let challenge = store
        .workflow_approval_challenge(&plan.run_id, 1, "stage:foundation", "desktop")
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let proof = key.sign(&statement).unwrap();
    store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .unwrap();
    let challenge = store
        .workflow_approval_challenge(&plan.run_id, 1, "stage:product", "desktop")
        .await
        .unwrap();
    let statement = WorkflowApprovalStatement {
        challenge,
        decision: WorkflowDecision::RequestChanges,
        reason: "Add missing coverage".into(),
    };
    let proof = key.sign(&statement).unwrap();
    let receipt = store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .unwrap();
    assert_eq!(receipt.current_revision, 2);
    let complete: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM orchestrationTasks WHERE run_id = ? AND status = 'completed'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(complete, 3);
    let audits: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowDecisions WHERE run_id = ?")
        .bind(&plan.run_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(audits, 3);
}

#[tokio::test]
async fn workflow_evidence_changes_invalidate_an_already_approved_gate() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let id: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'foundation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "UPDATE orchestrationTasks SET status = 'completed', result = 'result' WHERE id = ?",
    )
    .bind(&id)
    .execute(store.pool())
    .await
    .unwrap();
    sqlx::query("INSERT INTO workflowTaskEvidence VALUES (?, ?, 'artifacts', ?)")
        .bind(&id)
        .bind(workflow_digest(&"result").unwrap())
        .bind(&plan.integration_sha)
        .execute(store.pool())
        .await
        .unwrap();
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let statement = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "stage:foundation", "desktop")
            .await
            .unwrap(),
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let proof = key.sign(&statement).unwrap();
    store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .unwrap();
    sqlx::query("UPDATE workflowTaskEvidence SET artifact_digest = 'changed' WHERE task_id = ?")
        .bind(id)
        .execute(store.pool())
        .await
        .unwrap();
    let status: String = sqlx::query_scalar(
        "SELECT status FROM workflowStageGates WHERE run_id = ? AND stage_id = 'foundation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(status, "pending");
}
