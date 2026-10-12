use super::run_plan::workflow_digest;
use super::run_plan_tests::{decision, fixture, stage_decision, valid_profile, WorkflowDecision};
use super::run_workspace_eligibility::eligible_task;
use super::*;

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
    candidate.branch = Some(format!("alera/runs/{}", candidate.id));
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
        "SELECT id FROM orchestrationTasks WHERE run_id = ? AND logical_id = 'foundation'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    let implementation: String = sqlx::query_scalar(
        "SELECT id FROM orchestrationTasks WHERE run_id = ? AND logical_id = 'implementation'",
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
    sqlx::query("INSERT INTO runTaskEvidence VALUES (?, ?, 'artifacts', ?)")
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
            .contains("stage gate")
    );
    tx.rollback().await.unwrap();
    let approved = stage_decision(
        &store,
        &plan.run_id,
        "foundation",
        WorkflowDecision::Approve,
    )
    .await
    .unwrap();
    assert_eq!(approved.run_status.as_deref(), Some("running"));
    let mut tx = store.pool().begin().await.unwrap();
    eligible_task(&mut tx, &plan.run_id, 1, &implementation, &plan.plan)
        .await
        .unwrap();
    tx.rollback().await.unwrap();
    sqlx::query("UPDATE runTaskEvidence SET result_digest = 'stale' WHERE task_id = ?")
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
