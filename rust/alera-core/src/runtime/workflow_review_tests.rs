use super::workflow_plan::workflow_digest;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

#[tokio::test]
async fn workflow_review_binds_the_rendered_plan_without_materializing_tasks() {
    let (_dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let review = store
        .workflow_review(&plan.run_id, 1, "plan", "desktop")
        .await
        .unwrap();
    assert_eq!(review.plan.digest, review.challenge.plan_digest);
    assert_eq!(review.plan.source_sha, review.challenge.integration_sha);
    assert_eq!(review.plan.tasks.len(), plan.plan.tasks.len());
    assert!(review.tasks.is_empty());
    let tasks: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(tasks, 0);
    assert!(store
        .workflow_review(&plan.run_id, 2, "plan", "desktop")
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_review_bounds_evidence_and_keeps_the_displayed_challenge_stale() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let task: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'foundation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let result = "🚀".repeat(2048);
    sqlx::query("UPDATE orchestrationTasks SET status = 'completed', result = ? WHERE id = ?")
        .bind(&result)
        .bind(&task)
        .execute(store.pool())
        .await
        .unwrap();
    sqlx::query("INSERT INTO workflowTaskEvidence VALUES (?, ?, 'artifacts', ?)")
        .bind(&task)
        .bind(workflow_digest(&Some(result)).unwrap())
        .bind(&plan.integration_sha)
        .execute(store.pool())
        .await
        .unwrap();
    let review = store
        .workflow_review(&plan.run_id, 1, "stage:foundation", "desktop")
        .await
        .unwrap();
    assert_eq!(review.tasks.len(), 1);
    assert_eq!(review.tasks[0].task_id, task);
    assert_eq!(
        review.tasks[0]
            .result_preview
            .as_ref()
            .unwrap()
            .chars()
            .count(),
        1024
    );
    assert!(review.tasks[0].result_truncated);
    assert_eq!(
        review.tasks[0].artifact_digest.as_deref(),
        Some("artifacts")
    );
    let statement = WorkflowApprovalStatement {
        challenge: review.challenge,
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    };
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let proof = key.sign(&statement).unwrap();
    sqlx::query("UPDATE workflowTaskEvidence SET artifact_digest = 'changed' WHERE task_id = ?")
        .bind(&task)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store
        .decide_workflow(key.verify(statement, &proof).unwrap(), "desktop")
        .await
        .is_err());
    let refreshed = store
        .workflow_review(&plan.run_id, 1, "stage:foundation", "desktop")
        .await
        .unwrap();
    assert_eq!(
        refreshed.tasks[0].artifact_digest.as_deref(),
        Some("changed")
    );
}
