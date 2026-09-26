use super::workflow_plan::workflow_digest;
use super::workflow_plan_tests::{decision, fixture, valid_profile};
use super::workflow_workspace_eligibility::eligible_task;
use super::*;
use crate::workflow_approval::{
    DesktopWorkflowCredential, WorkflowApprovalStatement, WorkflowDecision,
};

#[tokio::test]
async fn workflow_workspaces_require_the_current_approved_plan() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    let mut candidate = store.find_workspace("workspace").await.unwrap().unwrap();
    candidate.id = uuid::Uuid::new_v4().to_string();
    candidate.instance_id = uuid::Uuid::new_v4().to_string();
    candidate.kind = WorkspaceKind::Linked;
    candidate.branch = Some(format!("alera/workflows/{}", candidate.id));
    candidate.path = dir
        .path()
        .join(&candidate.id)
        .to_string_lossy()
        .into_owned();
    let request = PrepareWorkflowWorkspace {
        request_id: "prepare-resource".into(),
        run_id: plan.run_id.clone(),
        revision: 1,
        task_id: None,
        retry_of: None,
    };
    assert!(store
        .reserve_workflow_workspace(&request, candidate.clone())
        .await
        .is_err());
    decision(dir.path(), &store, &plan, WorkflowDecision::Reject).await;
    assert!(store
        .reserve_workflow_workspace(&request, candidate)
        .await
        .is_err());
    assert!(store
        .workflow_workspaces(&WorkflowWorkspaceQuery {
            run_id: plan.run_id,
            before_row: None,
            limit: None,
        })
        .await
        .unwrap()
        .items
        .is_empty());
}

#[tokio::test]
async fn workflow_workspaces_require_integrated_prerequisites_and_human_foundation_gate() {
    let (dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap();
    decision(dir.path(), &store, &plan, WorkflowDecision::Approve).await;
    let foundation: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'foundation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let implementation: String = sqlx::query_scalar(
        "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'implementation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    sqlx::query(
        "UPDATE orchestrationTasks SET status = 'completed', result = 'result' WHERE id = ?",
    )
    .bind(&foundation)
    .execute(store.pool())
    .await
    .unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    assert!(
        eligible_task(&mut tx, &plan.run_id, 1, &implementation, &plan.plan)
            .await
            .unwrap_err()
            .to_string()
            .contains("integrated")
    );
    tx.rollback().await.unwrap();
    sqlx::query("INSERT INTO workflowTaskEvidence VALUES (?, ?, 'artifacts', ?)")
        .bind(&foundation)
        .bind(workflow_digest(&Some("result".to_string())).unwrap())
        .bind(&plan.integration_sha)
        .execute(store.pool())
        .await
        .unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    assert!(
        eligible_task(&mut tx, &plan.run_id, 1, &implementation, &plan.plan)
            .await
            .unwrap_err()
            .to_string()
            .contains("human gate")
    );
    tx.rollback().await.unwrap();
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let statement = WorkflowApprovalStatement {
        challenge: store
            .workflow_approval_challenge(&plan.run_id, 1, "stage:foundation", "desktop")
            .await
            .unwrap(),
        decision: WorkflowDecision::Approve,
        reason: "Reviewed integrated evidence".into(),
    };
    store
        .decide_workflow(
            key.verify(statement.clone(), &key.sign(&statement).unwrap())
                .unwrap(),
            "desktop",
        )
        .await
        .unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    eligible_task(&mut tx, &plan.run_id, 1, &implementation, &plan.plan)
        .await
        .unwrap();
    tx.rollback().await.unwrap();
    sqlx::query("UPDATE workflowTaskEvidence SET result_digest = 'stale' WHERE task_id = ?")
        .bind(foundation)
        .execute(store.pool())
        .await
        .unwrap();
    let mut tx = store.pool().begin().await.unwrap();
    assert!(
        eligible_task(&mut tx, &plan.run_id, 1, &implementation, &plan.plan)
            .await
            .is_err()
    );
}
