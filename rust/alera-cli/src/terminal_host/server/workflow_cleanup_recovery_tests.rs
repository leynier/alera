use super::*;
use crate::managed_workspace::workflow::{cleanup_preview, tests::fixture::Fixture};
use crate::terminal_host::server::actor_test_harness::test_actor;
use alera_core::runtime::{
    ControlWorkflowExecution, WorkflowCleanupState, WorkflowExecutionAction,
};

#[tokio::test]
async fn workflow_cleanup_startup_reconciles_git_receipt_without_repeating_retirement() {
    let _serial = CLEANUP_TEST_LOCK.lock().await;
    let fixture = Fixture::new("").await;
    let resource = fixture.integration().await;
    let task = fixture.task("fix").await;
    cancel(&fixture).await;
    let preview = cleanup_preview::preview(
        &fixture.store,
        cleanup_preview::CleanupSelection {
            id: uuid::Uuid::new_v4().to_string(),
            run_id: fixture.plan.run_id.clone(),
            resources: [&resource, &task]
                .iter()
                .map(|record| cleanup_preview::CleanupResourceSelection {
                    workspace_id: record.identity.workspace.id.clone(),
                    remove_branch: false,
                })
                .collect(),
        },
    )
    .await
    .unwrap();
    let prepared = crate::managed_workspace::workflow::cleanup::prepare(
        &fixture.store,
        &fixture.runtime,
        &preview.id,
        &preview.digest,
    )
    .await
    .unwrap();
    let first = &prepared.claim.preview.items[0];
    crate::managed_workspace::workflow::cleanup::retire(&fixture.store, &prepared, first)
        .await
        .unwrap();
    // A completed resource's old path may have been reused. Recovery must not
    // touch it while finishing a different resource in the same confirmation.
    std::fs::create_dir_all(&first.identity.workspace.path).unwrap();
    let preserved = std::path::Path::new(&first.identity.workspace.path).join("new-owner.txt");
    std::fs::write(&preserved, "unrelated replacement").unwrap();
    let pending = &prepared.claim.preview.items[1];
    alera_core::git::remove_workflow_cleanup_resource(
        &pending.identity.repo_path,
        &alera_core::git::WorkflowCleanupRemoval {
            cleanup_id: preview.id.clone(),
            resource_id: pending.identity.workspace.id.clone(),
            path: pending.identity.workspace.path.clone(),
            base_sha: pending.identity.base_sha.clone(),
            expected_head: pending.git.head_sha.clone(),
            remove_branch: false,
        },
    )
    .unwrap();
    assert!(fixture
        .store
        .find_workspace(&pending.identity.workspace.id)
        .await
        .unwrap()
        .is_some());
    drop(prepared);
    // Restart with a new store connection after Git committed but SQLite did not.
    let actor_dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&actor_dir, Default::default(), Default::default()).await;
    actor.runtime_store = RuntimeStore::open(&fixture.runtime).await.unwrap();
    actor.runtime_dir = fixture.runtime.clone();
    startup(&mut actor).await;
    let status = fixture
        .store
        .workflow_cleanup_status(&preview.id)
        .await
        .unwrap();
    assert_eq!(status.state, WorkflowCleanupState::Retired);
    assert_eq!(status.retired_workspace_ids.len(), 2);
    for item in &preview.items {
        assert!(fixture
            .store
            .find_workspace(&item.identity.workspace.id)
            .await
            .unwrap()
            .is_none());
        assert!(fixture
            .store
            .workflow_workspace(&item.identity.workspace.id)
            .await
            .is_ok());
    }
    assert_eq!(
        std::fs::read_to_string(preserved).unwrap(),
        "unrelated replacement"
    );
    startup(&mut actor).await;
    assert_eq!(
        fixture
            .store
            .workflow_cleanup_status(&preview.id)
            .await
            .unwrap()
            .retired_workspace_ids
            .len(),
        2
    );
}

#[tokio::test]
async fn workflow_cleanup_startup_preserves_unconfirmed_and_attention_resources() {
    let _serial = CLEANUP_TEST_LOCK.lock().await;
    let fixture = Fixture::new("").await;
    let resource = fixture.integration().await;
    cancel(&fixture).await;
    let preview = cleanup_preview::preview(
        &fixture.store,
        cleanup_preview::CleanupSelection {
            id: uuid::Uuid::new_v4().to_string(),
            run_id: fixture.plan.run_id.clone(),
            resources: vec![cleanup_preview::CleanupResourceSelection {
                workspace_id: resource.identity.workspace.id.clone(),
                remove_branch: false,
            }],
        },
    )
    .await
    .unwrap();
    let actor_dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&actor_dir, Default::default(), Default::default()).await;
    actor.runtime_store = fixture.store.clone();
    actor.runtime_dir = fixture.runtime.clone();
    startup(&mut actor).await;
    assert_eq!(
        fixture
            .store
            .workflow_cleanup_status(&preview.id)
            .await
            .unwrap()
            .state,
        WorkflowCleanupState::Preview
    );
    let prepared = crate::managed_workspace::workflow::cleanup::prepare(
        &fixture.store,
        &fixture.runtime,
        &preview.id,
        &preview.digest,
    )
    .await
    .unwrap();
    drop(prepared);
    let mut live =
        crate::terminal_host::session::Session::driver_test_stub("cleanup-live-owner", 80, 24);
    live.workspace_id = resource.identity.workspace.id.clone();
    actor.sessions.insert("cleanup-live-owner".into(), live);
    startup(&mut actor).await;
    assert_eq!(
        fixture
            .store
            .workflow_cleanup_status(&preview.id)
            .await
            .unwrap()
            .state,
        WorkflowCleanupState::Attention
    );
    assert!(actor.sessions["cleanup-live-owner"].running());
    actor.sessions.remove("cleanup-live-owner");
    startup(&mut actor).await;
    assert_eq!(
        fixture
            .store
            .workflow_cleanup_status(&preview.id)
            .await
            .unwrap()
            .state,
        WorkflowCleanupState::Attention
    );
    assert!(std::path::Path::new(&resource.identity.workspace.path).exists());
    assert!(fixture
        .store
        .find_workspace(&resource.identity.workspace.id)
        .await
        .unwrap()
        .is_some());
}

async fn cancel(fixture: &Fixture) {
    fixture
        .store
        .control_workflow_execution(&ControlWorkflowExecution {
            request_id: "cancel-for-cleanup-recovery".into(),
            run_id: fixture.plan.run_id.clone(),
            revision: 1,
            expected_sequence: 0,
            action: WorkflowExecutionAction::Cancel,
        })
        .await
        .unwrap();
}

async fn startup(actor: &mut super::super::ServerActor) {
    actor.workflow_execution.ready = false;
    let (inbox, mut commands) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    actor.start_workflow_workspace_recovery();
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
    loop {
        let command = tokio::time::timeout_at(deadline, commands.recv())
            .await
            .unwrap()
            .unwrap();
        if matches!(command, ServerCommand::WorkflowWorkspaceRecoveryFinished) {
            // The real handler starts the execution pump next. Keep this fixture
            // focused on startup reconciliation without spawning unrelated work.
            actor.managed_workspace_jobs -= 1;
            assert_eq!(actor.managed_workspace_jobs, 0);
            return;
        }
        actor.handle(command).await;
    }
}
