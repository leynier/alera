use std::{collections::HashMap, time::Duration};

use alera_core::runtime::{
    ControlWorkflowExecution, PrepareWorkflowPlan, WorkflowExecutionAction, WorkflowPlanProposal,
};

use super::*;
use crate::managed_workspace::workflow::tests::{completed, fixture::Fixture};
use crate::terminal_host::server::actor_test_harness::test_actor;

async fn drain(
    actor: &mut ServerActor,
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
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
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
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

#[tokio::test]
async fn cancellation_settlement_failure_becomes_attention_and_continues_the_page() {
    let fixture = Fixture::new("").await;
    fixture.integration().await;
    completed(&fixture, "fix", "fixed").await;
    completed(&fixture, "other", "other").await;
    let mut cancel = ControlWorkflowExecution {
        request_id: "cancel".into(),
        run_id: fixture.plan.run_id.clone(),
        revision: 1,
        expected_sequence: 0,
        action: WorkflowExecutionAction::Cancel,
    };
    fixture
        .store
        .control_workflow_execution(&cancel)
        .await
        .unwrap();
    let plan = &fixture.plan.plan;
    let proposal = fixture
        .store
        .create_workflow_proposal(
            PrepareWorkflowPlan {
                request_id: "cancel-proposal".into(),
                workspace_id: "owner".into(),
                run_id: None,
                expected_revision: None,
                proposal: WorkflowPlanProposal {
                    objective: "Propose a plan".into(),
                    source_sha: plan.source_sha.clone(),
                    recipe_source: plan.recipe.source.clone(),
                    expected_recipe_digest: plan.recipe.recipe.content_digest().unwrap(),
                    coordinator_profile_id: "profile".into(),
                    role_profiles: plan
                        .recipe
                        .recipe
                        .roles
                        .iter()
                        .map(|role| (role.id.clone(), "profile".into()))
                        .collect(),
                    max_concurrent: 2,
                    tasks: vec![],
                },
            },
            |_| Ok(()),
        )
        .await
        .unwrap();
    fixture
        .store
        .reserve_workflow_coordinator(&proposal)
        .await
        .unwrap();
    fixture
        .store
        .cancel_workflow_proposal(&proposal.id)
        .await
        .unwrap();
    sqlx::query(
        "CREATE TRIGGER fail_run_settle BEFORE UPDATE ON workflowCancellationTargets
        WHEN NEW.state='settled' AND OLD.id=(SELECT MIN(id) FROM workflowCancellationTargets)
        BEGIN SELECT RAISE(ABORT, 'injected run settlement failure'); END",
    )
    .execute(fixture.store.pool())
    .await
    .unwrap();
    sqlx::query(
        "CREATE TRIGGER fail_proposal_settle BEFORE UPDATE ON workflowProposalCancellations
        WHEN NEW.status='settled'
        BEGIN SELECT RAISE(ABORT, 'injected proposal settlement failure'); END",
    )
    .execute(fixture.store.pool())
    .await
    .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    let controls = fixture
        .store
        .workflow_run_controls(&fixture.plan.run_id, Some(1))
        .await
        .unwrap();
    assert!(controls.can_cancel);
    assert!(controls
        .cancellation_error
        .unwrap()
        .contains("injected run"));
    let settled: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM workflowCancellationTargets WHERE state='settled'",
    )
    .fetch_one(fixture.store.pool())
    .await
    .unwrap();
    assert_eq!(settled, 1, "later page targets still settle");
    let attention = fixture
        .store
        .workflow_proposal_cancellation(&proposal.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(attention.status, "attention");
    assert!(attention.error.unwrap().contains("injected proposal"));
    sqlx::query("DROP TRIGGER fail_run_settle")
        .execute(fixture.store.pool())
        .await
        .unwrap();
    sqlx::query("DROP TRIGGER fail_proposal_settle")
        .execute(fixture.store.pool())
        .await
        .unwrap();
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    assert_eq!(
        fixture
            .store
            .workflow_proposal_cancellation(&proposal.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "attention"
    );
    assert!(fixture
        .store
        .workflow_run_controls(&fixture.plan.run_id, Some(1))
        .await
        .unwrap()
        .cancellation_error
        .is_some());
    cancel.request_id = "retry".into();
    cancel.expected_sequence = 1;
    fixture
        .store
        .control_workflow_execution(&cancel)
        .await
        .unwrap();
    fixture
        .store
        .retry_workflow_proposal_cancellation(&proposal.id, 0)
        .await
        .unwrap();
    actor.wake_workflow_cancellation();
    drain(&mut actor, &mut commands).await;
    assert_eq!(
        fixture
            .store
            .workflow_run_controls(&fixture.plan.run_id, Some(1))
            .await
            .unwrap()
            .cancellation_pending,
        0
    );
    assert_eq!(
        fixture
            .store
            .workflow_proposal_cancellation(&proposal.id)
            .await
            .unwrap()
            .unwrap()
            .status,
        "settled"
    );
    assert_eq!(actor.workflow_workspace_jobs, 0);
    actor.dispose().await;
}
