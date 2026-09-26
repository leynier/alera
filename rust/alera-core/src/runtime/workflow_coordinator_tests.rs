use super::workflow_plan_tests::{fixture, valid_profile};
use super::*;

#[tokio::test]
async fn workflow_proposal_cancellation_retry_is_explicit_and_sequence_fenced() {
    let (dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    store.reserve_workflow_coordinator(&draft).await.unwrap();
    let first = store.cancel_workflow_proposal(&draft.id).await.unwrap();
    assert!(store
        .retry_workflow_proposal_cancellation(&draft.id, 0)
        .await
        .is_err());
    store
        .settle_workflow_proposal_cancellation(&first, Some("identity changed"))
        .await
        .unwrap();
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert!(reopened
        .pending_workflow_proposal_cancellations()
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        reopened
            .cancel_workflow_proposal(&draft.id)
            .await
            .unwrap()
            .status,
        "attention"
    );
    let retry = reopened
        .retry_workflow_proposal_cancellation(&draft.id, 0)
        .await
        .unwrap();
    assert_eq!(retry.sequence, 1);
    assert_eq!(retry.status, "pending");
    assert!(retry.error.is_none());
    assert!(reopened
        .settle_workflow_proposal_cancellation(&first, None)
        .await
        .is_err());
    reopened
        .settle_workflow_proposal_cancellation(&retry, Some("still changed"))
        .await
        .unwrap();
    let replay = reopened
        .retry_workflow_proposal_cancellation(&draft.id, 0)
        .await
        .unwrap();
    assert_eq!(replay.status, "attention");
    assert_eq!(replay.sequence, 1);
    let final_attempt = reopened
        .retry_workflow_proposal_cancellation(&draft.id, 1)
        .await
        .unwrap();
    reopened
        .settle_workflow_proposal_cancellation(&final_attempt, None)
        .await
        .unwrap();
    assert_eq!(
        reopened
            .retry_workflow_proposal_cancellation(&draft.id, 1)
            .await
            .unwrap()
            .status,
        "settled"
    );
    assert!(reopened
        .retry_workflow_proposal_cancellation(&draft.id, 3)
        .await
        .is_err());
}

#[tokio::test]
async fn workflow_proposal_cancel_and_submit_have_one_atomic_winner() {
    let (_dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (cancel, submit) = tokio::join!(
        store.cancel_workflow_proposal(&draft.id),
        store.submit_workflow_proposal(&draft.id, tasks)
    );
    assert_ne!(cancel.is_ok(), submit.is_ok());
    assert_eq!(
        store
            .workflow_proposal_cancellation(&draft.id)
            .await
            .unwrap()
            .is_some(),
        cancel.is_ok()
    );
}

#[tokio::test]
async fn workflow_proposal_cancellation_fences_launch_and_late_submission_after_restart() {
    let (dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (one, two) = tokio::join!(
        store.cancel_workflow_proposal(&draft.id),
        store.cancel_workflow_proposal(&draft.id)
    );
    assert_eq!(one.unwrap().status, "settled");
    assert_eq!(two.unwrap().status, "settled");
    let page = store
        .workflow_proposals(WorkflowProposalQuery::default())
        .await
        .unwrap();
    assert_eq!(
        page.entries[0].cancellation_status.as_deref(),
        Some("settled")
    );
    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    assert!(reopened.reserve_workflow_coordinator(&draft).await.is_err());
    assert!(reopened
        .submit_workflow_proposal(&draft.id, tasks)
        .await
        .is_err());
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM workflowRuns")
        .fetch_one(reopened.pool())
        .await
        .unwrap();
    assert_eq!(count, 0);
}

#[tokio::test]
async fn workflow_proposal_cancellation_retains_exact_coordinator_target() {
    let (_dir, store, mut request) = fixture(false).await;
    request.proposal.tasks.clear();
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (coordinator, _) = store.reserve_workflow_coordinator(&draft).await.unwrap();
    let receipt = store.cancel_workflow_proposal(&draft.id).await.unwrap();
    assert_eq!(receipt.status, "pending");
    assert_eq!(receipt.tab_id.as_deref(), Some(coordinator.tab_id.as_str()));
    assert_eq!(receipt.workspace_id, coordinator.workspace_id);
    assert!(store.reserve_workflow_coordinator(&draft).await.is_err());
}

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
    let recovered = store
        .workflow_coordinator(&draft.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, "attention");
    assert!(recovered.error.unwrap().contains("did not survive"));
    assert!(store
        .require_workflow_coordinator_spawnable(&receipt.tab_id)
        .await
        .is_err());
    sqlx::query("UPDATE workspaces SET instanceId = 'replacement' WHERE id = 'workspace'")
        .execute(store.pool())
        .await
        .unwrap();
    assert!(store.reserve_workflow_coordinator(&draft).await.is_err());
}

#[tokio::test]
async fn submitted_coordinator_stays_started_after_restart() {
    let (_dir, store, mut request) = fixture(false).await;
    let tasks = std::mem::take(&mut request.proposal.tasks);
    let draft = store
        .create_workflow_proposal(request, valid_profile)
        .await
        .unwrap();
    let (receipt, _) = store.reserve_workflow_coordinator(&draft).await.unwrap();
    store
        .settle_workflow_coordinator(&draft.id, &receipt.tab_id, None)
        .await
        .unwrap();
    store
        .submit_workflow_proposal(&draft.id, tasks)
        .await
        .unwrap();

    store.recover_workflow_coordinators().await.unwrap();
    let recovered = store
        .workflow_coordinator(&draft.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, "started");
    assert!(recovered.error.is_none());
}
