use super::workflow_plan_tests::{fixture, valid_profile};
use super::*;

#[tokio::test]
async fn workflow_coordinator_has_one_launch_winner_across_reconnect_and_restart() {
    let (dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (first, second) = tokio::join!(
        store.reserve_workflow_coordinator(&draft),
        store.reserve_workflow_coordinator(&draft)
    );
    let (first, first_won) = first.unwrap();
    let (second, second_won) = second.unwrap();
    assert_ne!(first_won, second_won);
    assert_eq!(first.tab_id, second.tab_id);
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    reopened.recover_workflow_coordinators().await.unwrap();
    let (replay, won) = reopened.reserve_workflow_coordinator(&draft).await.unwrap();
    assert!(!won);
    assert_eq!(replay.tab_id, first.tab_id);
    assert_eq!(replay.status, "attention");
    assert!(replay.error.is_some());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationTasks")
        .fetch_one(store.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[tokio::test]
async fn workflow_coordinator_completion_and_source_identity_are_bound() {
    let (_dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (receipt, won) = store.reserve_workflow_coordinator(&draft).await.unwrap();
    assert!(won);
    assert!(store
        .settle_workflow_coordinator(&draft.id, "other-tab", None)
        .await
        .is_err());
    let settled = store
        .settle_workflow_coordinator(&draft.id, &receipt.tab_id, None)
        .await
        .unwrap();
    assert_eq!(settled.status, "started");
    let status = store.workflow_proposal_status(&draft.id).await.unwrap();
    assert!(status.run_id.is_none());
    assert_eq!(status.coordinator.unwrap().tab_id, receipt.tab_id);
    store.recover_workflow_coordinators().await.unwrap();
    assert_eq!(
        store
            .workflow_coordinator(&draft.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "started"
    );
    sqlx::query("UPDATE workspaces SET instanceId = 'replacement' WHERE id = 'workspace'")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store.reserve_workflow_coordinator(&draft).await.is_err());
}
