use super::*;
use crate::managed_workspace::workflow::tests::completed;
use crate::terminal_host::server::{ServerActor, ServerCommand};
use alera_core::runtime::{RuntimeStore, WorkflowIntegrationState};

async fn drain(
    actor: &mut ServerActor,
    commands: &mut tokio::sync::mpsc::UnboundedReceiver<ServerCommand>,
) {
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    // Include queued ExecutionWake events even after CancellationFinished has
    // cleared the cancelling flag. A feedback loop must fail this bounded drain.
    for _ in 0..100 {
        let command = match commands.try_recv() {
            Ok(command) => command,
            Err(_) if actor.workflow_workspace_jobs == 0 => return,
            Err(_) => tokio::time::timeout_at(deadline, commands.recv())
                .await
                .unwrap()
                .unwrap(),
        };
        actor.handle(command).await;
    }
    panic!("cancelled integration recovery did not become quiescent");
}

async fn revision(store: &RuntimeStore) -> i64 {
    sqlx::query_scalar("SELECT revision FROM orchestrationBoardRevision WHERE id=1")
        .fetch_one(store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn cancelled_integration_attention_waits_for_explicit_retry_without_actor_feedback() {
    for prepared in [false, true] {
        let fixture = Fixture::new("").await;
        let target = fixture.integration().await;
        let (input, _) = completed(&fixture, "fix", "fixed\n").await;
        let integration = fixture
            .store
            .reserve_workflow_integration(&input)
            .await
            .unwrap();
        if prepared {
            let outcome =
                alera_core::git::prepare_workflow_integration(&integration.request).unwrap();
            fixture
                .store
                .record_workflow_integration_preparation(&integration.request.id, &outcome)
                .await
                .unwrap();
        }
        let repo = git2::Repository::open(&target.identity.workspace.path).unwrap();
        let head = repo.head().unwrap().target().unwrap();
        let dirty = std::path::Path::new(&target.identity.workspace.path).join("retained.txt");
        std::fs::write(&dirty, "retain user work").unwrap();
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
        let dir = tempfile::tempdir().unwrap();
        let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
        actor.runtime_store = fixture.store.clone();
        actor.runtime_dir = fixture.runtime.clone();
        actor.workflow_execution.ready = true;
        let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
        actor.inbox = inbox;
        actor.wake_workflow_execution();
        drain(&mut actor, &mut commands).await;
        let attention = fixture
            .store
            .workflow_integration(&integration.request.id)
            .await
            .unwrap();
        assert_eq!(attention.state, WorkflowIntegrationState::Attention);
        assert_eq!(std::fs::read_to_string(&dirty).unwrap(), "retain user work");
        let unchanged = revision(&fixture.store).await;
        for _ in 0..3 {
            actor.wake_workflow_execution();
            drain(&mut actor, &mut commands).await;
            assert_eq!(revision(&fixture.store).await, unchanged);
        }
        // Even after restart and manual repair, an Attention row must not be
        // inspected again until a fresh cancellation command explicitly retries.
        std::fs::remove_file(&dirty).unwrap();
        actor.runtime_store = RuntimeStore::open(&fixture.runtime).await.unwrap();
        actor.wake_workflow_execution();
        drain(&mut actor, &mut commands).await;
        assert_eq!(revision(&fixture.store).await, unchanged);
        assert_eq!(
            fixture
                .store
                .workflow_integration(&integration.request.id)
                .await
                .unwrap()
                .state,
            WorkflowIntegrationState::Attention
        );
        fixture
            .store
            .control_workflow_execution(&cancel)
            .await
            .unwrap();
        assert_eq!(revision(&fixture.store).await, unchanged);
        cancel.request_id = "retry".into();
        assert!(fixture
            .store
            .control_workflow_execution(&cancel)
            .await
            .is_err());
        assert_eq!(revision(&fixture.store).await, unchanged);
        cancel.expected_sequence = 1;
        fixture
            .store
            .control_workflow_execution(&cancel)
            .await
            .unwrap();
        let reset = fixture
            .store
            .workflow_integration(&integration.request.id)
            .await
            .unwrap();
        assert_eq!(
            reset.state,
            if prepared {
                WorkflowIntegrationState::Prepared
            } else {
                WorkflowIntegrationState::Pending
            }
        );
        assert_eq!(reset.receipt, attention.receipt);
        actor.wake_workflow_execution();
        drain(&mut actor, &mut commands).await;
        let settled = fixture
            .store
            .workflow_integration(&integration.request.id)
            .await
            .unwrap();
        assert_eq!(settled.state, WorkflowIntegrationState::Cancelled);
        assert_eq!(settled.receipt, attention.receipt);
        assert_eq!(repo.head().unwrap().target().unwrap(), head);
        let evidence: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM workflowTaskEvidence WHERE task_id=?")
                .bind(&input.task_id)
                .fetch_one(fixture.store.pool())
                .await
                .unwrap();
        assert_eq!(evidence, 0);
        let settled_revision = revision(&fixture.store).await;
        actor.wake_workflow_execution();
        drain(&mut actor, &mut commands).await;
        assert_eq!(revision(&fixture.store).await, settled_revision);
        assert_eq!(actor.managed_workspace_jobs, 0);
        assert_eq!(actor.workflow_workspace_jobs, 0);
        actor.dispose().await;
    }
}
