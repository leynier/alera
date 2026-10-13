//! A plan gate's request for changes: the placeholder revision, the
//! cancelled tasks and the next proposal.

use super::run_plan_tests::{decision, fixture, run_status, valid_profile, WorkflowDecision};

#[tokio::test]
async fn request_changes_keeps_a_traceable_placeholder_and_waits_for_a_new_plan() {
    let (dir, store, request) = fixture(false).await;
    let plan = store
        .prepare_workflow_plan(request.clone(), valid_profile)
        .await
        .unwrap();
    let receipt = decision(dir.path(), &store, &plan, WorkflowDecision::RequestChanges).await;
    assert!(receipt.changes_requested);
    assert_eq!(receipt.plan_revision, Some(2));
    assert_eq!(receipt.run_status.as_deref(), Some("planning"));
    let placeholder = store
        .workflow_plan_revision(&plan.run_id, None)
        .await
        .unwrap();
    assert_eq!(placeholder.previous_revision, Some(1));
    assert!(placeholder.change_reason.is_some());
    let cancelled: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM orchestrationTasks WHERE run_id = ? AND status = 'cancelled'",
    )
    .bind(&plan.run_id)
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(cancelled, 2);
    let mut next = request;
    next.request_id = uuid::Uuid::new_v4().to_string();
    next.run_id = Some(plan.run_id.clone());
    next.expected_revision = Some(2);
    let revised = store
        .prepare_workflow_plan(next, valid_profile)
        .await
        .unwrap();
    assert_eq!(revised.revision, 3);
    assert_eq!(run_status(&store, &plan.run_id).await, "awaitingApproval");
    let rejected = decision(dir.path(), &store, &revised, WorkflowDecision::Reject).await;
    assert_eq!(rejected.run_status.as_deref(), Some("cancelled"));
    let kinds: Vec<String> =
        sqlx::query_scalar("SELECT kind FROM runEvents WHERE run_id = ? ORDER BY sequence")
            .bind(&plan.run_id)
            .fetch_all(store.pool())
            .await
            .unwrap();
    for kind in [
        "created",
        "planProposed",
        "changesRequested",
        "planRejected",
        "cancelled",
    ] {
        assert!(kinds.iter().any(|value| value == kind), "{kind}: {kinds:?}");
    }
}
