use super::*;
use crate::runtime::AutomationCleanupAttempt;
use chrono::Duration;

async fn state(store: &RuntimeStore, run: &AutomationRun) -> String {
    sqlx::query_scalar("SELECT state FROM automationSharedCleanupIntents WHERE runId = ?")
        .bind(&run.id)
        .fetch_one(store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn cleanup_intent_survives_restart_and_reserves_only_one_attempt() {
    let (directory, store, run, workspace) = successful().await;
    let now = Utc::now();
    store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .unwrap();
    let first = store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first.run, run);
    assert_eq!(first.workspace.instance_id, workspace.instance_id);
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert!(reopened
        .due_automation_shared_cleanups(now + Duration::seconds(119))
        .await
        .unwrap()
        .is_empty());
    assert!(reopened
        .claim_automation_shared_cleanup(&run.id, now + Duration::seconds(119))
        .await
        .unwrap()
        .is_none());
    let later = now + Duration::seconds(121);
    assert_eq!(
        reopened
            .due_automation_shared_cleanups(later)
            .await
            .unwrap(),
        vec![run.id.clone()]
    );
    let second = reopened
        .claim_automation_shared_cleanup(&run.id, later)
        .await
        .unwrap()
        .unwrap();
    assert_ne!(first.id, second.id);
    assert_eq!(second.run, first.run);
    assert_eq!(second.workspace.instance_id, first.workspace.instance_id);
    assert!(!reopened
        .settle_automation_shared_cleanup(&first, false, None, later)
        .await
        .unwrap());
    assert_eq!(state(&reopened, &run).await, "running");
}

#[tokio::test]
async fn retries_keep_original_snapshot_and_do_not_reactivate_preserved_intents() {
    let (_directory, store, run, workspace) = successful().await;
    let now = Utc::now();
    store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .unwrap();
    let attempt = store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    assert!(store
        .settle_automation_shared_cleanup(&attempt, true, Some("Host disconnected"), now)
        .await
        .unwrap());
    assert!(store
        .claim_automation_shared_cleanup(&run.id, now + Duration::seconds(59))
        .await
        .unwrap()
        .is_none());
    let later = now + Duration::seconds(61);
    let retry = store
        .claim_automation_shared_cleanup(&run.id, later)
        .await
        .unwrap()
        .unwrap();
    assert!(store
        .settle_automation_shared_cleanup(&retry, false, Some("User took over"), later)
        .await
        .unwrap());
    store
        .request_automation_shared_cleanup(&run, &workspace, later)
        .await
        .unwrap();
    assert_eq!(state(&store, &run).await, "preserved");
    assert!(store
        .due_automation_shared_cleanups(later + Duration::days(1))
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn only_matching_retirement_receipt_completes_cleanup() {
    let (_directory, store, run, workspace) = successful().await;
    let now = Utc::now();
    store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .unwrap();
    let attempt = store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    let mut wrong = attempt.clone();
    wrong.workspace.instance_id = "different-instance".into();
    assert!(!store
        .settle_automation_shared_cleanup(&wrong, false, None, now)
        .await
        .unwrap());
    assert!(store
        .settle_automation_shared_cleanup(&attempt, true, None, now)
        .await
        .unwrap());
    assert_eq!(state(&store, &run).await, "pending");
    store
        .retire_verified_automation_shared_workspace(&run, &workspace)
        .await
        .unwrap();
    let attempt = store
        .claim_automation_shared_cleanup(&run.id, now + Duration::seconds(61))
        .await
        .unwrap()
        .unwrap();
    assert!(store
        .settle_automation_shared_cleanup(&attempt, true, Some("Lost response"), now)
        .await
        .unwrap());
    assert_eq!(state(&store, &run).await, "completed");
    assert!(store
        .due_automation_shared_cleanups(now + Duration::days(1))
        .await
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn changed_run_cannot_replace_the_original_recovery_snapshot() {
    let (_directory, store, mut run, workspace) = successful().await;
    let now = Utc::now();
    store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .unwrap();
    let original = run.clone();
    run.taken_over = true;
    let run = store.save_automation_run(&run).await.unwrap();
    assert!(store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .is_err());
    let attempt: AutomationCleanupAttempt = store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(attempt.run, original);
    assert!(store
        .require_automation_shared_workspace_cleanup(&attempt.run, &attempt.workspace)
        .await
        .is_err());
    assert!(store.find_workspace(&workspace.id).await.unwrap().is_some());
}

#[tokio::test]
async fn retention_does_not_remove_a_run_needed_by_pending_cleanup() {
    let (_directory, store, run, workspace) = successful().await;
    let now = Utc::now();
    store
        .request_automation_shared_cleanup(&run, &workspace, now)
        .await
        .unwrap();
    store
        .prune_automation_history(now + Duration::days(400))
        .await
        .unwrap();
    assert!(store.find_automation_run(&run.id).await.unwrap().is_some());
    let attempt = store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    store
        .settle_automation_shared_cleanup(&attempt, false, Some("Preserved"), now)
        .await
        .unwrap();
    store
        .prune_automation_history(now + Duration::days(400))
        .await
        .unwrap();
    assert!(store.find_automation_run(&run.id).await.unwrap().is_none());
}
