use sqlx::Row;

use super::{
    NewOrchestrationTask, OrchestrationCoordinatorStatus, OrchestrationPolicyStatus, RuntimeStore,
};

async fn store() -> (tempfile::TempDir, RuntimeStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    (dir, store)
}

const POLICY: &str = r#"{"version":1,"stages":[{"id":"impl","profile":"Codex Sol"}]}"#;

#[tokio::test]
async fn a_new_run_starts_without_a_policy() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    assert_eq!(run.execution_policy, None);
    assert_eq!(run.execution_policy_status, OrchestrationPolicyStatus::None);
    // A run with no policy must keep scheduling exactly as before.
    assert!(!run.execution_policy_status.blocks_dispatch());
}

#[tokio::test]
async fn proposing_parks_the_run_as_draft_and_blocks_dispatch() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    let proposed = store
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .unwrap();

    assert_eq!(proposed.execution_policy.as_deref(), Some(POLICY));
    assert_eq!(
        proposed.execution_policy_status,
        OrchestrationPolicyStatus::Draft
    );
    assert!(proposed.execution_policy_status.blocks_dispatch());
    assert!(proposed.execution_policy_updated_at.is_some());
}

#[tokio::test]
async fn approving_unblocks_dispatch_and_rejecting_does_too() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();
    store
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .unwrap();

    let approved = store
        .resolve_orchestration_execution_policy(&run.id, true)
        .await
        .unwrap();
    assert_eq!(
        approved.execution_policy_status,
        OrchestrationPolicyStatus::Approved
    );
    assert!(!approved.execution_policy_status.blocks_dispatch());

    // Re-proposing is how a rejected or approved plan is revised.
    store
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .unwrap();
    let rejected = store
        .resolve_orchestration_execution_policy(&run.id, false)
        .await
        .unwrap();
    assert_eq!(
        rejected.execution_policy_status,
        OrchestrationPolicyStatus::Rejected
    );
    assert!(!rejected.execution_policy_status.blocks_dispatch());
}

#[tokio::test]
async fn resolving_without_a_pending_proposal_is_rejected() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();

    let error = store
        .resolve_orchestration_execution_policy(&run.id, true)
        .await
        .unwrap_err();
    assert!(
        error.to_string().contains("awaiting a decision"),
        "unexpected error: {error}"
    );

    // A decision cannot be silently overwritten by a second approval either.
    store
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .unwrap();
    store
        .resolve_orchestration_execution_policy(&run.id, true)
        .await
        .unwrap();
    assert!(store
        .resolve_orchestration_execution_policy(&run.id, false)
        .await
        .is_err());
}

#[tokio::test]
async fn proposing_for_a_finished_run_is_rejected() {
    let (_dir, store) = store().await;
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();
    store
        .finish_orchestration_coordinator_run(&run.id, OrchestrationCoordinatorStatus::Completed)
        .await
        .unwrap();

    assert!(store
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .is_err());
}

#[tokio::test]
async fn a_task_can_be_bound_to_a_stage() {
    let (_dir, store) = store().await;
    let task = store
        .create_orchestration_task(NewOrchestrationTask {
            spec: "implement".to_string(),
            task_title: None,
            display_name: None,
            deps: Vec::new(),
            parent_id: None,
            created_by_terminal_handle: Some("coord".to_string()),
            run_id: None,
            workspace_id: "ws".to_string(),
            coordinator_handle: "coord".to_string(),
            result_schema: None,
        })
        .await
        .unwrap();
    assert_eq!(task.stage_id, None);

    store
        .set_orchestration_task_stage(&task.id, Some("impl"))
        .await
        .unwrap();
    let stored = store.orchestration_task_by_id(&task.id).await.unwrap();
    assert_eq!(stored.unwrap().stage_id.as_deref(), Some("impl"));

    assert!(store
        .set_orchestration_task_stage("task_missing", Some("impl"))
        .await
        .is_err());
}

/// The orchestration tables are created with `CREATE TABLE IF NOT EXISTS`, so a
/// database that predates these columns is only migrated by `ensure_column`.
/// This reproduces that database shape and asserts the data survives.
#[tokio::test]
async fn policy_columns_are_backfilled_on_a_preexisting_database() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let run = store
        .create_orchestration_coordinator_run("audit", Some("coord"), 2000)
        .await
        .unwrap();
    let pool = store.pool().clone();
    for column in [
        "execution_policy",
        "execution_policy_status",
        "execution_policy_updated_at",
    ] {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "ALTER TABLE orchestrationCoordinatorRuns DROP COLUMN {column}"
        )))
        .execute(&pool)
        .await
        .unwrap();
    }
    drop(store);

    let reopened = RuntimeStore::open(dir.path()).await.unwrap();
    let migrated = reopened
        .orchestration_coordinator_run_by_id(&run.id)
        .await
        .unwrap()
        .expect("run survived the migration");
    assert_eq!(migrated.spec, "audit");
    assert_eq!(
        migrated.execution_policy_status,
        OrchestrationPolicyStatus::None
    );

    // The backfilled column must still accept a proposal.
    let proposed = reopened
        .propose_orchestration_execution_policy(&run.id, POLICY)
        .await
        .unwrap();
    assert_eq!(
        proposed.execution_policy_status,
        OrchestrationPolicyStatus::Draft
    );
    let count: i64 = sqlx::query("SELECT COUNT(*) AS total FROM orchestrationCoordinatorRuns")
        .fetch_one(reopened.pool())
        .await
        .unwrap()
        .get("total");
    assert_eq!(count, 1);
}
