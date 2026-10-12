use std::{collections::HashMap, time::Duration};

use super::*;
use crate::managed_workspace::run::tests::{completed, fixture::Fixture};
use crate::terminal_host::server::actor_test_harness::test_actor;

async fn drain(
    actor: &mut ServerActor,
    commands: &mut crate::terminal_host::server::ServerInboxReceiver,
) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while actor.workflow_execution.cancelling {
        let command = tokio::time::timeout_at(deadline, commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(command).await;
    }
}

#[tokio::test]
async fn cancellation_job_failure_retries_with_backoff_and_preserves_dirty_wakes() {
    for dirty in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
        actor.inbox = inbox;
        actor.workflow_execution.cancelling = true;
        actor.workflow_execution.cancellation_dirty = dirty;
        actor.workflow_workspace_jobs = 1;
        actor
            .finish_workflow_cancellation(Err(HostError::state("transient page failure")))
            .await;
        assert!(actor.workflow_execution.cancelling);
        assert_eq!(actor.workflow_workspace_jobs, 1);
        assert_eq!(actor.workflow_execution.cancellation_dirty, dirty);
        assert!(
            tokio::time::timeout(Duration::from_millis(100), commands.recv())
                .await
                .is_err()
        );
        actor.wake_workflow_cancellation();
        assert_eq!(actor.workflow_workspace_jobs, 1, "no overlapping sweep");
        drain(&mut actor, &mut commands).await;
        assert_eq!(actor.workflow_workspace_jobs, 0);
        assert!(!actor.workflow_execution.cancellation_dirty);
        assert!(commands.try_recv().is_err());
        actor.dispose().await;
    }
}

async fn target_counts(fixture: &Fixture) -> (i64, i64, Option<String>) {
    let row: (i64, i64, Option<String>) = sqlx::query_as(
        "SELECT SUM(state = 'settled'), SUM(state <> 'settled'),
            MAX(CASE WHEN state = 'attention' THEN error END)
        FROM runCancellationTargets WHERE run_id = ?",
    )
    .bind(&fixture.plan.run_id)
    .fetch_one(fixture.store.pool())
    .await
    .unwrap();
    row
}

#[tokio::test]
async fn cancellation_settlement_failure_becomes_attention_and_continues_the_page() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    completed(&fixture, "fix", "fixed").await;
    completed(&fixture, "other", "other").await;
    let cancelled = fixture
        .control(alera_core::runtime::RunControlAction::Cancel)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER fail_run_settle BEFORE UPDATE ON runCancellationTargets
        WHEN NEW.state='settled' AND OLD.id=(SELECT MIN(id) FROM runCancellationTargets)
        BEGIN SELECT RAISE(ABORT, 'injected run settlement failure'); END",
    )
    .execute(fixture.store.pool())
    .await
    .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut commands) = crate::terminal_host::ServerInbox::channel();
    actor.inbox = inbox;
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    let (settled, open, error) = target_counts(&fixture).await;
    assert_eq!(settled, 1, "later page targets still settle");
    assert_eq!(open, 1);
    assert!(error.unwrap().contains("injected run"));
    sqlx::query("DROP TRIGGER fail_run_settle")
        .execute(fixture.store.pool())
        .await
        .unwrap();
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    assert!(
        target_counts(&fixture).await.2.is_some(),
        "attention is never retried automatically"
    );
    fixture
        .store
        .retry_run_cancellation(
            &alera_core::runtime::RetryRunCancellation {
                request_id: "retry".into(),
                run_id: fixture.plan.run_id.clone(),
                expected_sequence: cancelled.sequence,
            },
            &crate::managed_workspace::run::tests::fixture::desktop(),
        )
        .await
        .unwrap();
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    let (settled, open, _) = target_counts(&fixture).await;
    assert_eq!((settled, open), (2, 0));
    assert_eq!(actor.workflow_workspace_jobs, 0);
    actor.dispose().await;
}
